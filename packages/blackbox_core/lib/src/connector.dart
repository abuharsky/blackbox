part of blackbox;

/// Runtime reactive graph.
/// - Builder only assembles nodes/sources.
/// - Graph owns subscriptions, pump scheduling and lifecycle.
final class Connector<C> {
  final List<_Node<C, dynamic, dynamic>> _nodes;
  final Set<_OutputSource<dynamic>> _sources;
  final Map<_OutputSource<dynamic>, Output<dynamic>> _latestOutputs;
  final C? _context;

  final List<Cancel> _subscriptions = [];

  bool _started = false;
  bool _disposed = false;

  bool _pumpScheduled = false;
  bool _pumpingNow = false;

  int _pumpCount = 0;
  final Completer<void> _pumpedOnceCompleter = Completer<void>();

  Connector._({
    required List<_Node<C, dynamic, dynamic>> nodes,
    required Set<_OutputSource<dynamic>> sources,
    required Map<_OutputSource<dynamic>, Output<dynamic>> latestOutputs,
    required C? context,
  })  : _nodes = nodes,
        _sources = sources,
        _latestOutputs = latestOutputs,
        _context = context;

  static ConnectorBuilder<C> builder<C>({C? context}) =>
      ConnectorBuilder._(context);

  /// Starts subscriptions + schedules initial pump. Idempotent.
  void start() {
    if (_disposed) throw StateError('Graph is disposed');
    if (_started) return;
    _started = true;

    // 1) Snapshot initial outputs (critical: boxes often compute in constructor).
    for (final source in _sources) {
      _latestOutputs[source] = source.output;
    }

    // 2) Subscribe to changes. Any change -> update snapshot -> schedule pump.
    for (final source in _sources) {
      final cancel = source.listen((out) {
        if (_disposed) return;
        _latestOutputs[source] = out;
        _schedulePump();
      });
      _subscriptions.add(cancel);
    }

    // 3) Initial pump to propagate dependencies even if nothing emits.
    _schedulePump();
  }

  /// Cancels all subscriptions. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    for (final cancel in _subscriptions) {
      cancel.call();
    }
    _subscriptions.clear();
  }

  /// Barrier: resolves after the first successful pump cycle (after start()).
  Future<void> pumpedOnce() {
    start();
    return _pumpedOnceCompleter.future;
  }

  /// Returns the latest observed output for a source.
  /// Throws if the source wasn't registered in the graph.
  Output<T> getOutput<T>(_OutputSource<T> source) {
    final out = _latestOutputs[source];
    if (out == null) {
      throw StateError('Dependency is not registered: $source');
    }
    return out as Output<T>;
  }

  bool get hasDependencyNodes => _nodes.isNotEmpty;

  void _schedulePump() {
    if (_disposed) return;
    if (_pumpScheduled) return;
    _pumpScheduled = true;

    scheduleMicrotask(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  void _pump() {
    if (_disposed) return;
    if (_pumpingNow) return;
    _pumpingNow = true;

    try {
      final resolver = DependencyResolver<C>._(this);
      for (final node in _nodes) {
        node.tryCompute(resolver);
      }

      _pumpCount++;
      if (_pumpCount == 1 && !_pumpedOnceCompleter.isCompleted) {
        _pumpedOnceCompleter.complete();
      }
    } finally {
      _pumpingNow = false;
    }
  }
}

/// Builder assembles nodes/sources; execution is owned by Graph.
final class ConnectorBuilder<C> {
  final C? _context;

  final List<_Node<C, dynamic, dynamic>> _nodes = [];
  final Set<_OutputSource<dynamic>> _sources = {};
  final Map<_OutputSource<dynamic>, Output<dynamic>> _latestOutputs = {};

  bool _built = false;

  ConnectorBuilder._(this._context);

  void _registerSource(_OutputSource<dynamic> source) {
    _ensureNotBuilt();
    _sources.add(source);
  }

  ConnectorBuilder<C> connect<O>(
    _NoInputBox<O> box, {
    bool Function(Object error)? onError,
  }) {
    _registerSource(box);
    return this;
  }

  ConnectorBuilder<C> connectTo<I, O>(
    _InputBox<I, O> box, {
    required I Function(DependencyResolver<C> d) to,
    bool Function(Object error)? onError,
  }) {
    _registerSource(box);

    _nodes.add(
      _Node<C, I, O>(
        box: box,
        buildInput: to,
        onError: onError,
      ),
    );

    return this;
  }

  Connector<C> build({bool start = true}) {
    _ensureNotBuilt();
    _built = true;

    final connector = Connector<C>._(
      nodes: List.unmodifiable(_nodes),
      sources: Set.unmodifiable(_sources),
      latestOutputs: _latestOutputs,
      context: _context,
    );

    if (start) connector.start();
    return connector;
  }

  void _ensureNotBuilt() {
    if (_built) throw StateError('GraphBuilder already built');
  }
}

final class DependencyResolver<C> {
  final Connector<C> _graph;
  DependencyResolver._(this._graph);

  C get context {
    final v = _graph._context;
    if (v == null) throw StateError('Graph context is not set');
    return v;
  }

  C? get contextOrNull => _graph._context;

  /// Returns ready dependency value only (SyncOutput or AsyncData).
  /// Throws _DependencyNotReadyError if dependency isn't ready yet.
  T of<T>(_OutputSource<T> source) {
    final out = _graph.getOutput<T>(source);
    if (!out.isReady) {
      throw _DependencyNotReadyError('Dependency not ready: $source -> $out');
    }
    return out.value;
  }
}

final class _Node<C, I, O> {
  final _InputBox<I, O> box;
  final I Function(DependencyResolver<C> d) buildInput;
  final bool Function(Object error)? onError;

  I? _lastInput;
  bool _pushedAtLeastOnce = false;

  _Node({
    required this.box,
    required this.buildInput,
    this.onError,
  });

  void tryCompute(DependencyResolver<C> resolver) {
    I computedInput;

    try {
      computedInput = buildInput(resolver);
    } catch (e, st) {
      // deps not ready -> just wait
      if (e is _DependencyNotReadyError) return;

      // allow node-local error filter/handler
      final handled = onError?.call(e) ?? false;
      if (handled) return;

      Error.throwWithStackTrace(e, st);
    }

    // Always push at least once to "activate" the pipeline,
    // even if the constructor already had the same input.
    if (_pushedAtLeastOnce && _lastInput == computedInput) return;

    _pushedAtLeastOnce = true;
    _lastInput = computedInput;

    box._updateInput(computedInput);
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

final class _DependencyNotReadyError extends StateError {
  _DependencyNotReadyError(super.message);
}
