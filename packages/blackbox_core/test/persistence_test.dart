import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

final class _MemoryStore implements PersistentStore {
  final Map<String, Object?> _values = <String, Object?>{};

  @override
  Object? read(String key) => _values[key];

  @override
  void write(String key, Object? value) {
    _values[key] = value;
  }

  @override
  void delete(String key) {
    _values.remove(key);
  }
}

final class _BoolCodec extends PersistentCodec<bool> {
  const _BoolCodec();

  @override
  Object? encode(bool value) => value ? 1 : 0;

  @override
  bool decode(Object? stored) => stored == 1;
}

final class _StringCodec extends PersistentCodec<String> {
  const _StringCodec();

  @override
  Object? encode(String value) => value.toUpperCase();

  @override
  String decode(Object? stored) => stored as String;
}

final class _NullableStringCodec extends PersistentCodec<String?> {
  const _NullableStringCodec();

  @override
  Object? encode(String? value) => value;

  @override
  String? decode(Object? stored) => stored as String?;
}

/// Sync box with input-dependent persist key.
final class _SyncPerUserBox extends Box<String, int>
    with Persisted<String, int> {
  _SyncPerUserBox(super.input);

  @override
  String persistKeyFor(String input) => 'user:$input';

  @override
  int compute(String input, int? previous) => previous ?? 0;
}

/// Upstream box that drives the user id.
final class _UserIdBox extends NoInputBox<String> {
  String _id;
  _UserIdBox(this._id);

  @override
  String compute(String? previous) => _id;

  void setId(String id) => action(() => _id = id);
}

/// Async box with input-dependent persist key and cache TTL.
final class _AsyncPerUserBox extends AsyncBox<String, int>
    with AsyncPersisted<String, int> {
  final Map<String, Completer<int>> _completers = {};

  _AsyncPerUserBox(super.input);

  @override
  String persistKeyFor(String input) => 'async_user:$input';

  @override
  Duration? get cacheTtl => const Duration(minutes: 5);

  Completer<int> completerFor(String input) =>
      _completers.putIfAbsent(input, () => Completer<int>());

  @override
  Future<int> compute(String input, int? previous) {
    if (previous != null) return Future.value(previous);
    return completerFor(input).future;
  }
}

final class _PersistedCounterBox extends NoInputBox<int>
    with Persisted<void, int> {
  int _value;

  _PersistedCounterBox({int initial = 0})
      : _value = initial,
        super();

  @override
  String persistKeyFor(void _) => 'counter';

  @override
  int compute(int? previous) => previous ?? _value;

  void setValue(int value) => action(() {
        _value = value;
      });
}

