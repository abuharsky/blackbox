part of blackbox;

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

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

/// Shared sync machinery — not user-facing.
abstract class _SyncBoxBase<I, O> implements OutputSource<O> {
  late I _input;
  late SyncOutput<O> _state;
  bool _prepareCalled = false;
  final List<void Function(SyncOutput<O>)> _listeners = [];

  void _init(I input, {O? initialValue}) {
    _input = input;
    final effectiveInitial = resolveInitialValue(input, initialValue);
    final next = _computeWithPrepare(input, effectiveInitial);
    _state = SyncOutput(next);
    attachPersistence();
  }

  /// Current output value (unwrapped from SyncOutput).
  O get value {
    BoxHooks.reportRead(this);
    return _state.value;
  }

  @override
  SyncOutput<O> get output {
    BoxHooks.reportRead(this);
    return _state;
  }

  @override
  Cancel listen(void Function(Output<O>) listener) {
    void typed(SyncOutput<O> state) => listener(state);
    _listeners.add(typed);
    typed(_state);
    return _cancelGuarded(() => _listeners.remove(typed));
  }

  Cancel listenSync(void Function(SyncOutput<O>) listener) {
    _listeners.add(listener);
    listener(_state);
    return _cancelGuarded(() => _listeners.remove(listener));
  }

  void _updateInput(I input) {
    _input = input;
    _emit(_computeWithPrepare(input, _state.value));
  }

  void _emit(O value) {
    _state = SyncOutput(value);
    final snapshot = List<void Function(SyncOutput<O>)>.of(_listeners);
    for (final listener in snapshot) {
      listener(_state);
    }
  }

  O _computeWithPrepare(I input, O? previous) {
    if (!_prepareCalled) {
      _prepareCalled = true;
      prepare(input, previous);
    }
    return _computeInternal(input, previous);
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
          (_) => _emit(_computeWithPrepare(_input, _state.value)));
    }
    _emit(_computeWithPrepare(_input, _state.value));
    return Future.value();
  }

  @protected
  O? resolveInitialValue(I input, O? initialValue) => initialValue;

  @protected
  void attachPersistence() {}

  @protected
  void prepare(I input, O? previous) {}

  O _computeInternal(I input, O? previous);

  @protected
  void dispose() {}
}

/// Sync box with input.
abstract class Box<I, O> extends _SyncBoxBase<I, O> {
  Box(I input, {O? initialValue}) {
    _init(input, initialValue: initialValue);
  }

  @override
  O _computeInternal(I input, O? previous) => compute(input, previous);

  @protected
  O compute(I input, O? previous);
}

/// Sync box without input.
abstract class NoInputBox<O> extends _SyncBoxBase<void, O> {
  NoInputBox({O? initialValue}) {
    _init(null, initialValue: initialValue);
  }

  @override
  O _computeInternal(void _, O? previous) => compute(previous);

  @protected
  O compute(O? previous);
}

// ---------------------------------------------------------------------------
// Async
// ---------------------------------------------------------------------------

/// Shared async machinery — not user-facing.
abstract class _AsyncBoxBase<I, O> implements OutputSource<O> {
  I? _input;
  AsyncOutput<O> _state = AsyncLoading();
  bool _prepareCalled = false;
  bool _initialized = false;
  O? _lateInitialValue;
  int _version = 0;
  final List<void Function(AsyncOutput<O>)> _listeners = [];
  List<void Function(AsyncOutput<O>)>? _pendingListeners;

  bool get _isInitialized => _initialized;

  void _init(I input, {O? initialValue}) {
    _initialized = true;
    _input = input;
    final effectiveInitial = resolveInitialValue(input, initialValue);
    if (effectiveInitial != null) {
      _state = AsyncData(effectiveInitial);
    }
    attachPersistence();
    _recomputeWithLoadingPolicy(input);
  }

  void _initLateinit({O? initialValue}) {
    _lateInitialValue = initialValue;
  }

  void _recomputeWithLoadingPolicy(I input) {
    _recompute(
        shouldEmitLoading: shouldEmitLoadingBeforeCompute(input, _previous));
  }

  O? get _previous => switch (_state) {
        AsyncData<O>(:final value) => value,
        AsyncLoading<O>(:final previousData) => previousData,
        AsyncError<O>(:final previousData) => previousData,
      };

  I get _requireInput {
    if (!_initialized) {
      throw StateError(
        'AsyncBox is not initialized yet. '
        'Use lateinit() only with graph dependencies.',
      );
    }
    return _input as I;
  }

  @override
  AsyncOutput<O> get output {
    BoxHooks.reportRead(this);
    return _state;
  }

  /// Convenience: returns value if ready, null otherwise.
  O? get valueOrNull {
    final s = _state;
    return s is AsyncData<O> ? s.value : null;
  }

