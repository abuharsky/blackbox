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
/// When the input changes such that the key changes, the box is
/// **re-initialized in the new slot**: [onFirstCompute] runs again with the
/// new slot's cached value (or `null` when the slot is empty), and the old
/// slot's value never leaks into — or gets saved under — the new key.
///
/// Restore precedence: a disk-cached value wins over `initialValue`;
/// `initialValue` is only the first-boot fallback.
mixin Persisted<I, O> on _SyncBoxBase<I, O> {
  /// Storage key derived from the current input.
  String persistKeyFor(I input);

  late _ResolvedPersistence<O> _resolved;
  String? _currentPersistKey;
  bool _rekeyPending = false;

  @override
  O? resolveInitialValue(I input, O? initialValue) {
    _currentPersistKey = persistKeyFor(input);
    _resolved = BlackboxPersistence._resolve<O>(_currentPersistKey!);
    return _resolved.cached ?? initialValue;
  }

  @override
  O? resolvePreviousForInput(I input, O? previous) {
    final key = persistKeyFor(input);
    if (key == _currentPersistKey) {
      _rekeyPending = false;
      return previous;
    }
    // Persistence slot switch: re-initialize in the new slot. The old
    // slot's value must not survive as `previous` or internal state.
    _currentPersistKey = key;
    _resolved = BlackboxPersistence._resolve<O>(key);
    final cached = _resolved.cached;
    _rekeyPending = true;
    onFirstCompute(input, cached);
    return cached;
  }

  @override
  O? beforeCompute(I input, O? previous) {
    // On rekey `previous` is already the new slot's cached value:
    // short-circuit with it when present, otherwise compute fresh.
    if (_rekeyPending) return previous;
    return null;
  }

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
/// When the input changes such that the key changes, the box is
/// **re-initialized in the new slot**: [onFirstCompute] runs again with the
/// new slot's cached value (or `null` when the slot is empty), the old
/// slot's state is severed (it never appears as `previousData` and is never
/// saved under the new key).
///
/// Restore precedence: a disk-cached value wins over `initialValue`;
/// `initialValue` is only the first-boot fallback.
mixin AsyncPersisted<I, O> on _AsyncBoxBase<I, O> {
  /// Storage key derived from the current input.
  String persistKeyFor(I input);

  late _ResolvedPersistence<O> _resolved;
  DateTime? _persistedAt;
  String? _currentPersistKey;
  bool _rekeyPending = false;

  /// When the persisted value was last saved.
  DateTime? get persistedAt => _persistedAt;

  @override
  O? resolveInitialValue(I input, O? initialValue) {
    _currentPersistKey = persistKeyFor(input);
    _resolved = BlackboxPersistence._resolve<O>(_currentPersistKey!);
    _persistedAt = _resolved.savedAt;
    return _resolved.cached ?? initialValue;
  }

  @override
  O? resolvePreviousForInput(I input, O? previous) {
    final key = persistKeyFor(input);
    if (key == _currentPersistKey) {
      _rekeyPending = false;
      return previous;
    }
    // Persistence slot switch: re-initialize in the new slot.
    _currentPersistKey = key;
    _resolved = BlackboxPersistence._resolve<O>(key);
    _persistedAt = _resolved.savedAt;
    final cached = _resolved.cached;
    // Sever the old slot's state so it can't leak into the new slot
    // as `previousData` or be re-saved under the new key.
    _state = cached != null ? AsyncData(cached) : AsyncLoading<O>();
    _rekeyPending = true;
    onFirstCompute(input, cached);
    return cached;
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
    // Consume-once: `_recompute` can also run from `action()`, which
    // must not replay the rekey short-circuit.
    if (_rekeyPending) {
      _rekeyPending = false;
      // `previous` is the new slot's cached value: show it without a
      // fetch (composed cache mixins may still decide to refresh).
      if (previous != null) return Future.value(previous);
    }
    return null;
  }
}

/// Ready-made TTL cache management for async boxes.
///
/// Provides TTL-based expiration, stale-while-refresh, and manual
/// [refresh] / [invalidateCache] controls. Override [cacheTtl] and
/// treat [compute] as "fetch fresh value from the source".
///
/// Works standalone (in-memory TTL only) or composed with
/// [AsyncPersisted] (cache survives restarts via the store).
///
/// **Contract:** once a cached value exists, [compute] is only called via
/// [refresh] or when the cache expires. Regular recomputes (e.g. after
/// [action]) return the cached value without calling [compute].
mixin AsyncManagedCache<I, O> on _AsyncBoxBase<I, O> {
  /// Cache time-to-live.
  Duration get cacheTtl;

  /// When true, stale cache is shown while refreshing in background.
  bool get keepStaleWhileRefresh =>
      BlackboxPersistence.defaultKeepStaleWhileRefresh;

  DateTime? _fetchedAt;
  bool _forceRefresh = false;
  Future<void>? _refreshTask;
  I? _lastInputForCache;
  bool _hasLastInputForCache = false;

  /// When the cached value was last fetched or loaded.
  DateTime? get lastFetchedAt => _fetchedAt;

  bool get _isExpired {
    final at = _fetchedAt;
    if (at == null) return false;
    return BlackboxPersistence.now().difference(at) >= cacheTtl;
  }

  @override
  O? resolveInitialValue(I input, O? initialValue) {
    final v = super.resolveInitialValue(input, initialValue);
    _syncFetchedAtFromPersisted(fallbackToNowIfCached: true);
    if (_fetchedAt == null && v != null) {
      _fetchedAt = BlackboxPersistence.now();
    }
    return v;
  }

  void _syncFetchedAtFromPersisted({required bool fallbackToNowIfCached}) {
    if (this case AsyncPersisted<I, O> p) {
      _fetchedAt = p._persistedAt;
      if (_fetchedAt == null &&
          fallbackToNowIfCached &&
          p._resolved.hasCachedValue) {
        _fetchedAt = BlackboxPersistence.now();
      }
    }
  }

  @override
  void onReady() {
    super.onReady();
    var skip = _fetchedAt != null;
    _listeners.add((state) {
      if (skip) {
        skip = false;
        return;
      }
      if (state is AsyncData<O>) {
        _fetchedAt = BlackboxPersistence.now();
      }
    });
  }

  @override
  bool shouldEmitLoading(I input, O? previous) {
    if (previous == null) return true;
    if (!_forceRefresh) return false;
    return !keepStaleWhileRefresh;
  }

  @override
  Future<O>? beforeCompute(I input, O? previous) {
    final superResult = super.beforeCompute(input, previous);

    final inputChanged = _hasLastInputForCache && _lastInputForCache != input;
    _hasLastInputForCache = true;
    _lastInputForCache = input;

    _syncFetchedAtFromPersisted(fallbackToNowIfCached: true);

    if (inputChanged) {
      _forceRefresh = false;
      if (superResult != null) return superResult;
      return null;
    }

    if (superResult != null) {
      return superResult;
    }

    if (!_forceRefresh && previous != null && _fetchedAt != null) {
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

  /// Clear cached value (and persisted value if composed) and refresh.
  Future<void> invalidateCache() {
    _fetchedAt = null;
    if (this case AsyncPersisted<I, O> p) {
      p._resolved.save(null);
      p._persistedAt = null;
    }
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

/// Ready-made TTL cache for sync boxes with an async data source.
///
/// The box always exposes a synchronous value (starting with
/// [initialValue]). [fetch] runs in the background and updates the
/// value when it completes. Expired cache triggers a background
/// refresh on the next read.
///
/// Errors in [fetch] are swallowed: the previous value is preserved
/// and the TTL is stamped to avoid tight retry loops. Use [refresh]
/// for manual re-fetch and [invalidateCache] to force an immediate
/// re-fetch.
///
/// **Usage:** extend [Box] and mix in. Provide [cacheTtl] and [fetch];
/// do not override [compute] — the mixin returns the cached value.
/// Composing with [Persisted] persists the cached value across
/// restarts.
mixin ManagedCache<I, O> on Box<I, O> {
  /// Cache time-to-live.
  Duration get cacheTtl;

  /// Fetch a fresh value from the source.
  @protected
  Future<O> fetch(I input);

  late O _cachedValue;
  O? _initialFallback;
  I? _lastInput;
  bool _hasLastInput = false;
  DateTime? _fetchedAt;
  int _fetchVersion = 0;
  Future<void>? _refreshTask;

  /// When the cached value was last fetched (or loaded from store).
  DateTime? get lastFetchedAt => _fetchedAt;

  bool get _isExpired {
    final at = _fetchedAt;
    if (at == null) return false;
    return BlackboxPersistence.now().difference(at) >= cacheTtl;
  }

  @override
  O? resolveInitialValue(I input, O? initialValue) {
    _initialFallback = initialValue;
    // When composed with Persisted, super resolves disk-first:
    // disk-cached value wins over initialValue — initialValue is the
    // first-boot fallback, not a default that should overwrite cached state.
    final effective = super.resolveInitialValue(input, initialValue);
    if (this case Persisted<I, O> p) {
      _fetchedAt = p._resolved.savedAt;
    }
    if (effective == null) {
      throw StateError(
        '$runtimeType with ManagedCache requires an initialValue. '
        'Sync boxes must always have a value — pass initialValue to super().',
      );
    }
    _cachedValue = effective;
    return effective;
  }

  @override
  O compute(I input, O? previous) => _cachedValue;

  @override
  O? beforeCompute(I input, O? previous) {
    final rekeyed = super.beforeCompute(input, previous);

    final rekeyHappened = switch (this) {
      Persisted<I, O> p => p._rekeyPending,
      _ => false,
    };

    if (rekeyHappened) {
      // Persistence slot switched: adopt the new slot's cached value, or
      // fall back to the constructor default for an empty slot. The old
      // slot's value must not be shown or persisted under the new key.
      _cachedValue = rekeyed ?? _initialFallback ?? _cachedValue;
      _fetchedAt = rekeyed != null
          ? (this as Persisted<I, O>)._resolved.savedAt
          : null;
    } else if (rekeyed != null) {
      _cachedValue = rekeyed;
      if (this case Persisted<I, O> p) {
        _fetchedAt = p._resolved.savedAt;
      }
    }

    // A slot switch always counts as an input change, even though the
    // rekey path has already refreshed _lastInput via onFirstCompute:
    // the new slot needs a fetch, and bumping the fetch version also
    // invalidates any in-flight fetch for the previous input.
    final inputChanged =
        rekeyHappened || (_hasLastInput && _lastInput != input);
    _hasLastInput = true;
    _lastInput = input;

    if (inputChanged) {
      if (rekeyed == null && !rekeyHappened) _fetchedAt = null;
      _kickoffFetch(input);
    }
    return rekeyed ?? (rekeyHappened ? _cachedValue : null);
  }

  @override
  void onFirstCompute(I input, O? previous) {
    super.onFirstCompute(input, previous);
    _lastInput = input;
    _hasLastInput = true;
  }

  @override
  void onReady() {
    super.onReady();
    if (_refreshTask != null) return;
    if (_fetchedAt == null || _isExpired) {
      _kickoffFetch(_lastInput as I);
    }
  }

  @override
  SyncData<O> get output {
    _maybeRefreshOnAccess();
    return super.output;
  }

  @override
  Cancel listen(void Function(Output<O>) listener, {bool skipFirst = false}) {
    _maybeRefreshOnAccess();
    return super.listen(listener, skipFirst: skipFirst);
  }

  void _maybeRefreshOnAccess() {
    if (_refreshTask != null) return;
    if (_fetchedAt == null) return;
    if (!_isExpired) return;
    _kickoffFetch(_lastInput as I);
  }

  /// Force re-fetch regardless of cache freshness.
  Future<void> refresh() {
    final existing = _refreshTask;
    if (existing != null) return existing;
    return _kickoffFetch(_lastInput as I);
  }

  /// Clear TTL (and persisted value if composed) and re-fetch.
  Future<void> invalidateCache() {
    _fetchedAt = null;
    if (this case Persisted<I, O> p) {
      p._resolved.save(null);
    }
    return refresh();
  }

  Future<void> _kickoffFetch(I input) {
    final my = ++_fetchVersion;
    late final Future<void> task;
    task = _doFetch(input, my).whenComplete(() {
      if (identical(_refreshTask, task)) _refreshTask = null;
    });
    _refreshTask = task;
    return task;
  }

  Future<void> _doFetch(I input, int my) async {
    try {
      final value = await fetch(input);
      if (my != _fetchVersion) return;
      _fetchedAt = BlackboxPersistence.now();
      _cachedValue = value;
      action(() {});
    } catch (_) {
      if (my != _fetchVersion) return;
      _fetchedAt = BlackboxPersistence.now();
    }
  }
}
