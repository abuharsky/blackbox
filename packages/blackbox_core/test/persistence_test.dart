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

/// Sync box with input-dependent persist key (resolved once at init).
final class _SyncPerUserBox extends Box<String, int>
    with Persisted<String, int> {
  _SyncPerUserBox(super.input);

  @override
  String persistKeyFor(String input) => 'user:$input';

  @override
  int compute(String input, int? previous) => previous ?? 0;
}

/// Async box with persist key resolved once at init.
final class _AsyncPerUserBox extends AsyncBox<String, int>
    with AsyncPersisted<String, int> {
  _AsyncPerUserBox(super.input);

  @override
  String persistKeyFor(String input) => 'async_user:$input';

  @override
  Future<int> compute(String input, int? previous) =>
      Future.value(previous ?? -1);
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

  group('input-dependent persist key (resolved once)', () {
    test('sync box resolves key from initial input and restores cached value',
        () {
      final store = _MemoryStore()
        ..write('user:alice', {
          'v': 42,
          'ts': DateTime(2026, 4, 8).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);

      final box = _SyncPerUserBox('alice');
      expect(box.value, 42);
    });

    test('different input produces different key and independent cache', () {
      final now = DateTime(2026, 4, 8, 12);
      final store = _MemoryStore()
        ..write('user:alice', {
          'v': 42,
          'ts': now.millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final boxAlice = _SyncPerUserBox('alice');
      final boxBob = _SyncPerUserBox('bob');

      expect(boxAlice.value, 42);
      expect(boxBob.value, 0); // no cache for bob, defaults to 0

      // Bob's value is persisted under his own key
      expect(store.read('user:bob'), {
        'v': 0,
        'ts': now.millisecondsSinceEpoch,
      });
      // Alice's cache is untouched
      expect((store.read('user:alice') as Map)['v'], 42);
    });

    test('async box resolves key from initial input and restores cached value',
        () async {
      final now = DateTime(2026, 4, 8, 12);
      final store = _MemoryStore()
        ..write('async_user:alice', {
          'v': 99,
          'ts': now.millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _AsyncPerUserBox('alice');

      await Future<void>.delayed(Duration.zero);

      expect(box.output, isA<AsyncData<int>>());
      expect((box.output as AsyncData<int>).value, 99);
    });
  });
}
