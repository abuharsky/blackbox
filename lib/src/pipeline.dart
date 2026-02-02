part of blackbox;

/// Pipeline = Graph + declared result source.
/// run() guarantees:
/// - if there are dependency nodes -> at least one graph pump happened before completing
/// - completes on first ready value (SyncOutput or AsyncData) or AsyncError
final class Pipeline<C, R> {
  final Connector<C> _graph;
  final _OutputSource<R> _resultSource;

  bool _ran = false;

  Pipeline._(this._graph, this._resultSource);

  Future<R> run() async {
    if (_ran) {
      throw StateError('Pipeline.run() can be called only once.');
    }
    _ran = true;

    // Enforce "executed once" contract for non-trivial pipelines.
    if (_graph.hasDependencyNodes) {
      await _graph.pumpedOnce();
    } else {
      _graph.start();
    }

    final completer = Completer<R>();

    void tryCompleteFrom(Output<R> out) {
      if (completer.isCompleted) return;

      if (out is SyncOutput<R>) {
        completer.complete(out.value);
        return;
      }

      if (out is AsyncOutput<R>) {
        switch (out) {
          case AsyncLoading<R>():
            return;
          case AsyncData<R>(value: final v):
            completer.complete(v);
            return;
          case AsyncError<R>(error: final e, stackTrace: final st):
            completer.completeError(e, st);
            return;
        }
      }
    }

    // 1) Snapshot current output immediately (works even if result never emits).
    tryCompleteFrom(_graph.getOutput<R>(_resultSource));

    // 2) Then subscribe for future updates.
    late final Cancel cancel;
    cancel = _resultSource.listen((out) {
      if (completer.isCompleted) return;
      tryCompleteFrom(out);
      if (completer.isCompleted) {
        // Cancel on next microtask to avoid cancelling during dispatch.
        scheduleMicrotask(() => cancel.call());
      }
    });

    return completer.future;
  }

  void dispose() => _graph.dispose();

  static PipelineBuilder<C, R> builder<C, R>({C? context}) =>
      PipelineBuilder<C, R>(context: context);
}

final class PipelineBuilder<C, R> {
  final ConnectorBuilder<C> _connectorBuilder;
  _OutputSource<R>? _resultSource;

  PipelineBuilder({C? context})
      : _connectorBuilder = Connector.builder<C>(context: context);

  PipelineBuilder<C, R> add<O>(
    _NoInputBox<O> box, {
    bool Function(Object error)? onError,
  }) {
    _connectorBuilder.connect<O>(box, onError: onError);
    return this;
  }

  PipelineBuilder<C, R> addWithDependencies<I, O>(
    _InputBox<I, O> box, {
    required I Function(DependencyResolver<C> d) dependencies,
    bool Function(Object error)? onError,
  }) {
    _connectorBuilder.connectTo<I, O>(
      box,
      to: dependencies,
      onError: onError,
    );
    return this;
  }

  PipelineBuilder<C, R> result(_OutputSource<R> source) {
    _resultSource = source;

    // Ensure result source is registered in Graph for snapshot/listen.
    _connectorBuilder._registerSource(source);

    return this;
  }

  Pipeline<C, R> build() {
    final resultSource = _resultSource;
    if (resultSource == null) {
      throw StateError('PipelineBuilder: call result(source) before build().');
    }

    final graph = _connectorBuilder.build(start: true);
    return Pipeline<C, R>._(graph, resultSource);
  }
}