  @override
  Cancel listen(void Function(Output<O>) listener) {
    if (!_isInitialized) {
      final pending = _pendingListeners ??= [];
      void typed(AsyncOutput<O> s) => listener(s);
      pending.add(typed);
      listener(AsyncLoading());
      return _cancelGuarded(() => pending.remove(typed));
    }
    void typed(AsyncOutput<O> s) => listener(s);
    _listeners.add(typed);
    typed(_state);
    return _cancelGuarded(() => _listeners.remove(typed));
  }

  Cancel listenAsync(void Function(AsyncOutput<O>) listener) {
    if (!_isInitialized) {
      final pending = _pendingListeners ??= [];
      pending.add(listener);
      listener(AsyncLoading());
      return _cancelGuarded(() => pending.remove(listener));
    }
    _listeners.add(listener);
    listener(_state);
    return _cancelGuarded(() => _listeners.remove(listener));
  }

  void _updateInput(I input) {
    if (!_isInitialized) {
      _initialized = true;
      _input = input;
      final effectiveInitial =
          resolveInitialValue(input, _lateInitialValue);
      _lateInitialValue = null;
      if (effectiveInitial != null) {
        _state = AsyncData(effectiveInitial);
      }
      attachPersistence();
      _recomputeWithLoadingPolicy(input);
      _flushPendingListeners();
      return;
    }
    _input = input;
    _recomputeWithLoadingPolicy(input);
  }

  void _flushPendingListeners() {
    final pending = _pendingListeners;
    if (pending == null || pending.isEmpty) return;
    final snapshot = List<void Function(AsyncOutput<O>)>.of(pending);
    pending.clear();
    _pendingListeners = null;
    for (final listener in snapshot) {
      _listeners.add(listener);
      listener(_state);
    }
  }

  void _recompute({required bool shouldEmitLoading}) {
    final input = _requireInput;
    final previous = _previous;
    final my = ++_version;

    // Check beforeCompute short-circuit
    final early = beforeCompute(input, previous);
    if (early != null) {
      early.then((value) {
        if (my != _version) return;
        _emitData(value);
      });
      return;
    }

    if (shouldEmitLoading) {
      _emitLoading(previous);
    }

    _computeWithPrepare(input, previous).then((value) {
      if (my != _version) return;
      _emitData(value);
    }).catchError((Object e, StackTrace st) {
      if (my != _version) return;
      _emitError(e, st, previous);
    });
  }

  Future<O> _computeWithPrepare(I input, O? previous) {
    if (!_prepareCalled) {
      _prepareCalled = true;
      prepare(input, previous);
    }
    return _computeInternal(input, previous);
  }

  void _emitLoading(O? previousData) {
    _state = AsyncLoading(previousData: previousData);
    _notify();
  }

  void _emitData(O value) {
    _state = AsyncData(value);
    _notify();
  }

  void _emitError(Object error, StackTrace stackTrace, O? previousData) {
    _state = AsyncError(error, stackTrace, previousData: previousData);
    _notify();
  }

  void _notify() {
    final snapshot = List<void Function(AsyncOutput<O>)>.of(_listeners);
    for (final listener in snapshot) {
      listener(_state);
    }
  }

  @protected
  Future<void> action(FutureOr<void> Function() body) {
    final input = _requireInput;
    final FutureOr<void> result;
    try {
      result = body();
    } catch (e, st) {
      return Future.error(e, st);
    }
    if (result is Future) {
      return result.then<void>((_) => _recomputeWithLoadingPolicy(input));
    }
    _recomputeWithLoadingPolicy(input);
    return Future.value();
  }

  @protected
  O? resolveInitialValue(I input, O? initialValue) => initialValue;

  @protected
  void attachPersistence() {}

  /// Return non-null Future to short-circuit compute.
  @protected
  Future<O>? beforeCompute(I input, O? previous) => null;

  @protected
  bool shouldEmitLoadingBeforeCompute(I input, O? previous) => true;

  @protected
  void prepare(I input, O? previous) {}

  Future<O> _computeInternal(I input, O? previous);

  @protected
  void dispose() {}
}

/// Async box with input.
abstract class AsyncBox<I, O> extends _AsyncBoxBase<I, O> {
  AsyncBox(I input, {O? initialValue}) {
    _init(input, initialValue: initialValue);
  }

  AsyncBox.lateinit({O? initialValue}) {
    _initLateinit(initialValue: initialValue);
  }

  @override
  Future<O> _computeInternal(I input, O? previous) => compute(input, previous);

  @protected
  Future<O> compute(I input, O? previous);
}

/// Async box without input.
abstract class NoInputAsyncBox<O> extends _AsyncBoxBase<void, O> {
  NoInputAsyncBox({O? initialValue}) {
    _init(null, initialValue: initialValue);
  }

  @override
  Future<O> _computeInternal(void _, O? previous) => compute(previous);

  @protected
  Future<O> compute(O? previous);
}

