part of blackbox;

@immutable
abstract class FlowState {
  const FlowState();
}

final class _FlowBoxStep<S extends FlowState> {
  final OutputSource<dynamic> source;
  final S? Function(dynamic value) map;

  _FlowBoxStep(this.source, this.map);
}

final class FlowBoxBuilder<S extends FlowState> {
  final List<_FlowBoxStep<S>> _steps = [];

  FlowBoxBuilder<S> on<O>(
    OutputSource<O> source,
    S? Function(O value) map,
  ) {
    _steps.add(
      _FlowBoxStep<S>(
        source,
        (value) => map(value as O),
      ),
    );
    return this;
  }

  FlowBox<S> build({required S initial}) {
    return FlowBox<S>._(initial, _steps);
  }
}

/// Aggregates ready values from multiple sources into a sync no-input box.
final class FlowBox<S extends FlowState> extends Box<S> {
  final List<_FlowBoxStep<S>> _steps;
  final List<Cancel> _subscriptions = [];
  final List<void Function()> _queue = [];

  S _state;
  bool _draining = false;
  bool _disposed = false;

  FlowBox._(
    S initial,
    List<_FlowBoxStep<S>> steps,
  )   : _state = initial,
        _steps = List.unmodifiable(steps),
        super(initialValue: initial) {
    _bindSources();
  }

  S get state => _state;

  @override
  S compute(S? previous) => _state;

  /// Releases source subscriptions owned by this flow box.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    for (final cancel in _subscriptions) {
      cancel();
    }
    _subscriptions.clear();
  }

  void _bindSources() {
    for (final step in _steps) {
      _subscriptions.add(
        step.source.listen((out) {
          if (_disposed) return;

          final next = switch (out) {
            SyncOutput<dynamic>(:final value) => step.map(value),
            AsyncData<dynamic>(:final value) => step.map(value),
            _ => null,
          };

          if (next == null || next == _state) return;

          _enqueue(() {
            if (_disposed || next == _state) return;
            _state = next;
            _runtime.recompute();
          });
        }),
      );
    }
  }

  void _enqueue(void Function() job) {
    _queue.add(job);
    if (_draining) return;

    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        _queue.removeAt(0)();
      }
    } finally {
      _draining = false;
    }
  }
}
