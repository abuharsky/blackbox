part of blackbox;

/// EXPERIMENTAL — declarative cache for an async box.
///
/// Cache is the counterpart of a state cell (see docs/MODEL.md): a cell
/// persists what the box *remembers* (the truth, never expires), a cache
/// remembers the output of an *expensive compute* (reproducible, expires
/// after [ttl]). Declare it with one override — no mixins:
///
/// ```dart
/// class MenuBox extends NoInputAsyncBox<Menu> {
///   final Api _api;
///   MenuBox(this._api);
///
///   @override
///   Cache get cache => Cache(ttl: Duration(minutes: 5), persist: 'menu');
///
///   @override
///   Future<Menu> compute(Menu? previous) => _api.fetchMenu();
/// }
/// ```
///
/// Behavior (same contract as the `AsyncManagedCache`/`AsyncPersisted`
/// mixins, which remain as the legacy spelling):
/// - once a value exists, `compute` runs only via [refresh]/expiration —
///   regular recomputes return the cached value;
/// - expired cache refreshes in the background on the next read, showing
///   the stale value meanwhile (`staleWhileRefresh`, on by default);
/// - with `persist:` the value survives restarts: instant cold start from
///   disk, and the disk timestamp drives expiration — a stale restore
///   triggers a background refresh, so "forever-old menu" can't happen;
/// - with `persistFor:` the slot key follows the box input (one slot per
///   restaurant/user/...); an input change re-slots with no cross-slot
///   leaks;
/// - `codec:` overrides the codec registry locally.
final class Cache<I, O> {
  /// How long a fetched value stays fresh.
  final Duration ttl;

  /// Global storage slot key. The cache survives restarts.
  final String? persist;

  /// Storage slot key derived from the box input. One slot per input.
  final String Function(I input)? persistFor;

  /// Show the stale value while refreshing in background (default: the
  /// global [BlackboxPersistence.defaultKeepStaleWhileRefresh], which is
  /// `true`). When `false`, a forced refresh emits `AsyncLoading` first.
  final bool? staleWhileRefresh;

  /// Local codec override; defaults to the registry.
  final PersistentCodec<O>? codec;

  const Cache({
    required this.ttl,
    this.persist,
    this.persistFor,
    this.staleWhileRefresh,
    this.codec,
  }) : assert(
          persist == null || persistFor == null,
          'Provide either persist or persistFor, not both.',
        );
}

/// EXPERIMENTAL — an async box whose compute is a cached fetch.
///
/// The contract lives in the names, so there is nothing to keep in mind:
/// - [fetch] — "go get a fresh value from the source". *When* it runs is
///   not your concern: the [cache] decides (first boot, TTL expiration,
///   [refresh], an input change with an empty slot).
/// - whatever [fetch] returns becomes the cached value — in memory, and
///   in the disk slot when `persist:`/`persistFor:` is set;
/// - reads (`output`, `listen`) check freshness: an expired value
///   triggers a background re-fetch while the stale one stays visible.
///
/// `compute` is sealed — a cached box exposes only [fetch]:
///
/// ```dart
/// class RestaurantMenuBox extends CachedBox<String, Menu> {
///   final Api _api;
///   RestaurantMenuBox(this._api, {required super.input});
///
///   @override
///   Cache<String, Menu> get cache => Cache(
///         ttl: Duration(minutes: 5),
///         persistFor: (id) => 'menu:$id',
///       );
///
///   @override
///   Future<Menu> fetch(String id) => _api.fetchMenu(id);
/// }
/// ```
abstract class CachedBox<I, O> extends AsyncBox<I, O> {
  CachedBox({required I input, O? initialValue})
      : super(input, initialValue: initialValue);

  /// Cache policy: TTL, optional disk slot, stale behavior. Required.
  Cache<I, O> get cache;

  @override
  Cache<I, O> get _cacheConfig => cache;

  /// Fetches a fresh value from the source. Called by the cache — on
  /// first boot, on expiration, on [refresh], and when an input change
  /// lands on an empty slot.
  @protected
  Future<O> fetch(I input);

  @override
  @nonVirtual
  Future<O> compute(I input, O? previous) => fetch(input);
}

/// EXPERIMENTAL — [CachedBox] without input. See [CachedBox].
///
/// ```dart
/// class MenuBox extends NoInputCachedBox<Menu> {
///   final Api _api;
///   MenuBox(this._api);
///
///   @override
///   Cache<void, Menu> get cache =>
///       const Cache(ttl: Duration(minutes: 5), persist: 'menu');
///
///   @override
///   Future<Menu> fetch() => _api.fetchMenu();
/// }
/// ```
abstract class NoInputCachedBox<O> extends NoInputAsyncBox<O> {
  NoInputCachedBox({super.initialValue});

