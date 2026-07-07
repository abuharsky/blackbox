import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

Future<void> flushMicrotasks([int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _MemoryStore implements PersistentStore {
  final Map<String, Object?> values = <String, Object?>{};

  @override
  Object? read(String key) => values[key];

  @override
  void write(String key, Object? value) => values[key] = value;

  @override
  void delete(String key) => values.remove(key);
}

Object? storedValue(_MemoryStore store, String key) {
  final raw = store.values[key];
  if (raw is Map) return raw['v'];
  return raw;
}

final class _StringListCodec extends PersistentCodec<List<String>> {
  const _StringListCodec();

  @override
  Object? encode(List<String> value) => value;

  @override
  List<String> decode(Object? stored) => (stored as List).cast<String>();
}

// ---------------------------------------------------------------------------
// Restore precedence: disk wins over initialValue
// ---------------------------------------------------------------------------

final class _SyncDefaultBox extends NoInputBox<int> with Persisted<void, int> {
  _SyncDefaultBox() : super(initialValue: 100);

  @override
  String persistKeyFor(void _) => 'sync_default';

  @override
  int compute(int? previous) => previous ?? -1;
}

final class _AsyncDefaultBox extends NoInputAsyncBox<int>
    with AsyncPersisted<void, int> {
  _AsyncDefaultBox() : super(initialValue: 100);

  @override
  String persistKeyFor(void _) => 'async_default';

  @override
  Future<int> compute(int? previous) async => previous ?? -1;
}

// ---------------------------------------------------------------------------
// Rekey: per-user cart with internal mutable state (README pattern)
// ---------------------------------------------------------------------------

final class _CartBox extends Box<String, List<String>>
    with Persisted<String, List<String>> {
  List<String> _items = [];

  _CartBox(super.input);

  @override
  String persistKeyFor(String user) => 'cart:$user';

  @override
  void onFirstCompute(String input, List<String>? previous) {
    _items = List.of(previous ?? const []);
  }

  @override
  List<String> compute(String input, List<String>? previous) => _items;

  void add(String item) => action(() => _items.add(item));
}

final class _AsyncUserBox extends AsyncBox<String, int>
    with AsyncPersisted<String, int> {
  int computeCalls = 0;

  _AsyncUserBox(super.input);

  @override
  String persistKeyFor(String user) => 'async_user:$user';

  @override
  Future<int> compute(String input, int? previous) async {
    computeCalls++;
    return previous ?? -1;
  }
}

final class _CachedUserBox extends Box<String, int>
    with Persisted<String, int>, ManagedCache<String, int> {
  final Map<String, int> remote;

  _CachedUserBox(super.input, {required this.remote})
      : super(initialValue: 0);

  @override
  String persistKeyFor(String user) => 'stop:$user';

  @override
  Duration get cacheTtl => const Duration(minutes: 5);

  @override
  Future<int> fetch(String input) async => remote[input]!;
}

// ---------------------------------------------------------------------------
// ValueStateBox + Persisted (doc pattern)
// ---------------------------------------------------------------------------

final class _ThemeBox extends ValueStateBox<String>
    with Persisted<String, String> {
  _ThemeBox() : super('system');

  @override
  String persistKeyFor(String _) => 'theme';
}

void main() {
  late _MemoryStore store;

  setUp(() {
    BlackboxPersistence.reset();
    store = _MemoryStore();
  });

  tearDown(BlackboxPersistence.reset);

  group('restore precedence (disk wins over initialValue)', () {
    test('sync box restores disk value even when initialValue is set', () {
      store.write('sync_default', {'v': 42, 'ts': 0});
      BlackboxPersistence.init(store);

      expect(_SyncDefaultBox().value, 42);
    });

    test('sync box falls back to initialValue when slot is empty', () {
      BlackboxPersistence.init(store);

      expect(_SyncDefaultBox().value, 100);
    });

    test('async box restores disk value even when initialValue is set',
        () async {
      store.write('async_default', {'v': 42, 'ts': 0});
      BlackboxPersistence.init(store);

      final box = _AsyncDefaultBox();
      await flushMicrotasks();

      expect((box.output as AsyncData<int>).value, 42);
    });

    test('async box falls back to initialValue when slot is empty', () async {
      BlackboxPersistence.init(store);

      final box = _AsyncDefaultBox();
      await flushMicrotasks();

      expect((box.output as AsyncData<int>).value, 100);
    });
  });

  group('rekey re-initializes the box in the new slot', () {
    test('internal state does not leak into an empty slot', () {
      BlackboxPersistence.init(store, codecs: const [_StringListCodec()]);

      final cart = _CartBox('alice');
      cart.add('apple');
      expect(cart.value, ['apple']);
      expect(storedValue(store, 'cart:alice'), ['apple']);

      updateInputForTest(cart, 'bob');

      expect(cart.value, isEmpty, reason: 'bob must not see alice\'s cart');
      expect(storedValue(store, 'cart:bob'), isEmpty,
          reason: 'alice\'s items must not be saved under bob\'s key');
      expect(storedValue(store, 'cart:alice'), ['apple'],
          reason: 'alice\'s slot must stay intact');
    });

    test('switching back restores the previous slot and rehydrates state', () {
      BlackboxPersistence.init(store, codecs: const [_StringListCodec()]);

      final cart = _CartBox('alice');
      cart.add('apple');

      updateInputForTest(cart, 'bob');
      cart.add('banana');
      expect(cart.value, ['banana']);

      updateInputForTest(cart, 'alice');
      expect(cart.value, ['apple']);

      // Internal state was rehydrated, not just the output: mutations
      // continue from the restored list.
      cart.add('orange');
      expect(cart.value, ['apple', 'orange']);
      expect(storedValue(store, 'cart:alice'), ['apple', 'orange']);
      expect(storedValue(store, 'cart:bob'), ['banana']);
    });

    test('async box severs old slot state on rekey to an empty slot',
        () async {
      store.write('async_user:alice', {'v': 42, 'ts': 0});
      BlackboxPersistence.init(store);

      final box = _AsyncUserBox('alice');
      await flushMicrotasks();
      expect((box.output as AsyncData<int>).value, 42);

      final emissions = <AsyncOutput<int>>[];
      box.listen((o) => emissions.add(o as AsyncOutput<int>),
          skipFirst: true);

      updateAsyncInputForTest(box, 'bob');
      await flushMicrotasks();

      expect((box.output as AsyncData<int>).value, -1,
          reason: 'bob must compute fresh, not inherit alice\'s 42');
      expect(storedValue(store, 'async_user:bob'), -1);
      expect(storedValue(store, 'async_user:alice'), 42);

      for (final o in emissions) {
        final leaked = switch (o) {
          AsyncLoading<int>(:final previousData) => previousData == 42,
          AsyncError<int>(:final previousData) => previousData == 42,
          AsyncData<int>(:final value) => value == 42,
        };
        expect(leaked, isFalse,
            reason: 'alice\'s value must not appear after rekey: $o');
      }
    });

    test('async box restores cached slot on rekey without recompute',
        () async {
      store.write('async_user:carol', {'v': 7, 'ts': 0});
      BlackboxPersistence.init(store);

      final box = _AsyncUserBox('dave');
      await flushMicrotasks();
      expect((box.output as AsyncData<int>).value, -1);
      final callsBefore = box.computeCalls;

      updateAsyncInputForTest(box, 'carol');
      await flushMicrotasks();

      expect((box.output as AsyncData<int>).value, 7);
      expect(box.computeCalls, callsBefore,
          reason: 'cached slot is shown without a refetch');
    });

    test('ManagedCache adopts the new slot or the constructor default',
        () async {
      store.write('stop:alice', {'v': 1, 'ts': 0});
      BlackboxPersistence.init(store);

      final box = _CachedUserBox('alice', remote: {'alice': 10, 'bob': 20});
      expect(box.value, 1, reason: 'restored from alice\'s slot');

      updateInputForTest(box, 'bob');
      expect(box.value, 0,
          reason: 'empty slot falls back to initialValue, not alice\'s 1');
      expect(storedValue(store, 'stop:bob'), 0,
          reason: 'alice\'s value must not be persisted under bob\'s key');

      await flushMicrotasks();
      expect(box.value, 20, reason: 'background fetch lands for bob');
      expect(storedValue(store, 'stop:bob'), 20);
      expect(storedValue(store, 'stop:alice'), 1);
    });
  });

  group('ValueStateBox + Persisted (documented pattern)', () {
    test('restores the persisted value instead of the constructor default',
        () {
      store.write('theme', {'v': 'dark', 'ts': 0});
      BlackboxPersistence.init(store);

      expect(_ThemeBox().value, 'dark');
    });

    test('uses the constructor default on first boot and then persists', () {
      BlackboxPersistence.init(store);

      final box = _ThemeBox();
      expect(box.value, 'system');

      updateInputForTest(box, 'dark');
      expect(box.value, 'dark');
      expect(storedValue(store, 'theme'), 'dark');
    });

    test('graph-driven updates still win after restore', () {
      store.write('theme', {'v': 'dark', 'ts': 0});
      BlackboxPersistence.init(store);

      final box = _ThemeBox();
      expect(box.value, 'dark');

      updateInputForTest(box, 'light');
      expect(box.value, 'light');
      expect(storedValue(store, 'theme'), 'light');
    });
  });
}
