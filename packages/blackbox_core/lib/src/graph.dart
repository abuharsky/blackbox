part of blackbox;

/// Runtime reactive graph.
/// - Builder only assembles nodes/sources.
/// - Graph owns subscriptions, pump scheduling and lifecycle.
final class Graph<C> {
  final List<_Node<C, dynamic, dynamic>> _nodes;
  final Set<OutputSource<dynamic>> _sources;
  final Map<OutputSource<dynamic>, Output<dynamic>> _latestOutputs;
  final C? _context;
  final void Function(PumpTrace trace)? _onTrace;

  final List<Cancel> _subscriptions = [];
  final Set<OutputSource<dynamic>> _deferredSources = {};

  bool _started = false;
  bool _disposed = false;

  bool _pumpScheduled = false;
  bool _pumpingNow = false;

  int _pumpCount = 0;
  final Completer<void> _pumpedOnceCompleter = Completer<void>();

  /// Name of the source that triggered the current pump scheduling.
  String? _lastTriggerSource;

  Graph._({
    required List<_Node<C, dynamic, dynamic>> nodes,
    required Set<OutputSource<dynamic>> sources,
    required Map<OutputSource<dynamic>, Output<dynamic>> latestOutputs,
    required C? context,
    void Function(PumpTrace trace)? onTrace,
  })  : _nodes = nodes,
        _sources = sources,
        _latestOutputs = latestOutputs,
        _context = context,
        _onTrace = onTrace;

  static GraphBuilder<C> builder<C>({C? context}) => GraphBuilder._(context);

  /// Starts subscriptions + schedules initial pump. Idempotent.
  void start() {
    if (_disposed) throw StateError('Graph is disposed');
    if (_started) return;
    _started = true;

    // 1) Snapshot initial outputs for sources that are already initialized.
    for (final source in _sources) {
      try {
        _latestOutputs[source] = source.output;
      } catch (_) {
        // lateinit boxes may not have output yet — skip.
      }
    }

    // 2) Subscribe to changes. Any change -> update snapshot -> schedule pump.
    //    lateinit boxes have no runtime yet — defer via _deferredSources.
    for (final source in _sources) {
      try {
        _subscribe(source);
      } catch (_) {
        // lateinit box — not ready yet; queued in _deferredSources.
        _deferredSources.add(source);
      }
    }

    // 3) Initial pump to propagate dependencies even if nothing emits.
    _schedulePump();
  }

  /// Cancels all subscriptions and disposes boxes. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    for (final cancel in _subscriptions) {
      cancel.call();
    }
    _subscriptions.clear();

    for (final source in _sources) {
      if (source is _SyncBoxBase) {
        source.dispose();
      } else if (source is _AsyncBoxBase) {
        source.dispose();
      }
    }
  }

  /// Barrier: resolves after the first successful pump cycle (after start()).
  Future<void> pumpedOnce() {
    start();
    return _pumpedOnceCompleter.future;
  }

  /// Returns the latest observed output for a source.
  /// Throws if the source wasn't registered in the graph.
  Output<T> getOutput<T>(OutputSource<T> source) {
    final out = _latestOutputs[source];
    if (out == null) {
      throw StateError('Dependency is not registered: $source');
    }
    return out as Output<T>;
  }

  bool get hasDependencyNodes => _nodes.isNotEmpty;

  void _subscribe(OutputSource<dynamic> source) {
    final cancel = source.listen((out) {
      if (_disposed) return;
      _latestOutputs[source] = out;
      _lastTriggerSource ??= source.runtimeType.toString();
      _schedulePump();
    });
    _subscriptions.add(cancel);
  }

  /// Subscribe to deferred lateinit sources that now have a runtime.
  void _flushDeferred() {
    if (_deferredSources.isEmpty) return;
    final ready = <OutputSource<dynamic>>[];
    for (final source in _deferredSources) {
      try {
        _subscribe(source);
        _latestOutputs[source] = source.output;
        ready.add(source);
      } catch (_) {
        // still not initialized
      }
    }
    _deferredSources.removeAll(ready);
  }

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

    final trigger = _lastTriggerSource;
    _lastTriggerSource = null;

    try {
      final resolver = DependencyResolver<C>._(this);
      final tracing = _onTrace != null;
      List<BoxTrace>? events;
      if (tracing) events = [];

      for (final node in _nodes) {
        if (tracing) {
          final result = node.tryComputeTraced(resolver);
          events!.add(result);
        } else {
          node.tryCompute(resolver);
        }
      }

      _pumpCount++;
      _flushDeferred();

      if (tracing) {
        _onTrace(PumpTrace(
          pumpCycle: _pumpCount,
          triggeredBy: trigger,
          events: events!,
        ));
      }

      if (_pumpCount == 1 && !_pumpedOnceCompleter.isCompleted) {
        _pumpedOnceCompleter.complete();
      }
    } finally {
      _pumpingNow = false;
    }
  }
}

