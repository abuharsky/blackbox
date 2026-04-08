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
    onInputChanged(input);
    _runtime.setInput(input);
  }

  /// Hook: called when input changes via graph. Override to rebind resources.
  @protected
  void onInputChanged(I input) {}

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
    onInputChanged(input);
    _requireRuntime.setInputInternal(
      input,
      shouldEmitLoading: shouldEmitLoadingBeforeCompute(
        input,
        _requireRuntime.previous,
      ),
    );
  }

  /// Hook: called when input changes via graph (after initial init).
  /// Override to rebind resources.
  @protected
  void onInputChanged(I input) {}

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
mixin Persisted<I, O> on _SyncBoxBase<I, O> {
  /// Storage key. Receives the current input value.
  String persistKeyFor(I input);

  late _ResolvedPersistence<O> _resolved;
  String? _resolvedKey;
  bool _skipNextSave = false;

  @override
  O? resolveInitialValue(I input, O? initialValue) {
    final key = persistKeyFor(input);
    _resolved = BlackboxPersistence._resolve<O>(key);
    _resolvedKey = key;
    return initialValue ?? _resolved.cached;
  }

  @override
  void onInitialized() {
    _skipNextSave = _resolved.hasCachedValue;
    _runtime.listen((state) {
      if (_skipNextSave) {
        _skipNextSave = false;
        return;
      }
      _resolved.save(state.value);
    });
  }

  @override
  void onInputChanged(I input) {
    final newKey = persistKeyFor(input);
    if (newKey == _resolvedKey) return;
    final p = BlackboxPersistence._resolve<O>(newKey);
    _resolved = p;
    _resolvedKey = newKey;
    _runtime.setPrevious(p.cached);
    _skipNextSave = p.hasCachedValue;
  }
}

/// Persistence for async boxes (AsyncBox, NoInputAsyncBox).
///
/// Includes optional cache with TTL — override [cacheTtl] to enable.
/// When [cacheTtl] is null (default), the box always recomputes and
/// just persists the result.
mixin AsyncPersisted<I, O> on _AsyncBoxBase<I, O> {
  /// Storage key. Receives the current input value.
  String persistKeyFor(I input);

  /// Override to enable caching with TTL. null = always recompute.
  Duration? get cacheTtl => null;

  /// When true, stale cache is shown while refreshing in background.
  bool get keepStaleWhileRefresh =>
      BlackboxPersistence.defaultKeepStaleWhileRefresh;

  _ResolvedPersistence<O>? _resolved;
  String? _resolvedKey;
  DateTime? _persistedAt;
  bool _skipNextSave = false;
  bool _forceRefresh = false;
  Future<void>? _refreshTask;

  /// When the persisted value was last saved.
  DateTime? get persistedAt => _persistedAt;

  @override
  O? resolveInitialValue(I input, O? initialValue) {
    final key = persistKeyFor(input);
    final p = BlackboxPersistence._resolve<O>(key);
    _resolved = p;
    _resolvedKey = key;
    _persistedAt = p.savedAt;
    return initialValue ?? p.cached;
  }

  @override
  void onInitialized() {
    if (_resolved == null) return;
    _skipNextSave = _resolved!.hasCachedValue;
    _requireRuntime.listen((state) {
      if (_skipNextSave) {
        _skipNextSave = false;
        return;
      }
      final r = _resolved;
      if (r == null) return;
      if (state is AsyncData<O>) {
        r.save(state.value);
        _persistedAt = BlackboxPersistence.now();
      }
    });
  }

  @override
  void onInputChanged(I input) {
    final newKey = persistKeyFor(input);
    if (newKey == _resolvedKey) return;
    final p = BlackboxPersistence._resolve<O>(newKey);
    _resolved = p;
    _resolvedKey = newKey;
    _persistedAt = p.savedAt;
    _requireRuntime.setPrevious(p.cached);
    _skipNextSave = p.hasCachedValue;
  }

  // -- Cache / TTL ----------------------------------------------------------

  bool get _isCached => cacheTtl != null;

  bool get _isExpired {
    final ttl = cacheTtl;
    final savedAt = _persistedAt;
    if (ttl == null || savedAt == null) return false;
    return BlackboxPersistence.now().difference(savedAt) >= ttl;
  }

  @override
  bool shouldEmitLoadingBeforeCompute(I input, O? previous) {
    if (!_isCached) return super.shouldEmitLoadingBeforeCompute(input, previous);
    if (previous == null) return true;
    if (!_forceRefresh) return false;
    return !keepStaleWhileRefresh;
  }

  @override
  Future<O>? beforeCompute(I input, O? previous) {
    if (_isCached && !_forceRefresh && previous != null) {
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
    _resolved?.save(null);
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