  /// Cache policy: TTL, optional disk slot, stale behavior. Required.
  Cache<void, O> get cache;

  @override
  Cache<void, O> get _cacheConfig => cache;

  /// Fetches a fresh value from the source. Called by the cache — on
  /// first boot, on expiration, and on [refresh].
  @protected
  Future<O> fetch();

  @override
  @nonVirtual
  Future<O> compute(O? previous) => fetch();
}

/// Runtime for the [Cache] declaration. Mirrors the combined semantics
/// of `AsyncPersisted` + `AsyncManagedCache` in one place.
final class _CacheRuntime<I, O> {
  final _AsyncBoxBase<I, O> _box;
  final Cache<I, O> _config;

  _ResolvedPersistence<O>? _slot; // null → in-memory TTL only
  String? _slotKey;
  DateTime? _persistedAt;

  DateTime? _fetchedAt;
  bool _force = false;
  bool _rekeyPending = false;
  Future<void>? _refreshTask;
  I? _lastInput;
  bool _hasLastInput = false;

  _CacheRuntime(this._box, this._config);

  bool get _staleWhileRefresh =>
      _config.staleWhileRefresh ??
      BlackboxPersistence.defaultKeepStaleWhileRefresh;

  String? _keyFor(I input) =>
      _config.persistFor?.call(input) ?? _config.persist;

  bool get _isExpired {
    final at = _fetchedAt;
    if (at == null) return false;
    return BlackboxPersistence.now().difference(at) >= _config.ttl;
  }

  O? resolveInitial(I input, O? initialValue) {
    var value = initialValue;
    final key = _keyFor(input);
    if (key != null) {
      _slotKey = key;
      final slot = BlackboxPersistence._resolve<O>(key, codec: _config.codec);
      _slot = slot;
      _persistedAt = slot.savedAt;
      value = slot.cached ?? initialValue;
      _fetchedAt = _persistedAt;
      if (_fetchedAt == null && slot.hasCachedValue) {
        _fetchedAt = BlackboxPersistence.now();
      }
    }
    if (_fetchedAt == null && value != null) {
      _fetchedAt = BlackboxPersistence.now();
    }
    return value;
  }

  O? resolvePrevious(I input, O? previous) {
    final key = _keyFor(input);
    if (key == null || key == _slotKey) {
      _rekeyPending = false;
      return previous;
    }
    // Slot switch: re-initialize in the new slot; the old slot's value
    // must not leak as `previousData` or be saved under the new key.
    _slotKey = key;
    final slot = BlackboxPersistence._resolve<O>(key, codec: _config.codec);
    _slot = slot;
    _persistedAt = slot.savedAt;
    final cached = slot.cached;
    _box._state = cached != null ? AsyncData(cached) : AsyncLoading<O>();
    _rekeyPending = true;
    _box.onFirstCompute(input, cached);
    return cached;
  }

  void onReady() {
    var skipSave = _slot?.hasCachedValue ?? false;
    var skipStamp = _fetchedAt != null;
    _box._listeners.add((state) {
      if (state is! AsyncData<O>) return;
      if (skipSave) {
        skipSave = false;
      } else {
        _slot?.save(state.value);
        _persistedAt = BlackboxPersistence.now();
      }
      if (skipStamp) {
        skipStamp = false;
      } else {
        _fetchedAt = BlackboxPersistence.now();
      }
    });
  }

  Future<O>? beforeCompute(I input, O? previous) {
    Future<O>? rekeyResult;
    if (_rekeyPending) {
      _rekeyPending = false;
      if (previous != null) rekeyResult = Future.value(previous);
    }

    final inputChanged = _hasLastInput && _lastInput != input;
    _hasLastInput = true;
    _lastInput = input;

    if (_slot != null) {
      _fetchedAt = _persistedAt;
      if (_fetchedAt == null && (_slot?.hasCachedValue ?? false)) {
        _fetchedAt = BlackboxPersistence.now();
      }
    }

    if (inputChanged) {
      _force = false;
      return rekeyResult;
    }
    if (rekeyResult != null) return rekeyResult;

    if (!_force && previous != null && _fetchedAt != null) {
      return Future.value(previous);
    }
    _force = false;
    return null;
  }

  bool shouldEmitLoading(O? previous) {
    if (previous == null) return true;
    if (!_force) return false;
    return !_staleWhileRefresh;
  }

  void onAccess() {
    if (!_isExpired) return;
    _requestRefresh(deferred: _staleWhileRefresh);
  }

  Future<void> refresh() => _requestRefresh(deferred: false);

  Future<void> invalidate() {
    _fetchedAt = null;
    _slot?.save(null);
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
    _force = true;
    return _box.action(() {});
  }
}
