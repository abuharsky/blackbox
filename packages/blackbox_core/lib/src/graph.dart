part of blackbox;

class Graph {
  final List<_GraphNode> _nodes = [];
  final Map<_OutputSource<dynamic>, Output<dynamic>> _outputs = {};

  void _schedulePump() {
    _pump();
  }

  void _pump() {
    final d = DependencyResolver._(this);
    for (final node in _nodes) {
      node.tryCompute(d);
    }
  }

  void _onBoxOutput(_OutputSource<dynamic> box, Output<dynamic> out) {
    _outputs[box] = out;
    _schedulePump(); // любое изменение -> пробуем пересчитать зависимых
  }

  Output<T> _getOutput<T>(_OutputSource<T> box) {
    final out = _outputs[box];
    if (out == null) throw StateError('Dependency is not registered: $box');
    return out as Output<T>;
  }

  /// add(box) — ТОЛЬКО NoInputBox
  void add<O>(
    _NoInputBox<O> box, {
    bool Function(Object error)? onError,
  }) {
    box.listen((out) => _onBoxOutput(box, out));
  }

  /// add(box, dependencies: ...) — ТОЛЬКО InputBox
  void addWithDependencies<I, O>(
    _InputBox<I, O> box, {
    required I Function(DependencyResolver d) dependencies,
    bool Function(Object error)? onError,
  }) {
    final node = _GraphNode<I, O>(
      box: box,
      buildInput: dependencies,
      onError: onError,
    );
    _nodes.add(node);

    box.listen((out) => _onBoxOutput(box, out));

    // попытка сразу после add, когда зависимости уже могли быть готовы
    _schedulePump();
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