void main() {
  tearDown(() {
    BlackboxPersistence.reset();
  });

  test('BlackboxPersistence.requireStore throws before init', () {
    expect(
      BlackboxPersistence.requireStore,
      throwsA(isA<StateError>()),
    );
  });

  test('BlackboxPersistence exposes the initialized store', () {
    final store = _MemoryStore();

    BlackboxPersistence.init(store);
    BlackboxPersistence.init(store);

    expect(BlackboxPersistence.isInitialized, isTrue);
    expect(identical(BlackboxPersistence.requireStore(), store), isTrue);
  });

  test('BlackboxPersistence rejects a different store after init', () {
    BlackboxPersistence.init(_MemoryStore());

    expect(
      () => BlackboxPersistence.init(_MemoryStore()),
      throwsA(isA<StateError>()),
    );
  });

  test('BlackboxPersistence.registerCodec registers codecs by valueType', () {
    const boolCodec = _BoolCodec();
    const stringCodec = _StringCodec();
    const nullableStringCodec = _NullableStringCodec();

    BlackboxPersistence.registerCodec(boolCodec);
    BlackboxPersistence.registerCodec(stringCodec);
    BlackboxPersistence.registerCodec(nullableStringCodec);

    expect(identical(BlackboxPersistence.codecFor<bool>(), boolCodec), isTrue);
    expect(
      identical(BlackboxPersistence.codecFor<String>(), stringCodec),
      isTrue,
    );
    expect(
      identical(
        BlackboxPersistence.codecFor<String?>(),
        nullableStringCodec,
      ),
      isTrue,
    );
  });

  test('BlackboxPersistence.init accepts multiple codecs at once', () {
    const boolCodec = _BoolCodec();
    const stringCodec = _StringCodec();
    const nullableStringCodec = _NullableStringCodec();

    BlackboxPersistence.init(
      _MemoryStore(),
      codecs: [
        boolCodec,
        stringCodec,
        nullableStringCodec,
      ],
    );

    expect(identical(BlackboxPersistence.codecFor<bool>(), boolCodec), isTrue);
    expect(
      identical(BlackboxPersistence.codecFor<String>(), stringCodec),
      isTrue,
    );
    expect(
      identical(
        BlackboxPersistence.codecFor<String?>(),
        nullableStringCodec,
      ),
      isTrue,
    );
  });

  test('persistent boxes restore legacy raw values', () {
    final store = _MemoryStore()..write('counter', 5);

    BlackboxPersistence.init(store);

    final box = _PersistedCounterBox();

    expect(box.value, 5);
  });

  test('persistent boxes save values with timestamp envelope', () {
    final store = _MemoryStore();
    final now = DateTime(2026, 4, 8, 12);

    BlackboxPersistence.init(store);
    BlackboxPersistence.now = () => now;

    final box = _PersistedCounterBox(initial: 7);

    expect(
      store.read('counter'),
      {
        'v': 7,
        'ts': now.millisecondsSinceEpoch,
      },
    );

    box.setValue(9);

    expect(
      store.read('counter'),
      {
        'v': 9,
        'ts': now.millisecondsSinceEpoch,
      },
    );
  });

  group('input-driven key switching', () {
    Future<void> flushMicrotasks([int times = 8]) async {
      for (var i = 0; i < times; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('sync box restores cached value from new key on input change',
        () async {
      final now = DateTime(2026, 4, 8, 12);
      final store = _MemoryStore()
        ..write('user:1', {
          'v': 10,
          'ts': now.millisecondsSinceEpoch,
        })
        ..write('user:2', {
          'v': 20,
          'ts': now.millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final userId = _UserIdBox('1');
      final perUser = _SyncPerUserBox('1');

      final graph = Graph.builder()
          .add(userId)
          .add(perUser, input: (d) => d.whenReady(userId))
          .build();

      await flushMicrotasks();

      // Starts with cached value for user:1
      expect(perUser.value, 10);

      // Switch to user:2 — should restore cached 20
      userId.setId('2');
      await flushMicrotasks();

      expect(perUser.value, 20);

      // Verify user:2 store was NOT rewritten (skip saved the timestamp)
      expect(
        store.read('user:2'),
        {'v': 20, 'ts': now.millisecondsSinceEpoch},
      );

      graph.dispose();
    });

    test('sync box does not overwrite new key with old value on switch',
        () async {
      final now = DateTime(2026, 4, 8, 12);
      final store = _MemoryStore()
        ..write('user:1', {
          'v': 10,
          'ts': now.millisecondsSinceEpoch,
        });
      // user:2 has no cached value

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final userId = _UserIdBox('1');
      final perUser = _SyncPerUserBox('1');

      final graph = Graph.builder()
          .add(userId)
          .add(perUser, input: (d) => d.whenReady(userId))
          .build();

      await flushMicrotasks();
      expect(perUser.value, 10);

      // Switch to user:2 — no cached value, compute returns 0
      userId.setId('2');
      await flushMicrotasks();

      expect(perUser.value, 0);
      // The new value 0 should be saved under user:2
      expect(store.read('user:2'), {
        'v': 0,
        'ts': now.millisecondsSinceEpoch,
      });
      // user:1 should still have its original value
      expect((store.read('user:1') as Map)['v'], 10);

      graph.dispose();
    });

    test(
        'async box restores cached value and preserves TTL timestamp on input change',
        () async {
      final staleTime = DateTime(2026, 4, 8, 10); // 2 hours ago
      final now = DateTime(2026, 4, 8, 12);
      final store = _MemoryStore()
        ..write('async_user:1', {
          'v': 100,
          'ts': now.millisecondsSinceEpoch,
        })
        ..write('async_user:2', {
          'v': 200,
          'ts': staleTime.millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final userId = _UserIdBox('1');
      final perUser = _AsyncPerUserBox('1');

      final graph = Graph.builder()
          .add(userId)
          .add(perUser, input: (d) => d.whenReady(userId))
          .build();

      await flushMicrotasks();

      // Starts with cached value for async_user:1
      expect(perUser.output, isA<AsyncData<int>>());
      expect((perUser.output as AsyncData<int>).value, 100);

      // Switch to user:2 — should restore cached 200
      userId.setId('2');
      await flushMicrotasks();

      expect(perUser.output, isA<AsyncData<int>>());
      expect((perUser.output as AsyncData<int>).value, 200);

      // Verify async_user:2 was NOT rewritten — original timestamp preserved
      final stored = store.read('async_user:2') as Map;
      expect(stored['v'], 200);
      expect(stored['ts'], staleTime.millisecondsSinceEpoch);

      // persistedAt should reflect the original stale timestamp
      expect(perUser.persistedAt, staleTime);

      graph.dispose();
    });
  });
}
