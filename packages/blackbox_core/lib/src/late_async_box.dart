part of blackbox;

/// Async box with deferred initialization via graph.
abstract class LateAsyncBox<I, O> extends AsyncBox<I, O> {
  bool _lateInitialized = false;
  O? _lateInitialValue;
  List<void Function(AsyncOutput<O>)>? _pendingListeners;

  LateAsyncBox({O? initialValue}) : super._() {
    _lateInitialValue = initialValue;
    if (initialValue != null) {
      _state = AsyncData(initialValue);
    }
  }

  @override
  Cancel listen(void Function(Output<O>) listener, {bool skipFirst = false}) {
    if (!_lateInitialized) {
      void typed(AsyncOutput<O> s) => listener(s);
      final pending = _pendingListeners ??= [];
      pending.add(typed);
      if (!skipFirst) listener(_state);
      return _cancelGuarded(() => pending.remove(typed));
    }
    return super.listen(listener, skipFirst: skipFirst);
  }

  @override
  void _updateInput(I input) {
    if (!_lateInitialized) {
      _lateInitialized = true;
      _input = input;
      final effectiveInitial =
          resolveInitialValue(input, _lateInitialValue);
      _lateInitialValue = null;
      if (effectiveInitial != null) {
        _state = AsyncData(effectiveInitial);
      }
      onFirstCompute(input, _previous);
      onReady();
      _recompute(
          shouldEmitLoading:
              shouldEmitLoading(input, _previous));
      _flushPendingListeners();
      return;
    }
    super._updateInput(input);
  }

  @override
  Future<void> action(FutureOr<void> Function() body) {
    if (!_lateInitialized) {
      throw StateError(
        'AsyncBox is not initialized yet. '
        'Use LateAsyncBox only with graph dependencies.',
      );
    }
    return super.action(body);
  }

  void _flushPendingListeners() {
    final pending = _pendingListeners;
    if (pending == null || pending.isEmpty) return;
    _pendingListeners = null;
    for (final listener in List.of(pending)) {
      _listeners.add(listener);
      listener(_state);
    }
  }
}
