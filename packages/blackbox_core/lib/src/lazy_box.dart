part of blackbox;

typedef LazyCreate<I, O> = _InputBox<I, O> Function(I input);

/// LazyBox: only lazy initialization of an inner box.
/// - Always exposes AsyncOutput<O>
/// - Initializes inner box on first input
/// - Afterwards delegates all inputs to inner box
/// - Proxies inner output (sync/async) into AsyncOutput<O>
/// - No extra logic: no reset, no recreate-on-change, no action buffering
class LazyBox<I, O> implements _InputBox<I, O> {
  LazyBox({required LazyCreate<I, O> create}) : _create = create;

  final LazyCreate<I, O> _create;

  /// Public by design: allows subclasses / generated wrappers to forward actions.
  /// Null means the inner box hasn't been created yet (or was disposed).
  _InputBox<I, O>? innerBoxOrNull;

  /// True when initialization failed. MVP-friendly: fail-fast and do not retry.
  bool _failed = false;

  Cancel? _innerCancel;

  AsyncOutput<O> _state = const AsyncLoading();
  final List<void Function(AsyncOutput<O>)> _listeners = [];

  @override
  AsyncOutput<O> get output => _state;

  @override
  Cancel listen(void Function(AsyncOutput<O>) listener) {
    _listeners.add(listener);
    listener(_state);
    return _cancelGuarded(() => _listeners.remove(listener));
  }

  /// Returns inner box or throws a clear error.
  /// Use this from actions in subclasses/gencode wrappers when UI guarantees readiness.
  _InputBox<I, O> requireInner() {
    final inner = innerBoxOrNull;
    if (inner != null) return inner;
    if (_failed) {
      throw StateError('LazyBox inner initialization failed.');
    }
    throw StateError('LazyBox inner is not initialized yet.');
  }

  @override
  void _updateInput(I input) {
    if (_failed) return;

    final inner = innerBoxOrNull;
    if (inner == null) {
      _initInner(input);
      return;
    }

    // Delegate all subsequent inputs to inner box.
    inner._updateInput(input);
  }

  void _initInner(I input) {
    try {
      final inner = _create(input);
      innerBoxOrNull = inner;

      // Start proxying inner output → AsyncOutput<O>
      _innerCancel = inner.listen((out) {
        _emit(_toAsync(out));
      });

      // Push first input into the inner box.
      inner._updateInput(input);
    } catch (e, st) {
      _failed = true;
      _emit(AsyncError(e, st));
    }
  }

  AsyncOutput<O> _toAsync(Output<O> out) {
    if (out is AsyncOutput<O>) return out;
    if (out is SyncOutput<O>) return AsyncData(out.value);
    return AsyncError(
      StateError('Unsupported output type: ${out.runtimeType}'),
      StackTrace.current,
    );
  }

  void _emit(AsyncOutput<O> next) {
    if (identical(next, _state) || next == _state) return;
    _state = next;
    for (final l in List.of(_listeners)) {
      l(_state);
    }
  }

  /// Optional: call from owning scope (Connector/Provider) when disposing the graph.
  void reset() {
    _innerCancel?.call();
    _innerCancel = null;

    innerBoxOrNull = null;

    _state = const AsyncLoading();
  }
}
