part of blackbox;

/// Pipeline = Graph, который:
/// 1) строится один раз
/// 2) имеет "финальный" box (result)
/// 3) run() возвращает Future результата, завершаясь при первом data/error
final class Pipeline<R> {
  final Graph _graph;
  final _OutputSource<R> _result;

  bool _ran = false;

  Pipeline._(this._graph, this._result);

  Future<R> run() {
    if (_ran) {
      throw StateError('Pipeline.run() can be called only once.');
    }
    _ran = true;

    final c = Completer<R>();

    late final Cancel cancel;
    cancel = _result.listen((out) {
      // Sync -> готов сразу
      if (out is SyncOutput<R>) {
        cancel();
        if (!c.isCompleted) c.complete(out.value);
        return;
      }

      // Async -> ждём data/error
      if (out is AsyncOutput<R>) {
        switch (out) {
          case AsyncLoading<R>():
            return;
          case AsyncData<R>(value: final v):
            cancel();
            if (!c.isCompleted) c.complete(v);
            return;
          case AsyncError<R>(error: final e, stackTrace: final st):
            cancel();
            if (!c.isCompleted) c.completeError(e, st);
            return;
        }
      }
    });

    return c.future;
  }

  static PipelineBuilder<R> builder<R>() => PipelineBuilder<R>();
}

/// Builder максимально похож на Graph.Builder, только добавляется .result(...)
final class PipelineBuilder<R> {
  final GraphBuilder _g = Graph.builder();
  _OutputSource<R>? _result;

  /// Box без input (provider-style node)
  PipelineBuilder<R> add<O>(
    _NoInputBox<O> box, {
    bool Function(Object error)? onError,
  }) {
    _g.add<O>(box, onError: onError);
    return this;
  }

  /// Box c input (подключение зависимостей через buildInput)
  PipelineBuilder<R> addWithDependencies<I, O>(
    _InputBox<I, O> box, {
    required I Function(DependencyResolver d) dependencies,
    bool Function(Object error)? onError,
  }) {
    _g.addWithDependencies<I, O>(
      box,
      dependencies: dependencies,
      onError: onError,
    );
    return this;
  }

  /// Финальный box, чьё output и будет результатом pipeline.
  PipelineBuilder<R> result(_OutputSource<R> box) {
    _result = box;
    return this;
  }

  Pipeline<R> build() {
    final res = _result;
    if (res == null) {
      throw StateError('Pipeline.Builder: call result(box) before build().');
    }
    final graph = _g.build();
    return Pipeline<R>._(graph, res);
  }
}
