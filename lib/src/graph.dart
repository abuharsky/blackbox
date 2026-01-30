part of blackbox;

/// Public immutable graph after build().
final class Graph {
  final List<_GraphNode> _nodes;
  final Map<_OutputSource<dynamic>, Output<dynamic>> _outputs;

  Graph._(this._nodes, this._outputs);

  /// Entry point: Graph.builder().add(...).addWithDependencies(...).build()
  static GraphBuilder builder() => GraphBuilder._();

  // ==== Internal runtime ====

  void _start() {
    _schedulePump();
  }

  void _schedulePump() {
    _pump();
  }

  void _pump() {
    final d = DependencyResolver._(this);
    for (final node in _nodes) {
      node.tryCompute(d);
    }
  }

  Output<T> _getOutput<T>(_OutputSource<T> box) {
    final out = _outputs[box];
    if (out == null) throw StateError('Dependency is not registered: $box');
    return out as Output<T>;
  }
}

/// Builder is the only way to assemble a graph.
final class GraphBuilder {
  final List<_GraphNode> _nodes = [];
  final Map<_OutputSource<dynamic>, Output<dynamic>> _outputs = {};
  bool _built = false;

  GraphBuilder._();

  GraphBuilder add<O>(
    _NoInputBox<O> box, {
    bool Function(Object error)? onError,
  }) {
    _ensureNotBuilt();

    // immediately track box output changes
    box.listen((out) {
      _outputs[box] = out;
      _pump();
    });

    return this;
  }

  GraphBuilder addWithDependencies<I, O>(
    _InputBox<I, O> box, {
    required I Function(DependencyResolver d) dependencies,
    bool Function(Object error)? onError,
  }) {
    _ensureNotBuilt();

    final node = _GraphNode<I, O>(
      box: box,
      buildInput: dependencies,
      onError: onError,
    );
    _nodes.add(node);

    box.listen((out) {
      _outputs[box] = out;
      _pump();
    });

    // try compute right away if deps already ready
    _pump();

    return this;
  }

  Graph build() {
    _ensureNotBuilt();
    _built = true;

    final g = Graph._(_nodes, _outputs);
    g._start();
    return g;
  }

  void _ensureNotBuilt() {
    if (_built) throw StateError('Builder already built');
  }

  void _pump() {
    // builder временно “прикидывается” графом:
    // DependencyResolver ожидает доступ к _getOutput, поэтому создаём ephemeral Graph.
    final g = Graph._(_nodes, _outputs);
    final d = DependencyResolver._(g);

    for (final node in _nodes) {
      node.tryCompute(d);
    }
  }
}

final class DependencyResolver {
  final Graph _g;
  DependencyResolver._(this._g);

  /// Только готовые значения. Если не готово — кидаем ошибку.
  T of<T>(_OutputSource<T> box) {
    final out = _g._getOutput<T>(box);
    if (!out.isReady) {
      throw StateError('Dependency not ready: $box -> $out');
    }
    return out.value;
  }
}

final class _GraphNode<I, O> {
  final _InputBox<I, O> box;
  final I Function(DependencyResolver d) buildInput;
  final bool Function(Object error)? onError;

  I? _lastInput;

  _GraphNode({
    required this.box,
    required this.buildInput,
    this.onError,
  });

  void tryCompute(DependencyResolver d) {
    try {
      final input = buildInput(d);
      if (_lastInput != null && _lastInput == input)
        return; // ключ против циклов
      _lastInput = input;
      box._updateInput(input);
    } catch (e) {
      final handled = onError?.call(e) ?? false;
      if (!handled) rethrow;
    }
  }
}

extension _OutputReady<T> on Output<T> {
  bool get isReady => this is SyncOutput<T> || this is AsyncData<T>;

  T get value => switch (this) {
        SyncOutput<T>(:final value) => value,
        AsyncData<T>(:final value) => value,
        _ => throw StateError('Not ready'),
      };
}