/// Builder assembles nodes/sources; execution is owned by Graph.
final class GraphBuilder<C> {
  final C? _context;

  final List<_Node<C, dynamic, dynamic>> _nodes = [];
  final Set<OutputSource<dynamic>> _sources = {};
  final Map<OutputSource<dynamic>, Output<dynamic>> _latestOutputs = {};

  bool _built = false;

  GraphBuilder._(this._context);

  void _registerSource(OutputSource<dynamic> source) {
    _ensureNotBuilt();
    _sources.add(source);
  }

  /// Unified add — works for boxes with and without dependencies.
  GraphBuilder<C> add<O>(
    OutputSource<O> box, {
    Object? Function(DependencyResolver<C> d)? input,
    bool Function(Object error)? onError,
  }) {
    _registerSource(box);

    if (input != null) {
      _nodes.add(
        _Node<C, Object?, O>(
          box: box,
          buildInput: input,
          onError: onError,
        ),
      );
    }

    return this;
  }

  Graph<C> build({
    bool start = true,
    bool trace = false,
    void Function(PumpTrace)? onTrace,
  }) {
    _ensureNotBuilt();
    _built = true;

    final effectiveTrace = onTrace ?? (trace ? _defaultTracePrinter : null);

    final graph = Graph<C>._(
      nodes: List.unmodifiable(_nodes),
      sources: Set.unmodifiable(_sources),
      latestOutputs: _latestOutputs,
      context: _context,
      onTrace: effectiveTrace,
    );

    if (start) graph.start();
    return graph;
  }

  void _ensureNotBuilt() {
    if (_built) throw StateError('GraphBuilder already built');
  }
}

final class DependencyResolver<C> {
  final Graph<C> _graph;
  DependencyResolver._(this._graph);

  C get context {
    final v = _graph._context;
    if (v == null) throw StateError('Graph context is not set');
    return v;
  }

  C? get contextOrNull => _graph._context;

  /// Returns the value of [source] only when it is ready (SyncOutput or AsyncData).
  /// If the source is not ready yet, the dependent box skips this pump cycle.
  T whenReady<T>(OutputSource<T> source) {
    final out = _graph.getOutput<T>(source);
    if (!out.isReady) {
      throw _DependencyNotReadyError('Dependency not ready: $source -> $out');
    }
    return out.value;
  }
}

final class _Node<C, I, O> {
  final OutputSource<O> _source;
  final I Function(DependencyResolver<C> d) buildInput;
  final bool Function(Object error)? onError;

  I? _lastInput;
  bool _pushedAtLeastOnce = false;

  _Node({
    required OutputSource<O> box,
    required this.buildInput,
    this.onError,
  }) : _source = box;

  String get _boxName => _source.runtimeType.toString();

  void tryCompute(DependencyResolver<C> resolver) {
    I computedInput;

    try {
      computedInput = buildInput(resolver);
    } catch (e, st) {
      if (e is _DependencyNotReadyError) return;

      final handled = onError?.call(e) ?? false;
      if (handled) return;

      Error.throwWithStackTrace(e, st);
    }

    if (_pushedAtLeastOnce && _lastInput == computedInput) return;

    _pushedAtLeastOnce = true;
    _lastInput = computedInput;

    _dispatchInput(computedInput);
  }

  BoxTrace tryComputeTraced(DependencyResolver<C> resolver) {
    I computedInput;

    try {
      computedInput = buildInput(resolver);
    } catch (e, st) {
      if (e is _DependencyNotReadyError) {
        return BoxTrace(name: _boxName, result: BoxTraceResult.waiting);
      }

      final handled = onError?.call(e) ?? false;
      if (handled) {
        return BoxTrace(name: _boxName, result: BoxTraceResult.skipped);
      }

      Error.throwWithStackTrace(e, st);
    }

    if (_pushedAtLeastOnce && _lastInput == computedInput) {
      return BoxTrace(name: _boxName, result: BoxTraceResult.skipped);
    }

    _pushedAtLeastOnce = true;
    _lastInput = computedInput;
    _dispatchInput(computedInput);

    // Read the new output for display.
    String? displayValue;
    try {
      final out = _source.output;
      displayValue = _formatOutput(out);
    } catch (_) {}

    return BoxTrace(
      name: _boxName,
      result: BoxTraceResult.computed,
      value: displayValue,
    );
  }

  void _dispatchInput(I input) {
    final source = _source;
    if (source is _SyncBoxBase<I, O>) {
      source._updateInput(input);
    } else if (source is _AsyncBoxBase<I, O>) {
      source._updateInput(input);
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

String _formatOutput(Output<dynamic> out) => switch (out) {
      SyncOutput(:final value) => '$value',
      AsyncLoading() => '[loading...]',
      AsyncData(:final value) => '$value',
      AsyncError(:final error) => '[error: $error]',
    };

final class _DependencyNotReadyError extends StateError {
  _DependencyNotReadyError(super.message);
}
