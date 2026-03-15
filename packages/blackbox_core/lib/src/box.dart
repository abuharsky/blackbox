part of blackbox;

/// Universal sync box with input.
abstract class Box<I, O> implements OutputSource<O> {
  _SyncRuntime<I, O>? _runtime;
  void Function(O?)? _persistSave;
  bool _prepareCalled = false;

  /// Standard constructor — runtime created immediately.
  Box(I input, {O? initialValue, String? persistKey}) {
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

  /// Deferred initialization — runtime is null until first input from graph.
  Box.lateinit({String Function(I)? persistKey}) : _runtime = null {
    _persistKeyBuilder = persistKey;
  }

  O? _initialValue;
  String Function(I)? _persistKeyBuilder;

  _SyncRuntime<I, O> get _requireRuntime {
    final r = _runtime;
    if (r == null) {
      throw StateError(
        'Box is not initialized yet. '
        'Use Box.lateinit() only with graph dependencies.',
      );
    }
    return r;
  }

  /// Current input value.
  I get input => _requireRuntime.input;

  /// Current output value (unwrapped from SyncOutput).
  O get value {
    BoxHooks.reportRead(this);
    return _requireRuntime.state.value;
  }

  @override
  SyncOutput<O> get output {
    BoxHooks.reportRead(this);
    return _requireRuntime.state;
  }

  @override
  Cancel listen(void Function(Output<O>) listener) =>
      _requireRuntime.listen((s) => listener(s));

  Cancel listenSync(void Function(SyncOutput<O>) listener) =>
      _requireRuntime.listen(listener);

  void _updateInput(I input) {
    if (_runtime == null) {
      // lateinit: first input — resolve persistence if configured.
      O? effectiveInitial = _initialValue;
      final keyBuilder = _persistKeyBuilder;
      if (keyBuilder != null) {
        final p = BlackboxPersistence._resolve<O>(keyBuilder(input));
        effectiveInitial ??= p.cached;
        _persistSave = p.save;
        _persistKeyBuilder = null;
      }
      _runtime = _SyncRuntime<I, O>(
        input,
        _computeWithPrepare,
        initialValue: effectiveInitial,
      );
      _initialValue = null;
      _attachPersistence();
      return;
    }
    _runtime!.setInput(input);
  }

  O _computeWithPrepare(I input, O? previous) {
    if (!_prepareCalled) {
      _prepareCalled = true;
      prepare(input, previous);
    }
    return compute(input, previous);
  }

  void _attachPersistence() {
    final save = _persistSave;
    if (save == null) return;
    _requireRuntime.listen((state) {
      save(state.value);
    });
  }

  @protected
  Future<void> action(FutureOr<void> Function() body) =>
      _requireRuntime.action(body);

  /// Called once before the first [compute]. Override to restore internal
  /// state from [input] and [previous] (which may come from persistence).
  @protected
  void prepare(I input, O? previous) {}

  /// Called when the box is disposed (e.g. by [Graph.dispose]).
  /// Override to release resources (close sockets, cancel timers, etc.).
  @protected
  void dispose() {}

  @protected
  O compute(I input, O? previous);
}

/// Universal async box with input.
abstract class AsyncBox<I, O> implements OutputSource<O> {
  _AsyncRuntime<I, O>? _runtime;
  void Function(O?)? _persistSave;
  bool _prepareCalled = false;

  /// Standard constructor — runtime created immediately.
  AsyncBox(I input, {O? initialValue, String? persistKey}) {
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

  /// Deferred initialization — runtime is null until first input from graph.
  AsyncBox.lateinit({String Function(I)? persistKey}) : _runtime = null {
    _persistKeyBuilder = persistKey;
  }

  O? _initialValue;
  String Function(I)? _persistKeyBuilder;

  _AsyncRuntime<I, O> get _requireRuntime {
    final r = _runtime;
    if (r == null) {
      throw StateError(
        'AsyncBox is not initialized yet. '
        'Use AsyncBox.lateinit() only with graph dependencies.',
      );
    }
    return r;
  }

  /// Current input value.
  I get input => _requireRuntime.input;

  @override
  AsyncOutput<O> get output {
    BoxHooks.reportRead(this);
    return _requireRuntime.state;
  }

  /// Convenience: returns value if ready, null otherwise.
  O? get valueOrNull {
    final out = output;
    if (out is AsyncData<O>) return out.value;
    return null;
  }

  @override
  Cancel listen(void Function(Output<O>) listener) =>
      _requireRuntime.listen((s) => listener(s));

  Cancel listenAsync(void Function(AsyncOutput<O>) listener) =>
      _requireRuntime.listen(listener);

  void _updateInput(I input) {
    if (_runtime == null) {
      // lateinit: first input — resolve persistence if configured.
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
      return;
    }
    _runtime!.setInput(input);
  }

  Future<O> _computeWithPrepare(I input, O? previous) {
    if (!_prepareCalled) {
      _prepareCalled = true;
      prepare(input, previous);
    }
    return compute(input, previous);
  }

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

  /// Called once before the first [compute]. Override to restore internal
  /// state from [input] and [previous] (which may come from persistence).
  @protected
  void prepare(I input, O? previous) {}

  /// Called when the box is disposed (e.g. by [Graph.dispose]).
  /// Override to release resources (close sockets, cancel timers, etc.).
  @protected
  void dispose() {}

  @protected
  Future<O> compute(I input, O? previous);
}

/// Sync box without input — syntactic sugar for Box<void, O>.
abstract class NoInputBox<O> extends Box<void, O> {
  NoInputBox({O? initialValue, String? persistKey})
      : super(null, initialValue: initialValue, persistKey: persistKey);

  @override
  O compute(void _, O? previous) => computeValue(previous);

  @protected
  O computeValue(O? previous);
}

/// Async box without input — syntactic sugar for AsyncBox<void, O>.
abstract class NoInputAsyncBox<O> extends AsyncBox<void, O> {
  NoInputAsyncBox({O? initialValue, String? persistKey})
      : super(null, initialValue: initialValue, persistKey: persistKey);

  @override
  Future<O> compute(void _, O? previous) => computeValue(previous);

  @protected
  Future<O> computeValue(O? previous);
}

/// Source of output values — used by Graph, Reaction, Provider.
abstract class OutputSource<O> {
  Output<O> get output;
  Cancel listen(void Function(Output<O>) listener);
}
