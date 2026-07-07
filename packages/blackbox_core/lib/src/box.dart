part of blackbox;

/// Source of output values — used by Graph, Reaction, Provider.
abstract class OutputSource<O> {
  Output<O> get output;
  Cancel listen(void Function(Output<O>) listener, {bool skipFirst = false});
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

/// Shared sync machinery — not user-facing.
abstract class _SyncBoxBase<I, O> implements OutputSource<O> {
  late I _input;
  late SyncData<O> _state;
  bool _disposed = false;
  final List<void Function(SyncData<O>)> _listeners = [];

  void _init(I input, {O? initialValue}) {
    _input = input;
    final effectiveInitial = resolveInitialValue(input, initialValue);
    // Read through _input (not the local param): hooks like
    // ValueStateBox.onFirstCompute may promote a restored value to be
    // the effective initial input.
    onFirstCompute(_input, effectiveInitial);
    _state = SyncData(_compute(_input, effectiveInitial));
    onReady();
  }

  /// Current output value (unwrapped from SyncData).
  O get value {
    BoxHooks.reportRead(this);
    return _state.value;
  }

  @override
  SyncData<O> get output {
    BoxHooks.reportRead(this);
    return _state;
  }

  @override
  Cancel listen(void Function(Output<O>) listener, {bool skipFirst = false}) {
    void typed(SyncData<O> state) => listener(state);
    _listeners.add(typed);
    if (!skipFirst) typed(_state);
    return _cancelGuarded(() => _listeners.remove(typed));
  }

  void _updateInput(I input) {
    if (_disposed) return;
    _input = input;
    final previous = resolvePreviousForInput(input, _state.value);
    final early = beforeCompute(input, previous);
    _set(early ?? _compute(input, previous));
  }

  /// Maps the effective `previous` value when a new input arrives.
  /// [Persisted] overrides this to re-initialize the box in a new
  /// persistence slot when the persist key changes.
  @protected
  O? resolvePreviousForInput(I input, O? previous) => previous;

  @protected
  O? beforeCompute(I input, O? previous) => null;

  void _set(O value) {
    // Late events (native callbacks, stream ticks) must not notify
    // listeners of a disposed box.
    if (_disposed) return;
    _state = SyncData(value);
    for (final listener in List.of(_listeners)) {
      listener(_state);
    }
  }

  @protected
  void action(void Function() body) {
    body();
    _set(_compute(_input, _state.value));
  }

  @protected
  O? resolveInitialValue(I input, O? initialValue) => initialValue;

  @protected
  void onReady() {}

  @protected
  void onFirstCompute(I input, O? previous) {}

  O _compute(I input, O? previous);

  @protected
  void dispose() {}

  /// Idempotent dispose entry point used by Graph and MultiBox.
  /// Guarantees [dispose] runs once and no emissions happen afterwards.
  void _disposeOnce() {
    if (_disposed) return;
    _disposed = true;
    dispose();
  }
}

/// Sync box with input.
abstract class Box<I, O> extends _SyncBoxBase<I, O> {
  Box(I input, {O? initialValue}) {
    _init(input, initialValue: initialValue);
  }

  @override
  O _compute(I input, O? previous) => compute(input, previous);

  @protected
  O compute(I input, O? previous);
}

/// Sync box without input.
abstract class NoInputBox<O> extends _SyncBoxBase<void, O> {
  NoInputBox({O? initialValue}) {
    _init(null, initialValue: initialValue);
  }

  @override
  O _compute(void _, O? previous) => compute(previous);

  @protected
  O compute(O? previous);
}

/// Shared async machinery — not user-facing.
abstract class _AsyncBoxBase<I, O> implements OutputSource<O> {
  late I _input;
  AsyncOutput<O> _state = AsyncLoading();
  int _version = 0;
  bool _disposed = false;
  final List<void Function(AsyncOutput<O>)> _listeners = [];

  void _init(I input, {O? initialValue}) {
    _input = input;
    final effectiveInitial = resolveInitialValue(input, initialValue);
    if (effectiveInitial != null) {
      _state = AsyncData(effectiveInitial);
    }
    onFirstCompute(input, _previous);
    onReady();
    _recompute(shouldEmitLoading: shouldEmitLoading(input, _previous));
  }

