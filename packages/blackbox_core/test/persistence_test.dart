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

final class _PersistedCounterBox extends NoInputBox<int> {
  int _value;

  _PersistedCounterBox({int initial = 0})
      : _value = initial,
        super(persistKey: 'counter');

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
}
