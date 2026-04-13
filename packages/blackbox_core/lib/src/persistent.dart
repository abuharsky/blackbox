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
      } else if (output is SyncData<O>) {
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

// ---------------------------------------------------------------------------
// Persistence mixins
// ---------------------------------------------------------------------------

/// Persistence for sync boxes (Box, NoInputBox).
///
/// The persistence key is derived from the current input via [persistKeyFor].
/// When the input changes such that the key changes, the persistence slot
/// is transparently switched ([_rekey]) — no box recreation needed.
mixin Persisted<I, O> on _SyncBoxBase<I, O> {
  /// Storage key derived from the current input.
  String persistKeyFor(I input);

  late _ResolvedPersistence<O> _resolved;
  String? _currentPersistKey;

  /// Switch persistence slot if the key changed.
  /// Returns the cached value from the new slot (or null).
  O? _rekey(I input) {
    final key = persistKeyFor(input);
    if (key == _currentPersistKey) return null;
    _currentPersistKey = key;
    _resolved = BlackboxPersistence._resolve<O>(key);
    return _resolved.cached;
  }

  @override
  O? resolveInitialValue(I input, O? initialValue) {
    _currentPersistKey = persistKeyFor(input);
    _resolved = BlackboxPersistence._resolve<O>(_currentPersistKey!);
    return initialValue ?? _resolved.cached;
  }

  @override
  O? beforeCompute(I input, O? previous) => _rekey(input);

  @override
  void onReady() {
    listen((output) {
      _resolved.save((output as SyncData<O>).value);
    }, skipFirst: _resolved.hasCachedValue);
  }
}

/// Persistence for async boxes (AsyncBox, NoInputAsyncBox).
///
/// The persistence key is derived from the current input via [persistKeyFor].
/// When the input changes such that the key changes, the persistence slot
/// is transparently switched ([_rekey]) — no box recreation needed.
mixin AsyncPersisted<I, O> on _AsyncBoxBase<I, O> {
  /// Storage key derived from the current input.
  String persistKeyFor(I input);

  late _ResolvedPersistence<O> _resolved;
  DateTime? _persistedAt;
  String? _currentPersistKey;

  /// When the persisted value was last saved.
  DateTime? get persistedAt => _persistedAt;

  /// Switch persistence slot if the key changed.
  /// Returns the cached value from the new slot (or null).
  O? _rekey(I input) {
    final key = persistKeyFor(input);
    if (key == _currentPersistKey) return null;
    _currentPersistKey = key;
    _resolved = BlackboxPersistence._resolve<O>(key);
    _persistedAt = _resolved.savedAt;
    return _resolved.cached;
  }

  @override
  O? resolveInitialValue(I input, O? initialValue) {
    _currentPersistKey = persistKeyFor(input);
    _resolved = BlackboxPersistence._resolve<O>(_currentPersistKey!);
    _persistedAt = _resolved.savedAt;
    return initialValue ?? _resolved.cached;
  }

  @override
  void onReady() {
    var skip = _resolved.hasCachedValue;
    // Use _listeners directly to avoid ManagedCache.listen
    // triggering cache refresh during init.
    _listeners.add((state) {
      if (skip) {
        skip = false;
        return;
      }
      if (state is AsyncData<O>) {
        _resolved.save(state.value);
        _persistedAt = BlackboxPersistence.now();
      }
    });
  }

  @override
  Future<O>? beforeCompute(I input, O? previous) {
    final cached = _rekey(input);
    if (this case ManagedCache<I, O> m) {
      return m._managedBeforeCompute(input, previous, cached);
    }
    if (cached != null) return Future.value(cached);
    return null;
  }
}

/// Ready-made cache management on top of [AsyncPersisted].
///
/// Provides TTL-based expiration, stale-while-refresh, and manual
/// [refresh] / [invalidateCache] controls. Just override [cacheTtl].
///
/// **Contract:** once a cached value exists, [compute] is only called via
/// [refresh] or when the cache expires. Regular recomputes (e.g. after
/// [action]) return the cached value without calling [compute].
/// Treat [compute] as "fetch fresh value from the source" — not as
/// a function of local mutable state.
mixin ManagedCache<I, O> on AsyncPersisted<I, O> {
  /// Cache time-to-live.
  Duration get cacheTtl;

  /// When true, stale cache is shown while refreshing in background.
  bool get keepStaleWhileRefresh =>
      BlackboxPersistence.defaultKeepStaleWhileRefresh;

  bool _forceRefresh = false;
  Future<void>? _refreshTask;

  bool get _isExpired {
    final savedAt = _persistedAt;
    if (savedAt == null) return false;
    return BlackboxPersistence.now().difference(savedAt) >= cacheTtl;
  }

  @override
  bool shouldEmitLoading(I input, O? previous) {
    if (previous == null) return true;
    if (!_forceRefresh) return false;
    return !keepStaleWhileRefresh;
  }

  Future<O>? _managedBeforeCompute(I input, O? previous, O? rekeyed) {
    if (rekeyed != null) {
      previous = rekeyed;
      if (!_isExpired) return Future.value(rekeyed);
      _forceRefresh = true;
    }
    if (!_forceRefresh && previous != null) {
      return Future.value(previous);
    }
    _forceRefresh = false;
    return null;
  }

  void _maybeRefreshOnAccess() {
    if (!_isExpired) return;
    _requestRefresh(deferred: keepStaleWhileRefresh);
  }

  @override
  AsyncOutput<O> get output {
    _maybeRefreshOnAccess();
    return super.output;
  }

  @override
  Cancel listen(void Function(Output<O>) listener, {bool skipFirst = false}) {
    _maybeRefreshOnAccess();
    return super.listen(listener, skipFirst: skipFirst);
  }

  /// Force recomputation regardless of cache freshness.
  Future<void> refresh() => _requestRefresh(deferred: false);

  /// Clear persisted value from store and refresh.
  Future<void> invalidateCache() {
    _resolved.save(null);
    _persistedAt = null;
    return refresh();
  }

  Future<void> _requestRefresh({required bool deferred}) {
    final existing = _refreshTask;
    if (existing != null) return existing;

    late final Future<void> task;
    task =
        (deferred ? Future<void>.microtask(_performRefresh) : _performRefresh())
            .whenComplete(() {
      if (identical(_refreshTask, task)) {
        _refreshTask = null;
      }
    });
    _refreshTask = task;
    return task;
  }

  Future<void> _performRefresh() {
    _forceRefresh = true;
    return action(() {});
  }
}
