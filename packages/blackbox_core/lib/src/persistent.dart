part of blackbox;

/// A minimal, synchronous key-value store for persistence.
abstract interface class PersistentStore {
  Object? read(String key);
  void write(String key, Object? value);
  void delete(String key);
}

/// Encode/decode box values to/from the [PersistentStore].
abstract class PersistentCodec<T> {
  const PersistentCodec();

  Type get valueType => T;

  Object? encode(T value);
  T decode(Object? stored);
}

final class IdentityCodec<T> extends PersistentCodec<T> {
  const IdentityCodec();
  @override
  Object? encode(T value) => value;

  @override
  T decode(Object? stored) => stored as T;
}

final class BlackboxPersistence {
  static PersistentStore? _store;
  static final Map<Type, PersistentCodec<dynamic>> _codecs = {};
  static Duration? defaultCacheTtl;
  static bool defaultKeepStaleWhileRefresh = true;
  static DateTime Function() now = DateTime.now;

  static bool get isInitialized => _store != null;

  static void init(
    PersistentStore store, {
    Iterable<PersistentCodec<dynamic>> codecs = const [],
  }) {
    final existing = _store;
    if (existing == null) {
      _store = store;
      _registerCodecs(codecs);
      return;
    }
    if (identical(existing, store)) {
      _registerCodecs(codecs);
      return;
    }

    throw StateError(
      'BlackboxPersistence is already initialized with '
      '${existing.runtimeType}. Reset it in tests before registering '
      '${store.runtimeType}.',
    );
  }

  static void registerCodec(PersistentCodec<dynamic> codec) {
    _codecs[codec.valueType] = codec;
  }

  static void _registerCodecs(Iterable<PersistentCodec<dynamic>> codecs) {
    for (final codec in codecs) {
      registerCodec(codec);
    }
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
      'Call BlackboxPersistence.init(store, codecs: [...]) '
      'or BlackboxPersistence.registerCodec(codec).',
    );
  }

  static void reset() {
    _store = null;
    _codecs.clear();
    defaultCacheTtl = null;
    defaultKeepStaleWhileRefresh = true;
    now = DateTime.now;
  }

  /// Resolve persistence for a given key: load cached value + start saving.
  static _ResolvedPersistence<O> _resolve<O>(String key) {
    final store = requireStore();
    final codec = codecFor<O>();
    final raw = store.read(key);
    O? cached;
    DateTime? savedAt;
    var hasCachedValue = false;
    if (raw is Map<Object?, Object?>) {
      final encodedValue = raw['v'];
      final timestamp = raw['ts'];
      if (encodedValue != null) {
        try {
          cached = codec.decode(encodedValue);
          hasCachedValue = true;
        } catch (_) {
          cached = null;
        }
      }
      if (timestamp is int) {
        savedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } else if (raw != null) {
      try {
        cached = codec.decode(raw);
        hasCachedValue = true;
      } catch (_) {
        cached = null;
      }
    }
    return _ResolvedPersistence<O>(
      cached: cached,
      savedAt: savedAt,
      hasCachedValue: hasCachedValue,
      save: (O? value) {
        if (value == null) {
          store.delete(key);
        } else {
          store.write(key, {
            'v': codec.encode(value),
            'ts': now().millisecondsSinceEpoch,
          });
        }
      },
    );
  }
}

final class _ResolvedPersistence<O> {
  final O? cached;
  final DateTime? savedAt;
  final bool hasCachedValue;
  final void Function(O? value) save;

  _ResolvedPersistence({
    required this.cached,
    required this.savedAt,
    required this.hasCachedValue,
    required this.save,
  });
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
    if (raw is Map<Object?, Object?>) {
      final encodedValue = raw['v'];
      if (encodedValue == null) return null;
      try {
        return codec.decode(encodedValue);
      } catch (_) {
        return null;
      }
    }
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
          store.write(key, {
            'v': codec.encode(output.value),
            'ts': BlackboxPersistence.now().millisecondsSinceEpoch,
          });
        }
      } else if (output is SyncOutput<O>) {
        if (output.value == null) {
          store.delete(key);
        } else {
          store.write(key, {
            'v': codec.encode(output.value),
            'ts': BlackboxPersistence.now().millisecondsSinceEpoch,
          });
        }
      }
    });
  }
}
