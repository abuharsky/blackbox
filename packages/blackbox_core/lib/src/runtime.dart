part of blackbox;

abstract class _Runtime<I, O, S extends Output<O>> {
  S get state;

  Cancel listen(void Function(S) listener);

  void setInput(I input);

  Future<void> action(FutureOr<void> Function() body);

  /// Принудительный пересчёт на текущем input.
  void recompute();
}

/// ---------------------------
/// Sync runtime
/// ---------------------------
final class _SyncRuntime<I, O> extends _Runtime<I, O, SyncOutput<O>> {
  final O Function(I input, O? previous) _compute;

  I _input;
  O? _previous;
  SyncOutput<O> _state;
  final _listeners = <void Function(SyncOutput<O>)>[];

  _SyncRuntime(this._input, this._compute, {O? initialValue})
      : _previous = initialValue,
        _state = SyncOutput(_compute(_input, initialValue));

  @override
  SyncOutput<O> get state => _state;

  @override
  Cancel listen(void Function(SyncOutput<O>) listener) {
    _listeners.add(listener);
    listener(_state);

    return _cancelGuarded(() => _listeners.remove(listener));
  }

  @override
  void setInput(I input) {
    _input = input;
    _recompute();
  }

  @override
  Future<void> action(FutureOr<void> Function() body) async {
    await body();
    _recompute();
  }

  @override
  void recompute() => _recompute();

  void _recompute() {
    final next = SyncOutput(_compute(_input, _previous));
    _previous = next.value;
    if (next == _state) return; // важно против циклов
    _state = next;
    for (final l in _listeners) l(_state);
  }
}

/// ---------------------------
/// Async runtime
/// ---------------------------
final class _AsyncRuntime<I, O> extends _Runtime<I, O, AsyncOutput<O>> {
  final Future<O> Function(I input, O? previous) _compute;

  I _input;
  O? _previous;
  AsyncOutput<O> _state;
  final _listeners = <void Function(AsyncOutput<O>)>[];
  int _version = 0;

  _AsyncRuntime(this._input, this._compute, {O? initialValue})
      : _previous = initialValue,
        _state =
            initialValue == null ? AsyncLoading() : AsyncData(initialValue);

  @override
  AsyncOutput<O> get state => _state;

  @override
  Cancel listen(void Function(AsyncOutput<O>) listener) {
    _listeners.add(listener);
    listener(_state);

    return _cancelGuarded(() => _listeners.remove(listener));
  }

  @override
  void setInput(I input) {
    _input = input;
    _recompute();
  }

  @override
  Future<void> action(FutureOr<void> Function() body) async {
    await body();
    _recompute();
  }

  @override
  void recompute() => _recompute();

  void _emit(AsyncOutput<O> next) {
    if (next == _state) return;
    _state = next;
    for (final l in _listeners) l(_state);
  }

  void _recompute() {
    final my = ++_version;
//    if (_previous == null) {
    _emit(const AsyncLoading());
    // }
    _compute(_input, _previous).then((value) {
      if (my != _version) return;
      _previous = value;
      _emit(AsyncData(value));
    }).catchError((e, st) {
      if (my != _version) return;
      _emit(AsyncError(e, st));
    });
  }
}
