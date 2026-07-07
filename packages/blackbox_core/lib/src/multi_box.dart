part of blackbox;

/// Composite owner with a single graph-driven input `I` and N child
/// boxes whose inputs are routed entirely from inside the multibox.
///
/// `MultiBox` is **abstract** — always subclass it. The graph drives the
/// multibox via its single input; the subclass implements [compute]
/// to wire that input into child boxes (typically by subscribing to
/// streams from native plugins, services, or other boxes, and pushing
/// values into children via [dispatch]).
///
/// Architectural shape:
///
/// - Graph drives MultiBox: `multibox.input(I)` is private; the graph
///   calls it through `_updateInput` like for any other box.
/// - The graph never touches child inputs. Children's inputs are an
///   internal concern of the subclass.
/// - Children's outputs are observable as ordinary `OutputSource<T>`:
///   `whenReady(player.trackTitle)` works in graph builders, and UI
///   subscribes via `Box.listen()` / `ListenableBuilder`.
///
/// Lifecycle:
///
/// - [compute] runs on every input change (driven by the graph).
/// - Use [track] to register stream subscriptions (or any [Cancel])
///   that should be released on [dispose].
/// - [dispose] cancels everything tracked, then runs subclass cleanup
///   (override and call `super.dispose()`).
///
/// Example:
///
/// ```dart
/// class PlayerBox extends MultiBox<Stream> {
///   late final status     = child(valueBox<PlayerStatus>(PlayerStatus.idle));
///   late final position   = child(valueBox<Duration>(Duration.zero));
///   late final trackTitle = child(valueBox<String>(''));
///
///   NativePlayer? _native;
///
///   @override
///   void compute(Stream current, Stream? previous) {
///     _native?.release();
///     _native = NativePlayer.create(current.url);
///
///     track(_native!.onStateChanged.listen((s) =>
///       dispatch(status, _mapStatus(s))).cancel);
///     track(_native!.onPositionChanged.listen((m) =>
///       dispatch(position, Duration(microseconds: m))).cancel);
///     track(_native!.onTrackChanged.listen((t) =>
///       dispatch(trackTitle, t?.title ?? '')).cancel);
///   }
///
///   @override
///   void dispose() {
///     _native?.release();
///     super.dispose();
///   }
/// }
/// ```
abstract class MultiBox<I> {
  I? _previous;
  bool _hasPrevious = false;
  bool _disposed = false;
  final List<Cancel> _cancels = [];
  final List<OutputSource<dynamic>> _children = [];

  /// Registers [box] as an owned child of this multibox and returns it.
  /// Declare children as `late final` fields:
  ///
  /// ```dart
  /// late final status = child(valueBox<PlayerStatus>(PlayerStatus.idle));
  /// ```
  ///
  /// Ownership gives you:
  /// - deterministic lifecycle — children are disposed with the multibox;
  /// - a guarded [dispatch] — only owned children can be driven.
  ///
  /// `late final` fields initialize on first access (from [dispatch], the
  /// UI, or a graph `whenReady`) — a child nobody ever touches is never
  /// even created.
  @protected
  B child<B extends OutputSource<dynamic>>(B box) {
    _children.add(box);
    return box;
  }

  /// Owned children registered via [child] so far, in declaration order.
  /// `late final` children appear here once first accessed.
  List<OutputSource<dynamic>> get children => List.unmodifiable(_children);

  /// Subclass hook. Receives the multibox's input on every change and
  /// routes it into child boxes (via [dispatch]) and/or sets up new
  /// stream subscriptions (via [track]).
  ///
  /// Called for the first time when the graph delivers the initial
  /// input; called again whenever the input changes.
  @protected
  void compute(I input, I? previous);

  /// Push [value] into an owned child's input pipeline. Triggers the
  /// child's own `compute`, updates its output, notifies its listeners.
  ///
  /// Only callable from within a [MultiBox] subclass, and only for boxes
  /// registered via [child] — the ownership invariant ("a multibox drives
  /// only its own children") is enforced with an assert in debug mode.
  @protected
  void dispatch<T>(Box<T, dynamic> box, T value) {
    assert(
      _children.contains(box),
      'dispatch target ${box.runtimeType} is not an owned child of '
      '$runtimeType. Register it via `late final field = child(...)`.',
    );
    box._updateInput(value);
  }

  /// Async variant of [dispatch] for `AsyncBox` children.
  @protected
  void dispatchAsync<T>(AsyncBox<T, dynamic> box, T value) {
    assert(
      _children.contains(box),
      'dispatchAsync target ${box.runtimeType} is not an owned child of '
      '$runtimeType. Register it via `late final field = child(...)`.',
    );
    box._updateInput(value);
  }

  /// Register a cancel function for transient resources scoped to the
  /// **current** input cycle. All registered cancels are automatically
  /// invoked at the start of the next [compute] call (and at [dispose]),
  /// so subclasses don't have to track + clear stream subscriptions
  /// when rebinding to a new input. Idiomatic usage with streams:
  /// `track(stream.listen(...).cancel);`
  ///
  /// Resources whose lifetime must outlive a single input cycle should
  /// be created in the subclass constructor and released in an
  /// override of [dispose] (calling `super.dispose()`).
  @protected
  void track(Cancel cancel) => _cancels.add(cancel);

  void _releaseTracked() {
    if (_cancels.isEmpty) return;
    final snapshot = List<Cancel>.of(_cancels);
    _cancels.clear();
    for (final c in snapshot) {
      try {
        c();
      } catch (_) {
        // best-effort
      }
    }
  }

  /// Releases all [track]-ed cancels and disposes owned children
  /// (registered via [child]). Subclasses that hold their own resources
  /// (e.g. native plugins) should override and call `super.dispose()`.
  ///
  /// Safe to combine with `graph.dispose()` — box disposal is idempotent.
  @mustCallSuper
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseTracked();
    for (final child in _children) {
      _disposeSource(child);
    }
  }

  // Internal entry point — the graph calls this through addMultiBox.
  // Mirrors the role of _SyncBoxBase._updateInput for ordinary boxes.
  void _updateInput(I input) {
    if (_disposed) return;
    final prev = _hasPrevious ? _previous : null;
    // Cancel all subscriptions tracked for the *previous* input cycle
    // before letting the subclass set up new ones for this cycle.
    _releaseTracked();
    compute(input, prev);
    _previous = input;
    _hasPrevious = true;
  }
}
