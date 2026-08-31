part of blackbox;

/// What a step's failure — an `AsyncError` left standing after the
/// step's retries — does to the run.
///
/// This is the only thing the flag decides. Whether *readers* proceed
/// without the step is not here — that is the wire's word
/// (`onlyWhenReady` / `whenReadyOrNull` / `outputOf`).
enum FailurePolicy {
  /// The error fails the whole run immediately (default).
  fail,

  /// The step stays failed; the run continues. Its readers must use
  /// `whenReadyOrNull`/`outputOf` — an `onlyWhenReady` reader of a
  /// failed step waits forever (the timeout is the net).
  skip,
}

/// Per-step run policy of a [Pipeline] step.
final class _StepPolicy {
  final int retry;
  final FailurePolicy onFailure;
  const _StepPolicy({required this.retry, required this.onFailure});
}

/// Assembles a [Pipeline]. Same shape as [GraphBuilder], plus per-step
/// run policies; `build` requires the result source by signature, so
/// forgetting it is impossible.
final class PipelineBuilder<C, R> {
  final GraphBuilder<C> _gb;
  final Map<OutputSource<dynamic>, _StepPolicy> _policies = {};

  PipelineBuilder({C? context}) : _gb = GraphBuilder._(context);

  /// Declares a step. On top of [GraphBuilder.add], two run policies:
  ///
  /// - [retry]: on `AsyncError` the pipeline re-drives the step via its
  ///   `refresh()`, up to [retry] times, before letting the error stand.
  /// - [onFailure]: what the standing error does to the run —
  ///   [FailurePolicy.fail] (default) or [FailurePolicy.skip].
  ///
  /// Whether a *reader* proceeds without the step is not decided here —
  /// that is the wire's word: `onlyWhenReady` (required),
  /// `whenReadyOrNull` (absence is fine), `outputOf` (the failure itself
  /// is data).
  PipelineBuilder<C, R> add<O>(
    OutputSource<O> box, {
    Object? Function(DependencyResolver<C> d)? input,
    int retry = 0,
    FailurePolicy onFailure = FailurePolicy.fail,
  }) {
    _gb.add<O>(box, input: input);
    if (retry > 0 || onFailure != FailurePolicy.fail) {
      _policies[box] = _StepPolicy(retry: retry, onFailure: onFailure);
    }
    return this;
  }

  /// Fire-and-forget sink, e.g. telemetry per step. See
  /// [GraphBuilder.addEffect].
  PipelineBuilder<C, R> addEffect<I>(
    I Function(DependencyResolver<C> d) input, {
    required FutureOr<void> Function(I current, I? previous) run,
  }) {
    _gb.addEffect<I>(input, run: run);
    return this;
  }

  /// Assembles the pipeline. Does not start it — [Pipeline.start] does,
  /// once. [result] must be one of the declared steps; its output type
  /// is the pipeline's output type. [timeout] belongs to the assembly,
  /// not the call site: a pipeline that can hang is misassembled.
  Pipeline<C, R> build({
    required OutputSource<R> result,
    Duration? timeout,
  }) {
    if (!_gb._declared.contains(result)) {
      throw StateError(
        'PipelineBuilder.build: the result source is not a declared step. '
        'Add it with add(...) — the pipeline completes with its output.',
      );
    }
    _gb._ensureNotBuilt();
    _gb._built = true;
    return Pipeline<C, R>._(
      nodes: List.unmodifiable(_gb._nodes),
      multiboxes: List.unmodifiable(_gb._multiboxes),
      effects: List.unmodifiable(_gb._effects),
      sources: _gb._sources,
      latestOutputs: _gb._latestOutputs,
      declared: List.unmodifiable(_gb._declared),
      context: _gb._context,
      result: result,
      timeout: timeout,
      policies: Map.unmodifiable(_policies),
    );
  }
}

