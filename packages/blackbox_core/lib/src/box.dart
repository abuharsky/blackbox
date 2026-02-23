part of blackbox;

/// -------------------------
/// SYNC with input
/// -------------------------
abstract class BoxWithInput<I, O> implements _InputBox<I, O> {
  late final _SyncRuntime<I, O> _runtime;

  BoxWithInput(I initialInput, {O? initialValue}) {
    _runtime = _SyncRuntime<I, O>(
      initialInput,
      (i, prev) => compute(i, prev),
      initialValue: initialValue,
    );
  }

  @override
  SyncOutput<O> get output => _runtime.state;

  @override
  Cancel listen(void Function(SyncOutput<O>) listener) =>
      _runtime.listen(listener);

  @override
  void _updateInput(I input) => _runtime.setInput(input);

  @protected
  Future<void> action(FutureOr<void> Function() body) => _runtime.action(body);

  @protected
  O compute(I input, O? previous);
}

/// -------------------------
/// ASYNC with input
/// -------------------------
abstract class AsyncBoxWithInput<I, O> implements _InputBox<I, O> {
  late final _AsyncRuntime<I, O> _runtime;

  AsyncBoxWithInput(I initialInput, {O? initialValue}) {
    _runtime = _AsyncRuntime<I, O>(
      initialInput,
      (i, prev) => compute(i, prev),
      initialValue: initialValue,
    );
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
  Future<void> action(FutureOr<void> Function() body) => _runtime.action(body);

  @protected
  Future<O> compute(I input, O? previous);
}

/// -------------------------
/// SYNC no input
/// -------------------------
abstract class Box<O> implements _NoInputBox<O> {
  late final _SyncRuntime<void, O> _runtime;

  Box({O? initialValue}) {
    _runtime = _SyncRuntime<void, O>(
      null,
      (_, prev) => compute(prev),
      initialValue: initialValue,
    );
  }

  @override
  SyncOutput<O> get output => _runtime.state;

  @override
  Cancel listen(void Function(SyncOutput<O>) listener) =>
      _runtime.listen(listener);

  @protected
  Future<void> action(FutureOr<void> Function() body) => _runtime.action(body);

  @protected
  O compute(O? previous);
}

/// -------------------------
/// ASYNC no input
/// -------------------------
abstract class AsyncBox<O> implements _NoInputBox<O> {
  late final _AsyncRuntime<void, O> _runtime;

  AsyncBox({O? initialValue}) {
    _runtime = _AsyncRuntime<void, O>(
      null,
      (_, prev) => compute(prev),
      initialValue: initialValue,
    );
    _runtime.recompute();
  }

  @override
  AsyncOutput<O> get output => _runtime.state;

  @override
  Cancel listen(void Function(AsyncOutput<O>) listener) =>
      _runtime.listen(listener);

  @protected
  Future<void> action(FutureOr<void> Function() body) => _runtime.action(body);

  @protected
  Future<O> compute(O? previous);
}

///////////

/// Общий источник output (для графа/резолвера).
abstract class OutputSource<O> {
  Output<O> get output;
  Cancel listen(void Function(Output<O>) listener);
}

/// Маркер: без входных инпутов (graph.add(box) без dependencies)
abstract class _NoInputBox<O> implements OutputSource<O> {}

/// Маркер: с входными инпутами (graph.add(box, dependencies: ...))
abstract class _InputBox<I, O> implements OutputSource<O> {
  void _updateInput(I input);
}
