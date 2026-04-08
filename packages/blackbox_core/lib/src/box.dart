part of blackbox;

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

/// Shared sync machinery — not user-facing.
abstract class _SyncBoxBase<I, O> implements OutputSource<O> {
  late final _SyncRuntime<I, O> _runtime;
  void Function(O?)? _persistSave;
  bool _prepareCalled = false;

  void _init(I input, {O? initialValue, String? persistKey}) {
    O? effectiveInitial = initialValue;
    if (persistKey != null) {
      final p = BlackboxPersistence._resolve<O>(persistKey);
      effectiveInitial ??= p.cached;
      _persistSave = p.save;
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
    _runtime.listen((state) {
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
  bool _prepareCalled = false;
  O? _initialValue;
  String Function(I)? _persistKeyBuilder;
  List<void Function(AsyncOutput<O>)>? _pendingListeners;

  void _init(I input, {O? initialValue, String? persistKey}) {
    O? effectiveInitial = initialValue;
    if (persistKey != null) {
      final p = BlackboxPersistence._resolve<O>(persistKey);
      effectiveInitial ??= p.cached;
      _persistSave = p.save;
    }
    _runtime = _AsyncRuntime<I, O>(
      input,
      _computeWithPrepare,
      initialValue: effectiveInitial,
    );
    _attachPersistence();
    _runtime!.recompute();
  }

  void _initLateinit({String Function(I)? persistKey}) {
    _persistKeyBuilder = persistKey;
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
        final p = BlackboxPersistence._resolve<O>(keyBuilder(input));
        effectiveInitial ??= p.cached;
        _persistSave = p.save;
        _persistKeyBuilder = null;
      }
      _runtime = _AsyncRuntime<I, O>(
        input,
        _computeWithPrepare,
        initialValue: effectiveInitial,
      );
      _initialValue = null;
      _attachPersistence();
      _runtime!.recompute();
      _flushPendingListeners();
      return;
    }
    _runtime!.setInput(input);
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
    _requireRuntime.listen((state) {
      if (state is AsyncData<O>) {
        save(state.value);
      }
    });
  }

  @protected
  Future<void> action(FutureOr<void> Function() body) =>
      _requireRuntime.action(body);

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
