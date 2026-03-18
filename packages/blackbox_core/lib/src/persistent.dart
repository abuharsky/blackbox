part of blackbox;

/// A minimal, synchronous key-value store for persistence.
abstract interface class PersistentStore {
  Object? read(String key);
  void write(String key, Object? value);
  void delete(String key);
}

/// Encode/decode box values to/from the [PersistentStore].
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
  static final Map<Type, PersistentCodec<dynamic>> _codecs = {};

  static bool get isInitialized => _store != null;

  static void init(
    PersistentStore store, {
    Map<Type, PersistentCodec<dynamic>> codecs = const {},
  }) {
    final existing = _store;
    if (existing == null) {
      _store = store;
      _codecs.addAll(codecs);
      return;
    }
    if (identical(existing, store)) {
      _codecs.addAll(codecs);
      return;
    }

    throw StateError(
      'BlackboxPersistence is already initialized with '
      '${existing.runtimeType}. Reset it in tests before registering '
      '${store.runtimeType}.',
    );
  }

  static void registerCodec<T>(PersistentCodec<T> codec) {
    _codecs[T] = codec;
  }

  static PersistentStore requireStore() {
    final store = _store;
    if (store != null) return store;

    throw StateError(
      'BlackboxPersistence is not initialized. Call your platform '
      'persistence preload() before creating persistent boxes.',
    );
  }

  static PersistentCodec<T> codecFor<T>() {
    final codec = _codecs[T];
    if (codec != null) return codec as PersistentCodec<T>;

    // Identity codec for primitive types.
    if (T == int || T == double || T == String || T == bool) {
      return IdentityCodec<T>();
    }

    throw StateError(
      'No PersistentCodec registered for type $T. '
      'Call BlackboxPersistence.init(store, codecs: {$T: ...}) '
      'or BlackboxPersistence.registerCodec<$T>(...).',
    );
  }

  static void reset() {
    _store = null;
    _codecs.clear();
  }

  /// Resolve persistence for a given key: load cached value + start saving.
  static _ResolvedPersistence<O> _resolve<O>(String key) {
    final store = requireStore();
    final codec = codecFor<O>();
    final raw = store.read(key);
    O? cached;
    if (raw != null) {
      try {
        cached = codec.decode(raw);
      } catch (_) {
        cached = null;
      }
    }
    return _ResolvedPersistence<O>(
      cached: cached,
      save: (O? value) {
        if (value == null) {
          store.delete(key);
        } else {
          store.write(key, codec.encode(value));
        }
      },
    );
  }
}

final class _ResolvedPersistence<O> {
  final O? cached;
  final void Function(O? value) save;

  _ResolvedPersistence({required this.cached, required this.save});
}

/// For codegen / advanced manual use.
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
