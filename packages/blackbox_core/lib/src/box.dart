part of blackbox;

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

/// Shared sync machinery — not user-facing.
abstract class _SyncBoxBase<I, O> implements OutputSource<O> {
  late final _SyncRuntime<I, O> _runtime;
  bool _prepareCalled = false;

  void _init(I input, {O? initialValue}) {
    final effectiveInitial = resolveInitialValue(input, initialValue);
    _runtime = _SyncRuntime<I, O>(
      input,
      _computeWithPrepare,
      initialValue: effectiveInitial,
    );
    onInitialized();
  }

  /// Hook: resolve initial value before runtime creation.
  /// Override in mixins to inject cached values.
  @protected
  O? resolveInitialValue(I input, O? initialValue) => initialValue;

  /// Hook: called after runtime is created.
  /// Override in mixins to attach listeners.
  @protected
  void onInitialized() {}

  /// Current output value (unwrapped from SyncOutput).
  O get value {
    BoxHooks.reportRead(this);
    return _runtime.state.value;
  }

  @override
  SyncOutput<O> get output {
    BoxHooks.reportRead(this);
    return _runtime.state;
  }

  @override
  Cancel listen(void Function(Output<O>) listener) =>
      _runtime.listen((s) => listener(s));

  Cancel listenSync(void Function(SyncOutput<O>) listener) =>
      _runtime.listen(listener);

  void _updateInput(I input) {
    _runtime.setInput(input);
  }

  O _computeWithPrepare(I input, O? previous);

  @protected
  Future<void> action(FutureOr<void> Function() body) => _runtime.action(body);

  @protected
  void prepare(I input, O? previous) {}

  @protected
  void dispose() {}
}

/// Sync box with input.
abstract class Box<I, O> extends _SyncBoxBase<I, O> {
  /// Standard constructor — runtime created immediately.
  Box(I input, {O? initialValue}) {
    _init(input, initialValue: initialValue);
  }

  @override
  O _computeWithPrepare(I input, O? previous) {
    if (!_prepareCalled) {
      _prepareCalled = true;
      prepare(input, previous);
    }
    return compute(input, previous);
  }

  @protected
  O compute(I input, O? previous);
}

/// Sync box without input.
abstract class NoInputBox<O> extends _SyncBoxBase<void, O> {
  NoInputBox({O? initialValue}) {
    _init(null, initialValue: initialValue);
  }

  @override
  O _computeWithPrepare(void _, O? previous) {
    if (!_prepareCalled) {
      _prepareCalled = true;
      prepare(null, previous);
    }
    return compute(previous);
  }

  @protected
  O compute(O? previous);
}

// ---------------------------------------------------------------------------
// Async
// ---------------------------------------------------------------------------

/// Shared async machinery — not user-facing.
abstract class _AsyncBoxBase<I, O> implements OutputSource<O> {
  _AsyncRuntime<I, O>? _runtime;
  bool _prepareCalled = false;
  O? _initialValue;
  List<void Function(AsyncOutput<O>)>? _pendingListeners;

  void _init(I input, {O? initialValue}) {
    final effectiveInitial = resolveInitialValue(input, initialValue);
    _runtime = _AsyncRuntime<I, O>(
      input,
      _computeWithPrepare,
      initialValue: effectiveInitial,
    );
    onInitialized();
    _recomputeWithLoadingPolicy(input);
  }

  void _initLateinit() {}

  /// Hook: resolve initial value before runtime creation.
  /// Override in mixins to inject cached values.
  @protected
  O? resolveInitialValue(I input, O? initialValue) => initialValue;

  /// Hook: called after runtime is created.
  /// Override in mixins to attach listeners.
  @protected
  void onInitialized() {}

  /// Hook: called before compute. Return non-null to short-circuit compute.
  @protected
  Future<O>? beforeCompute(I input, O? previous) => null;

