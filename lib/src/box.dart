part of blackbox;

/// -------------------------
/// SYNC with input
/// -------------------------
abstract class BoxWithInput<I, O> implements _InputBox<I, O> {
  late final _SyncRuntime<I, O> _runtime;

  BoxWithInput(I initialInput) {
    _runtime = _SyncRuntime<I, O>(initialInput, (i) => compute(i));
    _runtime.recompute();
  }

  @override
  SyncOutput<O> get output => _runtime.state;

  @override
  Cancel listen(void Function(SyncOutput<O>) listener) =>
      _runtime.listen(listener);

  @override
  void _updateInput(I input) => _runtime.setInput(input);

  @protected
  void signal(void Function() body) => _runtime.signal(body);

  @protected
  O compute(I input);
}

/// -------------------------
/// ASYNC with input
/// -------------------------
abstract class AsyncBoxWithInput<I, O> implements _InputBox<I, O> {
  late final _AsyncRuntime<I, O> _runtime;

  AsyncBoxWithInput(I initialInput) {
    _runtime = _AsyncRuntime<I, O>(initialInput, (i) => compute(i));
    _runtime.recompute();
  }

  @override
  AsyncOutput<O> get output => _runtime.state;

  @override
  Cancel listen(void Function(AsyncOutput<O>) listener) =>
      _runtime.listen(listener);

  @override
  void _updateInput(I input) => _runtime.setInput(input);

  @protected
  void signal(void Function() body) => _runtime.signal(body);

  @protected
  Future<O> compute(I input);
}

/// -------------------------
/// SYNC no input
/// -------------------------
abstract class Box<O> implements _NoInputBox<O> {
  late final _SyncRuntime<void, O> _runtime;

  Box() {
    _runtime = _SyncRuntime<void, O>(null, (_) => compute());
    _runtime.recompute();
  }

  @override
  SyncOutput<O> get output => _runtime.state;

  @override
  Cancel listen(void Function(SyncOutput<O>) listener) =>
      _runtime.listen(listener);

  @protected
  void signal(void Function() body) => _runtime.signal(body);

  @protected
  O compute();
}

/// -------------------------
/// ASYNC no input
/// -------------------------
abstract class AsyncBox<O> implements _NoInputBox<O> {
  late final _AsyncRuntime<void, O> _runtime;

  AsyncBox() {
    _runtime = _AsyncRuntime<void, O>(null, (_) => compute());
    _runtime.recompute();
  }

  @override
  AsyncOutput<O> get output => _runtime.state;

  @override
  Cancel listen(void Function(AsyncOutput<O>) listener) =>
      _runtime.listen(listener);

  @protected
  void signal(void Function() body) => _runtime.signal(body);

  @protected
  Future<O> compute();
}

///////////

/// Общий источник output (для графа/резолвера).
abstract class _OutputSource<O> {
  Output<O> get output;
  Cancel listen(void Function(Output<O>) listener);
}

/// Маркер: без входных инпутов (graph.add(box) без dependencies)
abstract class _NoInputBox<O> implements _OutputSource<O> {}

/// Маркер: с входными инпутами (graph.add(box, dependencies: ...))
abstract class _InputBox<I, O> implements _OutputSource<O> {
  void _updateInput(I input);
}
