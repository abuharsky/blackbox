import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

Future<void> flushMicrotasks([int times = 6]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Stop-list per store: always-available sync value, background fetch.
final class StopListBox extends CachedValueBox<String, List<String>> {
  int fetches = 0;
  bool fail;
  Map<String, List<String>> data = {
    's1': ['burger'],
    's2': ['cola'],
  };

  StopListBox({required super.input, this.fail = false})
      : super(initialValue: const []);

  @override
  Cache<String, List<String>> get cache => Cache(
        ttl: const Duration(minutes: 1),
        persistFor: (store) => 'stop:$store',
        codec: const StringListCodec(),
      );

  @override
  Future<List<String>> fetch(String store) async {
    fetches++;
    if (fail) throw Exception('network down');
    return data[store] ?? const [];
  }
}

/// In-memory only, no-input flavor via `CachedValueBox<void, O>`.
final class ConfigBox extends CachedValueBox<void, int> {
  int fetches = 0;

  ConfigBox() : super(input: null, initialValue: 0);

  @override
  Cache<void, int> get cache => const Cache(ttl: Duration(minutes: 1));

  @override
  Future<int> fetch(void input) async {
    fetches++;
    return fetches * 10;
  }
}

final class StringListCodec extends PersistentCodec<List<String>> {
  const StringListCodec();
  @override
  Object? encode(List<String> value) => value;
  @override
  List<String> decode(Object? stored) =>
      (stored as List<dynamic>).cast<String>();
}

final class MemStore implements PersistentStore {
  final Map<String, Object?> values = {};
  @override
  Object? read(String key) => values[key];
  @override
  void write(String key, Object? value) => values[key] = value;
  @override
  void delete(String key) => values.remove(key);
}

void main() {
  late MemStore store;
  var currentTime = DateTime(2026, 1, 1, 12);

  void advance(Duration d) => currentTime = currentTime.add(d);

  Map<String, Object?> envelope(Object? v, DateTime at) => {
        'v': v,
        'ts': at.millisecondsSinceEpoch,
      };

  setUp(() {
    BlackboxPersistence.reset();
    store = MemStore();
    BlackboxPersistence.init(store);
    currentTime = DateTime(2026, 1, 1, 12);
    BlackboxPersistence.now = () => currentTime;
  });

  tearDown(BlackboxPersistence.reset);

  group('CachedValueBox basics', () {
    test('always has a sync value; background fetch updates and saves',
        () async {
      final box = StopListBox(input: 's1');
      expect(box.value, isEmpty, reason: 'initialValue visible immediately');

      await flushMicrotasks();
      expect(box.value, ['burger']);
      expect(box.fetches, 1);
      expect((store.values['stop:s1'] as Map<String, Object?>)['v'],
          ['burger']);
    });

    test('missing initialValue throws a clear error', () {
      expect(
        () => ConfigBoxWithoutInitial(),
        throwsA(isA<StateError>()),
      );
    });

    test('fresh disk restore: instant value, no fetch', () async {
      store.values['stop:s1'] = envelope(['old-burger'], currentTime);

      final box = StopListBox(input: 's1');
      expect(box.value, ['old-burger']);
      await flushMicrotasks();
      expect(box.fetches, 0);
    });

    test('expired disk restore: stale visible, refreshed in background',
        () async {
      store.values['stop:s1'] =
          envelope(['stale'], currentTime.subtract(const Duration(minutes: 5)));

      final box = StopListBox(input: 's1');
      expect(box.value, ['stale']);

      await flushMicrotasks();
      expect(box.fetches, 1);
      expect(box.value, ['burger']);
    });

    test('fetch errors are swallowed; previous value stays; TTL stamped',
        () async {
      final box = StopListBox(input: 's1', fail: true);
      await flushMicrotasks();

      expect(box.value, isEmpty, reason: 'initial value preserved');
      expect(box.fetches, 1);

      // Immediate access must not retry in a tight loop.
      box.value;
      await flushMicrotasks();
      expect(box.fetches, 1);

      // After TTL, access retries.
      advance(const Duration(minutes: 2));
      box.fail = false;
      box.value;
      await flushMicrotasks();
      expect(box.fetches, 2);
      expect(box.value, ['burger']);
    });

    test('TTL expiry on access triggers background refetch', () async {
      final box = StopListBox(input: 's1');
      await flushMicrotasks();
      expect(box.fetches, 1);

      box.data = {
        's1': ['burger', 'fries'],
      };
      advance(const Duration(minutes: 2));
      expect(box.value, ['burger'], reason: 'stale until refresh lands');

      await flushMicrotasks();
      expect(box.fetches, 2);
      expect(box.value, ['burger', 'fries']);
    });
  });

  group('CachedValueBox input change (persistFor)', () {
    test('empty new slot: old value visible while fetching the new input',
        () async {
      final box = StopListBox(input: 's1');
      await flushMicrotasks();
      expect(box.value, ['burger']);

      updateInputForTest(box, 's2');
      expect(box.value, ['burger'], reason: 'no flicker to initialValue');

      await flushMicrotasks();
      expect(box.value, ['cola']);
      expect((store.values['stop:s1'] as Map<String, Object?>)['v'],
          ['burger'], reason: 'old slot intact');
      expect((store.values['stop:s2'] as Map<String, Object?>)['v'],
          ['cola']);
    });

    test('fresh new slot: instant swap, no fetch', () async {
      store.values['stop:s2'] = envelope(['cached-cola'], currentTime);

      final box = StopListBox(input: 's1');
      await flushMicrotasks();
      final fetchesBefore = box.fetches;

      updateInputForTest(box, 's2');
      expect(box.value, ['cached-cola']);
      await flushMicrotasks();
      expect(box.fetches, fetchesBefore);
    });
  });

  group('CachedValueBox manual controls', () {
    test('refresh() bypasses TTL; invalidateCache() clears the slot',
        () async {
      final box = StopListBox(input: 's1');
      await flushMicrotasks();
      expect(box.fetches, 1);

      box.data = {
        's1': ['new-burger'],
      };
      await box.refresh();
      expect(box.fetches, 2);
      expect(box.value, ['new-burger']);

      await box.invalidateCache();
      expect(box.fetches, 3);
      expect((store.values['stop:s1'] as Map<String, Object?>)['v'],
          ['new-burger']);
    });
  });

  group('CachedValueBox no-input flavor', () {
    test('CachedValueBox<void, O> works with input: null', () async {
      final box = ConfigBox();
      expect(box.value, 0);
      await flushMicrotasks();
      expect(box.value, 10);
      expect(store.values, isEmpty, reason: 'in-memory cache only');
    });
  });
}

/// Missing initialValue must fail fast with a clear message.
final class ConfigBoxWithoutInitial extends CachedValueBox<void, int> {
  ConfigBoxWithoutInitial() : super(input: null);

  @override
  Cache<void, int> get cache => const Cache(ttl: Duration(minutes: 1));

  @override
  Future<int> fetch(void input) async => 1;
}