/// The graph, run as a function.
///
/// An application is a graph started to live (`Graph.start`); a pipeline
/// is a graph started once for its result. `Pipeline` adds no topology —
/// it is a run policy over an ordinary [Graph]: same wires, same map
/// (`toMermaid`), same owned resources (`own`).
///
/// One verb: [start]. It runs the graph and completes with the first
/// ready value of the result step:
///
/// ```dart
/// final answer = await Pipeline.builder<void, Rendered>()
///     .add(classify, retry: 2)
///     .add(phrases, input: (d) => d.onlyWhenReady(classify))
///     .add(enrich, onFailure: FailurePolicy.skip)
///     .add(retrieved, input: (d) => (
///           phrases: d.onlyWhenReady(phrases),
///           extra: d.whenReadyOrNull(enrich),   // failed optional → null
///         ))
///     .add(rendered, input: (d) => d.onlyWhenReady(retrieved))
///     .build(result: rendered, timeout: Duration(seconds: 30))
///     .start();
/// ```
///
/// Semantics of [start]:
/// - completes with the result's first `SyncData`/`AsyncData` value;
/// - **fails fast**: a step whose policy is [FailurePolicy.fail]
///   (the default) completes the run with its `AsyncError` (after
///   retries) — no silent hang;
/// - the [timeout] set at build time throws [TimeoutException];
/// - the graph is disposed when the run ends, in every outcome —
///   `own(...)`-ed resources are released;
/// - calling [start] again returns the same future.
final class Pipeline<C, R> extends Graph<C> {
  final OutputSource<R> _result;
  final Duration? _timeout;
  final Map<OutputSource<dynamic>, _StepPolicy> _policies;

  Future<R>? _running;

  Pipeline._({
    required List<_Node<C, dynamic, dynamic>> nodes,
    required List<_MultiBoxNode<C, dynamic>> multiboxes,
    required List<_Effect<C, dynamic>> effects,
    required Set<OutputSource<dynamic>> sources,
    required Map<OutputSource<dynamic>, Output<dynamic>> latestOutputs,
    required List<ProvidableBox> declared,
    required C? context,
    required OutputSource<R> result,
    required Duration? timeout,
    required Map<OutputSource<dynamic>, _StepPolicy> policies,
  })  : _result = result,
        _timeout = timeout,
        _policies = policies,
        super._(
          nodes: nodes,
          multiboxes: multiboxes,
          effects: effects,
          sources: sources,
          latestOutputs: latestOutputs,
          declared: declared,
          context: context,
          onTrace: null,
        );

  static PipelineBuilder<C, R> builder<C, R>({C? context}) =>
      PipelineBuilder<C, R>(context: context);

  /// Runs the pipeline once. See the class doc for the full contract.
  @override
  Future<R> start() => _running ??= _run();

  Future<R> _run() async {
    final completer = Completer<R>();
    final cancels = <Cancel>[];
    final retriesLeft = <OutputSource<dynamic>, int>{
      for (final e in _policies.entries) e.key: e.value.retry,
    };

    void watch(OutputSource<dynamic> source) {
      final isResult = identical(source, _result);
      cancels.add(source.listen((out) {
        if (completer.isCompleted) return;

        if (isResult) {
          if (out is SyncData) {
            completer.complete(out.value as R);
            return;
          }
          if (out is AsyncData) {
            completer.complete(out.value as R);
            return;
          }
        }

        if (out is AsyncError) {
          final left = retriesLeft[source] ?? 0;
          if (left > 0 && source is _AsyncBoxBase) {
            retriesLeft[source] = left - 1;
            unawaited(source.refresh());
            return;
          }
          if (!isResult &&
              _policies[source]?.onFailure == FailurePolicy.skip) {
            return;
          }
          completer.completeError(out.error, out.stackTrace);
        }
      }));
    }

    for (final declared in _declared) {
      if (declared is OutputSource) watch(declared);
    }

    super.start();

    var future = completer.future;
    final timeout = _timeout;
    if (timeout != null) future = future.timeout(timeout);
    try {
      return await future;
    } finally {
      for (final cancel in cancels) {
        cancel();
      }
      dispose();
    }
  }
}
