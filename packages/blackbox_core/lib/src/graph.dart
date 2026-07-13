part of blackbox;

/// Runtime reactive graph.
/// - Builder only assembles nodes/sources.
/// - Graph owns subscriptions, pump scheduling and lifecycle.
final class Graph<C> {
  final List<_Node<C, dynamic, dynamic>> _nodes;
  final List<_MultiBoxNode<C, dynamic>> _multiboxes;
  final List<_Effect<C, dynamic>> _effects;
  final Set<OutputSource<dynamic>> _sources;
  final Map<OutputSource<dynamic>, Output<dynamic>> _latestOutputs;
  final List<ProvidableBox> _declared;
  final C? _context;
  final void Function(PumpTrace trace)? _onTrace;

  final List<Cancel> _subscriptions = [];
  final List<Cancel> _owned = [];
  final Set<OutputSource<dynamic>> _deferredSources = {};

  bool _started = false;
  bool _disposed = false;

  bool _pumpScheduled = false;
  bool _pumpingNow = false;

  int _pumpCount = 0;
  int _burst = 0;
  bool _stormBroken = false;
  final Completer<void> _pumpedOnceCompleter = Completer<void>();

  /// Name of the source that triggered the current pump scheduling.
  String? _lastTriggerSource;

  Graph._({
    required List<_Node<C, dynamic, dynamic>> nodes,
    required List<_MultiBoxNode<C, dynamic>> multiboxes,
    required List<_Effect<C, dynamic>> effects,
    required Set<OutputSource<dynamic>> sources,
    required Map<OutputSource<dynamic>, Output<dynamic>> latestOutputs,
    required List<ProvidableBox> declared,
    required C? context,
    void Function(PumpTrace trace)? onTrace,
  })  : _nodes = nodes,
        _multiboxes = multiboxes,
        _effects = effects,
        _sources = sources,
        _latestOutputs = latestOutputs,
        _declared = declared,
        _context = context,
        _onTrace = onTrace;

