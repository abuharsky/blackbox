part of blackbox;

/// A minimal, synchronous key-value store for persistence.
/// (MVP) Keep it sync so boxes/graph can be created synchronously.
abstract interface class PersistentStore {
  Object? read(String key);
  void write(String key, Object? value);
  void delete(String key);
}

/// Encode/decode box values to/from the [PersistentStore].
/// For primitives you can use [IdentityCodec].
abstract interface class PersistentCodec<T> {
  Object? encode(T value);
  T decode(Object? stored);
}

final class IdentityCodec<T> implements PersistentCodec<T> {
  const IdentityCodec();
  @override
  Object? encode(T value) => value;

  @override
  T decode(Object? stored) => stored as T;
}

final class BlackboxPersistence {
  static PersistentStore? _store;

  static bool get isInitialized => _store != null;

  static void init(PersistentStore store) {
    final existing = _store;
    if (existing == null) {
      _store = store;
      return;
    }
    if (identical(existing, store)) return;

    throw StateError(
      'BlackboxPersistence is already initialized with '
      '${existing.runtimeType}. Reset it in tests before registering '
      '${store.runtimeType}.',
    );
  }

  static PersistentStore requireStore() {
    final store = _store;
    if (store != null) return store;

    throw StateError(
      'BlackboxPersistence is not initialized. Call your platform '
      'persistence preload() before creating persistent boxes.',
    );
  }

  static void reset() {
    _store = null;
  }
}

class Persistent<O> {
  final String key;
  final PersistentStore store;
  final PersistentCodec<O> codec;

  const Persistent({
    required this.key,
    required this.store,
    required this.codec,
  });

  O? load() {
    final raw = store.read(key);
    if (raw == null) return null;
    try {
      return codec.decode(raw);
    } catch (_) {
      return null;
    }
  }

  void attach(OutputSource<O> box) {
    box.listen((output) {
      if (output is AsyncData<O>) {
        if (output.value == null) {
          store.delete(key);
        } else {
          store.write(key, codec.encode(output.value));
        }
      } else if (output is SyncOutput<O>) {
        if (output.value == null) {
          store.delete(key);
        } else {
          store.write(key, codec.encode(output.value));
        }
      }
    });
  }
}