  void _recomputeWithLoadingPolicy(I input) {
    final runtime = _requireRuntime;
    runtime.recomputeInternal(
      shouldEmitLoading:
          shouldEmitLoadingBeforeCompute(input, runtime.previous),
    );
  }

  _AsyncRuntime<I, O> get _requireRuntime {
    final r = _runtime;
    if (r == null) {
      throw StateError(
        'AsyncBox is not initialized yet. '
        'Use lateinit() only with graph dependencies.',
      );
    }
    return r;
  }

  @override
  AsyncOutput<O> get output {
    BoxHooks.reportRead(this);
    if (_runtime == null) return AsyncLoading();
    return _runtime!.state;
  }

  /// Convenience: returns value if ready, null otherwise.
  O? get valueOrNull {
    final out = output;
    if (out is AsyncData<O>) return out.value;
    return null;
  }

  @override
  Cancel listen(void Function(Output<O>) listener) {
    if (_runtime == null) {
      final pending = _pendingListeners ??= [];
      void typed(AsyncOutput<O> s) => listener(s);
      pending.add(typed);
      listener(AsyncLoading());
      return _cancelGuarded(() => pending.remove(typed));
    }
    return _runtime!.listen((s) => listener(s));
  }

  Cancel listenAsync(void Function(AsyncOutput<O>) listener) {
    if (_runtime == null) {
      final pending = _pendingListeners ??= [];
      pending.add(listener);
      listener(AsyncLoading());
      return _cancelGuarded(() => pending.remove(listener));
    }
    return _runtime!.listen(listener);
  }

  void _updateInput(I input) {
    if (_runtime == null) {
      O? effectiveInitial = _initialValue;
      effectiveInitial = resolveInitialValue(input, effectiveInitial);
      _runtime = _AsyncRuntime<I, O>(
        input,
        _computeWithPrepare,
        initialValue: effectiveInitial,
      );
      _initialValue = null;
      onInitialized();
      _recomputeWithLoadingPolicy(input);
      _flushPendingListeners();
      return;
    }
    _requireRuntime.setInputInternal(
      input,
      shouldEmitLoading: shouldEmitLoadingBeforeCompute(
        input,
        _requireRuntime.previous,
      ),
    );
  }

  void _flushPendingListeners() {
    final pending = _pendingListeners;
    if (pending == null || pending.isEmpty) return;
    final listeners = List.of(pending);
    pending.clear();
    _pendingListeners = null;
    for (final listener in listeners) {
      _runtime!.listen(listener);
    }
  }

  Future<O> _computeWithPrepare(I input, O? previous);

  @protected
  Future<void> action(FutureOr<void> Function() body) {
    final FutureOr<void> result;
    try {
      result = body();
    } catch (e, st) {
      return Future.error(e, st);
    }
    if (result is Future) {
      return result.then<void>(
          (_) => _recomputeWithLoadingPolicy(_requireRuntime.input));
    }
    _recomputeWithLoadingPolicy(_requireRuntime.input);
    return Future.value();
  }

  @protected
  bool shouldEmitLoadingBeforeCompute(I input, O? previous) => true;

  @protected
  void prepare(I input, O? previous) {}

  @protected
  void dispose() {}
}

/// Async box with input.
abstract class AsyncBox<I, O> extends _AsyncBoxBase<I, O> {
  /// Standard constructor — runtime created immediately.
  AsyncBox(I input, {O? initialValue}) {
    _init(input, initialValue: initialValue);
  }

  /// Deferred initialization — runtime is null until first input from graph.
  AsyncBox.lateinit() {
    _initLateinit();
  }

  @override
  Future<O> _computeWithPrepare(I input, O? previous) {
    if (!_prepareCalled) {
      _prepareCalled = true;
      prepare(input, previous);
    }
    final early = beforeCompute(input, previous);
    if (early != null) return early;
    return compute(input, previous);
  }

  @protected
  Future<O> compute(I input, O? previous);
}

