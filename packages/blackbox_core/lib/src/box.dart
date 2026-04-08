part of blackbox;

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

/// Shared sync machinery — not user-facing.
abstract class _SyncBoxBase<I, O> implements OutputSource<O> {
  late final _SyncRuntime<I, O> _runtime;
  void Function(O?)? _persistSave;
  bool _skipInitialPersistReplay = false;
  bool _prepareCalled = false;

  void _init(I input, {O? initialValue, String? persistKey}) {
    O? effectiveInitial = initialValue;
    if (persistKey != null) {
      final p = BlackboxPersistence._resolve<O>(persistKey);
      effectiveInitial ??= p.cached;
      _persistSave = p.save;
      _skipInitialPersistReplay = p.hasCachedValue;
    }
    _runtime = _SyncRuntime<I, O>(
      input,
      _computeWithPrepare,
      initialValue: effectiveInitial,
    );
    _attachPersistence();
  }

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

  void _attachPersistence() {
    final save = _persistSave;
    if (save == null) return;
    var skipReplay = _skipInitialPersistReplay;
    _skipInitialPersistReplay = false;
    _runtime.listen((state) {
      if (skipReplay) {
        skipReplay = false;
        return;
      }
      save(state.value);
    });
  }

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
  Box(I input, {O? initialValue, String? persistKey}) {
    _init(input, initialValue: initialValue, persistKey: persistKey);
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
  NoInputBox({O? initialValue, String? persistKey}) {
    _init(null, initialValue: initialValue, persistKey: persistKey);
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
  void Function(O?)? _persistSave;
  bool _skipInitialPersistReplay = false;
  bool _prepareCalled = false;
  O? _initialValue;
  String? _persistKey;
  DateTime? _persistedAt;
  String Function(I)? _persistKeyBuilder;
  List<void Function(AsyncOutput<O>)>? _pendingListeners;

  void _init(I input, {O? initialValue, String? persistKey}) {
    O? effectiveInitial = initialValue;
    if (persistKey != null) {
      final p = BlackboxPersistence._resolve<O>(persistKey);
      effectiveInitial ??= p.cached;
      _configurePersistence(persistKey, p);
    }
    _runtime = _AsyncRuntime<I, O>(
      input,
      _computeWithPrepare,
      initialValue: effectiveInitial,
    );
    _attachPersistence();
    _recomputeWithLoadingPolicy(input);
  }

  void _initLateinit({String Function(I)? persistKey}) {
    _persistKeyBuilder = persistKey;
  }

  void _configurePersistence(String key, _ResolvedPersistence<O> p) {
    _persistKey = key;
    _persistedAt = p.savedAt;
    _skipInitialPersistReplay = p.hasCachedValue;
    _persistSave = (value) {
      p.save(value);
      _persistedAt = value == null ? null : BlackboxPersistence.now();
    };
  }

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
      final keyBuilder = _persistKeyBuilder;
      if (keyBuilder != null) {
        final persistKey = keyBuilder(input);
        final p = BlackboxPersistence._resolve<O>(persistKey);
        effectiveInitial ??= p.cached;
        _configurePersistence(persistKey, p);
        _persistKeyBuilder = null;
      }
      _runtime = _AsyncRuntime<I, O>(
        input,
        _computeWithPrepare,
        initialValue: effectiveInitial,
      );
      _initialValue = null;
      _attachPersistence();
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

  void _attachPersistence() {
    final save = _persistSave;
    if (save == null) return;
    var skipReplay = _skipInitialPersistReplay;
    _skipInitialPersistReplay = false;
    _requireRuntime.listen((state) {
      if (skipReplay) {
        skipReplay = false;
        return;
      }
      if (state is AsyncData<O>) {
        save(state.value);
      }
    });
  }

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
  String? get persistenceKey => _persistKey;

  @protected
  DateTime? get persistedAt => _persistedAt;

  @protected
  void clearPersistedValue() {
    _persistSave?.call(null);
  }

  @protected
  void prepare(I input, O? previous) {}

  @protected
  void dispose() {}
}

/// Async box with input.
abstract class AsyncBox<I, O> extends _AsyncBoxBase<I, O> {
  /// Standard constructor — runtime created immediately.
  AsyncBox(I input, {O? initialValue, String? persistKey}) {
    _init(input, initialValue: initialValue, persistKey: persistKey);
  }

  /// Deferred initialization — runtime is null until first input from graph.
  AsyncBox.lateinit({String Function(I)? persistKey}) {
    _initLateinit(persistKey: persistKey);
  }

  @override
  Future<O> _computeWithPrepare(I input, O? previous) {
    if (!_prepareCalled) {
      _prepareCalled = true;
      prepare(input, previous);
    }
    return compute(input, previous);
  }

  @protected
  Future<O> compute(I input, O? previous);
}

mixin CachedAsyncSupport<I, O> on AsyncBox<I, O> {
  bool _forceRefresh = false;
  Future<void>? _refreshTask;

  @protected
  Duration? get cacheTtl => BlackboxPersistence.defaultCacheTtl;

  @protected
  bool get keepStaleWhileRefresh =>
      BlackboxPersistence.defaultKeepStaleWhileRefresh;

  @protected
  Future<O> refreshValue(I input, O? cached);

  bool get _isExpired {
    final ttl = cacheTtl;
    final savedAt = persistedAt;
    if (ttl == null || savedAt == null) return false;
    return BlackboxPersistence.now().difference(savedAt) >= ttl;
  }

  @override
  bool shouldEmitLoadingBeforeCompute(I input, O? previous) {
    if (previous == null) return true;
    if (!_forceRefresh) return false;
    return !keepStaleWhileRefresh;
  }

  @override
  Future<O> compute(I input, O? previous) async {
    if (persistenceKey == null) {
      throw StateError(
        'CachedAsyncSupport requires persistKey on the AsyncBox constructor.',
      );
    }

    if (!_forceRefresh && previous != null) {
      return previous;
    }

    _forceRefresh = false;
    return refreshValue(input, previous);
  }

  Future<void> _requestRefresh({required bool deferred}) {
    final existing = _refreshTask;
    if (existing != null) return existing;

    late final Future<void> task;
    task =
        (deferred ? Future<void>.microtask(_performRefresh) : _performRefresh())
            .whenComplete(
      () {
        if (identical(_refreshTask, task)) {
          _refreshTask = null;
        }
      },
    );
    _refreshTask = task;
    return task;
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

  Future<void> refresh() {
    return _requestRefresh(deferred: false);
  }

  Future<void> _performRefresh() {
    _forceRefresh = true;
    return action(() {});
  }

  Future<void> invalidateCache() {
    clearPersistedValue();
    return refresh();
  }
}

/// Async box without input.
abstract class NoInputAsyncBox<O> extends _AsyncBoxBase<void, O> {
  NoInputAsyncBox({O? initialValue, String? persistKey}) {
    _init(null, initialValue: initialValue, persistKey: persistKey);
  }

  @override
  Future<O> _computeWithPrepare(void _, O? previous) {
    if (!_prepareCalled) {
      _prepareCalled = true;
      prepare(null, previous);
    }
    return compute(previous);
  }

  @protected
  Future<O> compute(O? previous);
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
