part of blackbox;

/// Pipeline = Graph + declared result source.
/// run() guarantees:
/// - if there are dependency nodes -> at least one graph pump happened before completing
/// - completes on first ready value (SyncOutput or AsyncData) or AsyncError
final class Pipeline<C, R> {
  final Graph<C> _graph;
  final OutputSource<R> _resultSource;

  bool _ran = false;

  Pipeline._(this._graph, this._resultSource);

  Future<R> run() async {
    if (_ran) {
      throw StateError('Pipeline.run() can be called only once.');
    }
    _ran = true;

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

    tryCompleteFrom(_graph.getOutput<R>(_resultSource));

    late final Cancel cancel;
    cancel = _resultSource.listen((out) {
      if (completer.isCompleted) return;
      tryCompleteFrom(out);
      if (completer.isCompleted) {
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
  final GraphBuilder<C> _graphBuilder;
  OutputSource<R>? _resultSource;

  PipelineBuilder({C? context})
      : _graphBuilder = Graph.builder<C>(context: context);

  PipelineBuilder<C, R> add<O>(
    OutputSource<O> box, {
    Object? Function(DependencyResolver<C> d)? input,
    bool Function(Object error)? onError,
  }) {
    _graphBuilder.add<O>(box, input: input, onError: onError);
    return this;
  }

  PipelineBuilder<C, R> result(OutputSource<R> source) {
    _resultSource = source;
    _graphBuilder._registerSource(source);
    return this;
  }

  Pipeline<C, R> build() {
    final resultSource = _resultSource;
    if (resultSource == null) {
      throw StateError('PipelineBuilder: call result(source) before build().');
    }

    final graph = _graphBuilder.build(start: true);
    return Pipeline<C, R>._(graph, resultSource);
  }
}
