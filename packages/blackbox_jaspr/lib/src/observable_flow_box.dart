part of blackbox_jaspr;

abstract base class _SyncOutputSourceBase<T> implements SyncOutputSource<T> {}

abstract base class _ObservableSyncOutputSource<T> = _SyncOutputSourceBase<T>
    with ObservableOutputSource<T>;

/// Tracks reads from a wrapped [FlowBox] so it can participate in [BoxObserver]
/// rebuilds like generated `@observable` boxes.
///
/// This is a thin proxy around an existing flow. It forwards output/listen/state
/// to the wrapped flow and reports reads from [output].
final class ObservableFlowBox<S extends FlowState>
    extends _ObservableSyncOutputSource<S> {
  ObservableFlowBox(FlowBox<S> inner) : _inner = inner;

  final FlowBox<S> _inner;

  /// The wrapped flow box.
  FlowBox<S> get inner => _inner;

  /// Current derived state of the wrapped flow.
  S get state => _inner.state;

  @override
  SyncOutput<S> get output {
    reportRead();
    return _inner.output;
  }

  @override
  Cancel listen(void Function(SyncOutput<S>) listener) {
    return _inner.listen(listener);
  }

  /// Disposes the wrapped flow box.
  void dispose() => _inner.dispose();
}

extension FlowBoxObservableX<S extends FlowState> on FlowBox<S> {
  /// Wraps this flow so [BoxObserver] can track reads from [output].
  ///
  /// Cache the wrapper if you reuse it often.
  ObservableFlowBox<S> observable() => ObservableFlowBox<S>(this);
}