  O? get _previous => switch (_state) {
        AsyncData<O>(:final value) => value,
        AsyncLoading<O>(:final previousData) => previousData,
        AsyncError<O>(:final previousData) => previousData,
      };

  @override
  AsyncOutput<O> get output {
    BoxHooks.reportRead(this);
    return _state;
  }

  @override
  Cancel listen(void Function(Output<O>) listener, {bool skipFirst = false}) {
    void typed(AsyncOutput<O> s) => listener(s);
    _listeners.add(typed);
    if (!skipFirst) typed(_state);
    return _cancelGuarded(() => _listeners.remove(typed));
  }

  void _updateInput(I input) {
    if (_disposed) return;
    _input = input;
    final previous = resolvePreviousForInput(input, _previous);
    _recompute(shouldEmitLoading: shouldEmitLoading(input, previous));
  }

  /// Maps the effective `previous` value when a new input arrives.
  /// [AsyncPersisted] overrides this to re-initialize the box in a new
  /// persistence slot (severing the old slot's state) when the persist
  /// key changes.
  @protected
  O? resolvePreviousForInput(I input, O? previous) => previous;

  Future<void> _recompute({required bool shouldEmitLoading}) {
    final input = _input;
    final previous = _previous;
    final my = ++_version;

    final early = beforeCompute(input, previous);
    if (early != null) {
      return early.then<void>((value) {
        if (my != _version) return;
        _set(AsyncData(value));
      }).catchError((Object e, StackTrace st) {
        if (my != _version) return;
        _set(AsyncError(e, st, previousData: previous));
      });
    }

    if (shouldEmitLoading) {
      _set(AsyncLoading(previousData: previous));
    }

    return _compute(input, previous).then<void>((value) {
      if (my != _version) return;
      _set(AsyncData(value));
    }).catchError((Object e, StackTrace st) {
      if (my != _version) return;
      _set(AsyncError(e, st, previousData: previous));
    });
  }

  void _set(AsyncOutput<O> state) {
    // Late completions must not notify listeners of a disposed box.
    if (_disposed) return;
    _state = state;
    for (final listener in List.of(_listeners)) {
      listener(_state);
    }
  }

  @protected
  Future<void> action(FutureOr<void> Function() body) {
    try {
      final result = body();
      if (result is Future) {
        return result.then<void>((_) => _recompute(
            shouldEmitLoading:
                shouldEmitLoading(_input, _previous)));
      }
    } catch (e, st) {
      return Future.error(e, st);
    }
    return _recompute(
        shouldEmitLoading: shouldEmitLoading(_input, _previous));
  }

  @protected
  O? resolveInitialValue(I input, O? initialValue) => initialValue;

  @protected
  void onReady() {}

  /// Return non-null Future to short-circuit compute.
  @protected
  Future<O>? beforeCompute(I input, O? previous) => null;

  @protected
  bool shouldEmitLoading(I input, O? previous) => true;

  @protected
  void onFirstCompute(I input, O? previous) {}

  Future<O> _compute(I input, O? previous);

  @protected
  void dispose() {}

  /// Idempotent dispose entry point used by Graph and MultiBox.
  /// Guarantees [dispose] runs once, invalidates in-flight computes,
  /// and no emissions happen afterwards.
  void _disposeOnce() {
    if (_disposed) return;
    _disposed = true;
    _version++;
    dispose();
  }
}

/// Async box with input.
abstract class AsyncBox<I, O> extends _AsyncBoxBase<I, O> {
  AsyncBox(I input, {O? initialValue}) {
    _init(input, initialValue: initialValue);
  }

  AsyncBox._();

  @override
  Future<O> _compute(I input, O? previous) => compute(input, previous);

  @protected
  Future<O> compute(I input, O? previous);
}

/// Async box without input.
abstract class NoInputAsyncBox<O> extends _AsyncBoxBase<void, O> {
  NoInputAsyncBox({O? initialValue}) {
    _init(null, initialValue: initialValue);
  }

  @override
  Future<O> _compute(void _, O? previous) => compute(previous);

  @protected
  Future<O> compute(O? previous);
}