/// Async box without input.
abstract class NoInputAsyncBox<O> extends _AsyncBoxBase<void, O> {
  NoInputAsyncBox({O? initialValue}) {
    _init(null, initialValue: initialValue);
  }

  @override
  Future<O> _computeWithPrepare(void _, O? previous) {
    if (!_prepareCalled) {
      _prepareCalled = true;
      prepare(null, previous);
    }
    final early = beforeCompute(_, previous);
    if (early != null) return early;
    return compute(previous);
  }

  @protected
  Future<O> compute(O? previous);
}

// ---------------------------------------------------------------------------
// Persistence mixins
// ---------------------------------------------------------------------------

/// Persistence for sync boxes (Box, NoInputBox).
///
/// The key is resolved once during initialization and never changes.
/// To switch keys, dispose the box and create a new one.
mixin Persisted<I, O> on _SyncBoxBase<I, O> {
  /// Storage key. Called once during init with the initial input.
  String persistKeyFor(I input);

  late final _ResolvedPersistence<O> _resolved;

  @override
  O? resolveInitialValue(I input, O? initialValue) {
    _resolved = BlackboxPersistence._resolve<O>(persistKeyFor(input));
    return initialValue ?? _resolved.cached;
  }

  @override
  void onInitialized() {
    var skip = _resolved.hasCachedValue;
    _runtime.listen((state) {
      if (skip) {
        skip = false;
        return;
      }
      _resolved.save(state.value);
    });
  }
}

/// Persistence for async boxes (AsyncBox, NoInputAsyncBox).
///
/// The key is resolved once during initialization and never changes.
/// To switch keys, dispose the box and create a new one.
mixin AsyncPersisted<I, O> on _AsyncBoxBase<I, O> {
  /// Storage key. Called once during init with the initial input.
  String persistKeyFor(I input);

  late final _ResolvedPersistence<O> _resolved;
  DateTime? _persistedAt;

  /// When the persisted value was last saved.
  DateTime? get persistedAt => _persistedAt;

  @override
  O? resolveInitialValue(I input, O? initialValue) {
    final p = BlackboxPersistence._resolve<O>(persistKeyFor(input));
    _resolved = p;
    _persistedAt = p.savedAt;
    return initialValue ?? p.cached;
  }

  @override
  void onInitialized() {
    var skip = _resolved.hasCachedValue;
    _requireRuntime.listen((state) {
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
  bool shouldEmitLoadingBeforeCompute(I input, O? previous) {
    if (previous == null) return true;
    if (!_forceRefresh) return false;
    return !keepStaleWhileRefresh;
  }

  @override
  Future<O>? beforeCompute(I input, O? previous) {
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
  Cancel listen(void Function(Output<O>) listener) {
    _maybeRefreshOnAccess();
    return super.listen(listener);
  }

  @override
  Cancel listenAsync(void Function(AsyncOutput<O>) listener) {
    _maybeRefreshOnAccess();
    return super.listenAsync(listener);
  }

  /// Force recomputation regardless of cache freshness.
  Future<void> refresh() => _requestRefresh(deferred: false);

  /// Clear persisted value from store and refresh.
  Future<void> invalidateCache() {
    _requireRuntime; // guard: throws if not yet initialized
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

// ---------------------------------------------------------------------------
// Common interface
// ---------------------------------------------------------------------------

/// Source of output values — used by Graph, Reaction, Provider.
abstract class OutputSource<O> {
  Output<O> get output;
  Cancel listen(void Function(Output<O>) listener);
}

extension OutputSourceValueAccess<T> on OutputSource<T> {
  /// Returns the current value for ready sync/async outputs, otherwise null.
  T? get valueOrNull {
    try {
      return requireValue;
    } on StateError {
      return null;
    }
  }

  /// Returns the current value for ready sync/async outputs.
  ///
  /// Throws [StateError] if the output is not ready yet.
  T get requireValue => output.value;
}