  /// Boxes declared on the builder via `add` / `addMultiBox`, in
  /// declaration order — the app's provider list in one line:
  ///
  /// ```dart
  /// BoxProvider.multi(boxes: graph.boxes, child: const App());
  /// ```
  ///
  /// Contains exactly what was declared: multiboxes appear as the
  /// composite (read children off it — generic cells would collide by
  /// runtimeType); sources registered lazily via `whenReady` are not
  /// included.
  List<ProvidableBox> get boxes => _declared;

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
      _disposeSource(source);
    }

    for (final mbNode in _multiboxes) {
      mbNode.mb.dispose();
    }

    // Owned resources are released last — every box is already stopped,
    // so nothing can touch a closed client. Reverse declaration order.
    for (final release in _owned.reversed) {
      try {
        release();
      } catch (_) {
        // best-effort teardown
      }
    }
    _owned.clear();
  }

  /// Declares the graph the owner of a resource created for it: the
  /// graph dies — the resource is released. One rule for everything
  /// app-scoped (HTTP clients, databases, files):
  ///
  /// ```dart
  /// return buildApp(context)
  ///   ..own(configClient.close)
  ///   ..own(db.close);
  /// ```
  ///
  /// [release] runs in [dispose], **after** every box has stopped —
  /// nothing can touch a closed client. Callbacks run in reverse
  /// registration order (last owned, first released). Owning a resource
  /// on an already-disposed graph releases it immediately.
  ///
  /// Own only what was created for this graph — a gateway injected by
  /// the runtime belongs to the runtime.
  void own(Cancel release) {
    if (_disposed) {
      release();
      return;
    }
    _owned.add(release);
  }

  /// Barrier: resolves after the first successful pump cycle (after start()).
  Future<void> pumpedOnce() {
    start();
    return _pumpedOnceCompleter.future;
  }

  /// Resolves when synchronous propagation has settled: no pump is
  /// scheduled or running. The test-friendly replacement for
  /// `flushMicrotasks()` loops:
  ///
  /// ```dart
  /// step.set(5);
  /// await graph.settled();
  /// expect(counter.value, 7);
  /// ```
  ///
  /// Does not await async computes in flight — when an `AsyncBox` fetch
  /// completes later, it schedules a new pump; await [settled] again
  /// after the moment you're interested in.
  Future<void> settled() async {
    start();
    while (_pumpScheduled || _pumpingNow) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Renders the dependency graph as a Mermaid `flowchart` — the app map
  /// as a picture. Edges are recorded during pumps, so call after
  /// [settled] (an un-pumped graph has no edges yet):
  ///
  /// ```dart
  /// await graph.settled();
  /// print(graph.toMermaid());
  /// ```
  ///
  /// Paste the output into any Mermaid renderer (GitHub, mermaid.live).
  String toMermaid() {
    final ids = <Object, String>{};
    final labels = <String, int>{};

    String idFor(Object node, String label) {
      return ids.putIfAbsent(node, () {
        final n = (labels[label] = (labels[label] ?? 0) + 1);
        final safe = label.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
        return n == 1 ? safe : '${safe}_$n';
      });
    }

    String boxLabel(Object source) => source.runtimeType.toString();

    final buf = StringBuffer('flowchart TD\n');
    final seenEdges = <String>{};

    void edge(Object from, Object to, String toLabel, {bool dashed = false}) {
      final f = idFor(from, boxLabel(from));
      final t = idFor(to, toLabel);
      final line = '  $f ${dashed ? '-.->' : '-->'} $t';
      if (seenEdges.add(line)) buf.writeln(line);
    }

    for (final node in _nodes) {
      final label = node._boxName;
      idFor(node._source, label);
      for (final dep in node._deps) {
        edge(dep, node._source, label);
      }
    }
    for (final mbNode in _multiboxes) {
      final mb = mbNode.mb;
      final label = mb.runtimeType.toString();
      idFor(mb, label);
      for (final dep in mbNode._deps) {
        edge(dep, mb, label);
      }
      // Ownership edges: multibox → its output cells (dashed).
      for (final cell in mb.children) {
        edge(mb, cell, boxLabel(cell), dashed: true);
      }
    }
    var effectIndex = 0;
    for (final effect in _effects) {
      effectIndex++;
      final label = 'effect_$effectIndex';
      for (final dep in effect._deps) {
        final f = idFor(dep, boxLabel(dep));
        final line = '  $f --> $label{{effect}}';
        if (seenEdges.add(line)) buf.writeln(line);
      }
    }
    // Declared sources that ended up with no edges still belong on the map.
    for (final source in _sources) {
      if (!ids.containsKey(source)) {
        buf.writeln('  ${idFor(source, boxLabel(source))}');
      }
    }
    return buf.toString();
  }

  /// Returns the latest observed output for a source.
  /// Returns the latest observed output for a source.
  /// Throws [_DependencyNotReadyError] if registered but not yet initialized
  /// (e.g. lateinit box before first input).
  /// Throws [StateError] if the source wasn't registered at all.
  Output<T> getOutput<T>(OutputSource<T> source) {
    final out = _latestOutputs[source];
    if (out == null) {
      if (_sources.contains(source)) {
        throw _DependencyNotReadyError(
          'Dependency not ready yet: $source',
        );
      }
      throw StateError('Dependency is not registered: $source');
    }
    return out as Output<T>;
  }

  /// Lazily registers a source the first time it is referenced via
  /// [DependencyResolver]. Used so that fields of a [MultiBox] (or any
  /// other ad-hoc source) can be observed by graph nodes without
  /// having to be added explicitly via [GraphBuilder.add].
  void _ensureRegistered(OutputSource<dynamic> source) {
    if (_disposed) return;
    if (_sources.contains(source)) return;
    _sources.add(source);
    try {
      _latestOutputs[source] = source.output;
      _subscribe(source);
    } catch (_) {
      _deferredSources.add(source);
    }
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
    if (_disposed || _stormBroken) return;
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
        resolver._depSink = node._deps..clear();
        if (tracing) {
          final result = node.tryComputeTraced(resolver);
          events!.add(result);
        } else {
          node.tryCompute(resolver);
        }
      }

      for (final mbNode in _multiboxes) {
        resolver._depSink = mbNode._deps..clear();
        mbNode.tryCompute(resolver);
      }

      for (final effect in _effects) {
        resolver._depSink = effect._deps..clear();
        effect.tryRun(resolver);
      }
      resolver._depSink = null;

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

      // Storm detector: a healthy cascade settles within a bounded number
      // of consecutive pumps (one per dependency level, at most). A pump
      // that keeps rescheduling itself past that bound is a cycle or a
      // box emitting on every recompute. Throwing is not enough — the
      // microtask loop would keep spinning and freeze the isolate — so
      // the graph also stops rescheduling itself for good.
      if (_pumpScheduled) {
        _burst++;
        final limit =
            64 + 4 * (_nodes.length + _multiboxes.length + _effects.length);
        if (_burst > limit) {
          _stormBroken = true;
          throw StateError(
            'Graph did not settle after $limit consecutive pump cycles — '
            'likely a dependency cycle, or a box whose compute emits a '
            'never-equal value every time. The graph has stopped pumping. '
            'Last trigger: ${_lastTriggerSource ?? 'unknown'}. '
            'Build with trace: true to see per-cycle activity.',
          );
        }
      } else {
        _burst = 0;
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
  final List<_MultiBoxNode<C, dynamic>> _multiboxes = [];
  final List<_Effect<C, dynamic>> _effects = [];
  final Set<OutputSource<dynamic>> _sources = {};
  final Map<OutputSource<dynamic>, Output<dynamic>> _latestOutputs = {};
  final List<ProvidableBox> _declared = [];

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
    _declared.add(box);

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

  /// Registers a [MultiBox] composite.
  ///
  /// `MultiBox` has a single graph-driven input and N child boxes whose
  /// inputs are routed entirely from inside the multibox's `compute`.
  /// The graph treats it as an input-consuming, output-less node:
  /// - the graph computes [input] every pump cycle and feeds it to the
  ///   multibox via its private `_updateInput` (mirrors how ordinary
  ///   boxes are driven);
  /// - the multibox's [MultiBox.dispose] is called when the graph is
  ///   disposed.
  ///
  /// Child boxes owned via `child(...)` are disposed together with the
  /// multibox. Any children already materialized at this point (non-late
  /// fields) are registered as graph sources eagerly; `late final`
  /// children appear lazily the moment they are first referenced —
  /// by [dispatch], by UI, or by another node via
  /// [DependencyResolver.whenReady] / [DependencyResolver.whenReadyOrNull].
  ///
  /// [onError] mirrors [add]: return `true` from it to swallow an error
  /// thrown by [input] (the multibox skips that pump cycle).
  ///
  /// [input] may be omitted for a **self-driven** module — a
  /// `MultiBox<void>` (or nullable input) that lives off its own streams
  /// and needs nothing from the graph. The graph then delivers a single
  /// `null` input on the first pump, so `compute` runs exactly once to
  /// start the module:
  ///
  /// ```dart
  /// .addMultiBox(billing)   // no dummy `input: (d) {}` closure
  /// ```
  GraphBuilder<C> addMultiBox<I>(
    MultiBox<I> mb, {
    I Function(DependencyResolver<C> d)? input,
    bool Function(Object error)? onError,
  }) {
    _ensureNotBuilt();
    assert(
      input != null || null is I,
      'addMultiBox(${mb.runtimeType}): MultiBox<$I> requires input:. '
      'Omitting input: is only for self-driven modules whose input type '
      'is void or nullable.',
    );
    _declared.add(mb);
    for (final child in mb.children) {
      _registerSource(child);
    }
    _multiboxes.add(
      _MultiBoxNode<C, I>(
        mb: mb,
        buildInput: input ?? (_) => null as I,
        onError: onError,
      ),
    );
    return this;
  }

  /// Registers an explicit graph effect.
  ///
  /// Effects are fire-and-forget sinks:
  /// - they receive [current] and [previous] distinct inputs
  /// - sync handlers run inline
  /// - async handlers are started but never awaited by the graph
  GraphBuilder<C> addEffect<I>(
    I Function(DependencyResolver<C> d) input, {
    required FutureOr<void> Function(I current, I? previous) run,
  }) {
    _ensureNotBuilt();
    _effects.add(
      _Effect<C, I>(
        buildInput: input,
        run: run,
      ),
    );
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
      multiboxes: List.unmodifiable(_multiboxes),
      effects: List.unmodifiable(_effects),
      // Mutable on purpose: DependencyResolver auto-registers
      // sources referenced for the first time during a pump
      // (e.g. fields of a MultiBox).
      sources: _sources,
      latestOutputs: _latestOutputs,
      declared: List.unmodifiable(_declared),
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

final class _MultiBoxNode<C, I> {
  final MultiBox<I> mb;
  final I Function(DependencyResolver<C> d) buildInput;
  final bool Function(Object error)? onError;

  final Set<OutputSource<dynamic>> _deps = {};

  I? _lastInput;
  bool _pushedAtLeastOnce = false;

  _MultiBoxNode({
    required this.mb,
    required this.buildInput,
    this.onError,
  });

  void tryCompute(DependencyResolver<C> resolver) {
    final I computedInput;

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

    mb._updateInput(computedInput);
  }
}

final class _Effect<C, I> {
  final I Function(DependencyResolver<C> d) buildInput;
  final FutureOr<void> Function(I current, I? previous) run;

  final Set<OutputSource<dynamic>> _deps = {};

  I? _lastInput;
  bool _pushedAtLeastOnce = false;

  _Effect({
    required this.buildInput,
    required this.run,
  });

  void tryRun(DependencyResolver<C> resolver) {
    final I computedInput;

    try {
      computedInput = buildInput(resolver);
    } catch (e, st) {
      if (e is _DependencyNotReadyError) return;
      Error.throwWithStackTrace(e, st);
    }

    if (_pushedAtLeastOnce && _lastInput == computedInput) return;

    final previous = _pushedAtLeastOnce ? _lastInput : null;
    _pushedAtLeastOnce = true;
    _lastInput = computedInput;

    final FutureOr<void> result;
    try {
      result = run(computedInput, previous);
    } catch (e, st) {
      Error.throwWithStackTrace(e, st);
    }

    if (result is Future<void>) {
      unawaited(
        result.catchError((Object error, StackTrace stackTrace) {
          Zone.current.handleUncaughtError(error, stackTrace);
        }),
      );
    }
  }
}

final class DependencyResolver<C> {
  final Graph<C> _graph;

  /// Dependency sink of the node currently being computed — resolver
  /// records every referenced source here (for [Graph.toMermaid]).
  Set<OutputSource<dynamic>>? _depSink;

  DependencyResolver._(this._graph);

  C get context {
    final v = _graph._context;
    if (v == null) throw StateError('Graph context is not set');
    return v;
  }

  C? get contextOrNull => _graph._context;

  /// Returns the value of [source] only when it is ready (SyncData or AsyncData).
  /// If the source is not ready yet, the dependent box skips this pump cycle.
  ///
  /// Lazily registers [source] with the graph on first reference, so
  /// that fields of a [MultiBox] (or other ad-hoc sources) become live
  /// graph dependencies without being explicitly added via [GraphBuilder.add].
  T whenReady<T>(OutputSource<T> source) {
    _depSink?.add(source);
    _graph._ensureRegistered(source);
    final out = _graph.getOutput<T>(source);
    if (!out.isReady) {
      throw _DependencyNotReadyError('Dependency not ready: $source -> $out');
    }
    return out.value;
  }

  /// Returns the value of [source] when ready, or `null` otherwise — without
  /// skipping the pump cycle. Use when the dependent accepts an optional input
  /// and should compute regardless of whether the upstream has produced data.
  ///
  /// Lazily registers [source] with the graph on first reference,
  /// like [whenReady].
  T? whenReadyOrNull<T>(OutputSource<T> source) {
    _depSink?.add(source);
    _graph._ensureRegistered(source);
    try {
      final out = _graph.getOutput<T>(source);
      return out.isReady ? out.value : null;
    } on _DependencyNotReadyError {
      return null;
    }
  }
}

final class _Node<C, I, O> {
  final OutputSource<O> _source;
  final I Function(DependencyResolver<C> d) buildInput;
  final bool Function(Object error)? onError;

  /// Sources this node's [buildInput] touched during the last pump —
  /// recorded via [DependencyResolver] for [Graph.toMermaid].
  final Set<OutputSource<dynamic>> _deps = {};

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
  bool get isReady => this is SyncData<T> || this is AsyncData<T>;

  T get value => switch (this) {
        SyncData<T>(:final value) => value,
        AsyncData<T>(:final value) => value,
        _ => throw StateError('Output value is not ready: ${runtimeType}'),
      };
}

String _formatOutput(Output<dynamic> out) => switch (out) {
      SyncData(:final value) => '$value',
      AsyncLoading() => '[loading...]',
      AsyncData(:final value) => '$value',
      AsyncError(:final error) => '[error: $error]',
    };

final class _DependencyNotReadyError extends StateError {
  _DependencyNotReadyError(super.message);
}

/// Idempotently disposes a box source (sync or async). Non-box sources
/// (custom OutputSource implementations) manage their own lifecycle.
void _disposeSource(OutputSource<dynamic> source) {
  if (source is _SyncBoxBase) {
    source._disposeOnce();
  } else if (source is _AsyncBoxBase) {
    source._disposeOnce();
  }
}
