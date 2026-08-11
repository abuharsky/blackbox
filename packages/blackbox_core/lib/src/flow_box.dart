part of blackbox;

@immutable
abstract class FlowState {
  const FlowState();
}

final class _FlowBoxStep<S extends FlowState> {
  final OutputSource<dynamic> source;
  final S? Function(Output<dynamic> output) map;

  _FlowBoxStep(this.source, this.map);
}

final class FlowBoxBuilder<S extends FlowState> {
  final List<_FlowBoxStep<S>> _steps = [];

  FlowBoxBuilder._();

  FlowBoxBuilder<S> _onOutput<O>(
    OutputSource<O> source,
    S? Function(Output<O> output) map,
  ) {
    _steps.add(
      _FlowBoxStep<S>(
        source,
        (output) => map(output as Output<O>),
      ),
    );
    return this;
  }

  FlowBoxBuilder<S> onLoading<O>(
    OutputSource<O> source,
    S? Function() map,
  ) {
    return _onOutput<O>(
      source,
      (output) => switch (output) {
        AsyncLoading<O>() => map(),
        _ => null,
      },
    );
  }

  FlowBoxBuilder<S> onError<O>(
    OutputSource<O> source,
    S? Function(Object error, StackTrace stackTrace) map,
  ) {
    return _onOutput<O>(
      source,
      (output) => switch (output) {
        AsyncError<O>(:final error, :final stackTrace) =>
          map(error, stackTrace),
        _ => null,
      },
    );
  }

  FlowBoxBuilder<S> on<O>(
    OutputSource<O> source,
    S? Function(O value) map,
  ) {
    return _onOutput<O>(
      source,
      (output) => switch (output) {
        SyncData<O>(:final value) => map(value),
        AsyncData<O>(:final value) => map(value),
        _ => null,
      },
    );
  }

  FlowBox<S> build({required S initial}) {
    return FlowBox<S>._(initial, _steps);
  }
}

/// Aggregates ready values from multiple sources into a sync no-input box.
final class FlowBox<S extends FlowState> extends NoInputBox<S> {
  final List<_FlowBoxStep<S>> _steps;
  final List<Cancel> _subscriptions = [];
  final List<void Function()> _queue = [];

  S _flowState;
  bool _draining = false;
  bool _disposed = false;

  static FlowBoxBuilder<S> builder<S extends FlowState>() =>
      FlowBoxBuilder<S>._();

  FlowBox._(
    S initial,
    List<_FlowBoxStep<S>> steps,
  )   : _flowState = initial,
        _steps = List.unmodifiable(steps),
        super(initialValue: initial) {
    _bindSources();
  }

  // NOTE: the former `state` getter was removed — it collides with the
  // inherited cell declarator `state(...)`. Read the current flow state
  // via `value` (identical semantics).

  @override
  S compute() => _flowState;

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

          final next = step.map(out);

          if (next == null || next == _flowState) return;

          _enqueue(() {
            if (_disposed || next == _flowState) return;
            _flowState = next;
            _set(_flowState);
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
