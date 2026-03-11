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
}
