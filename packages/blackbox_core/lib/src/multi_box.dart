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
///   final status     = ValueStateBox<PlayerStatus>(PlayerStatus.idle);
///   final position   = ValueStateBox<Duration>(Duration.zero);
///   final trackTitle = ValueStateBox<String>('');
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

  /// Subclass hook. Receives the multibox's input on every change and
  /// routes it into child boxes (via [dispatch]) and/or sets up new
  /// stream subscriptions (via [track]).
  ///
  /// Called for the first time when the graph delivers the initial
  /// input; called again whenever the input changes.
  @protected
  void compute(I input, I? previous);

  /// Push [value] into child Box's input pipeline. Triggers the child's
  /// own `compute`, updates its output, notifies its listeners.
  ///
  /// Only callable from within a [MultiBox] subclass. This is the
  /// controlled bridge that lets subclass code drive children whose
  /// `_updateInput` is otherwise library-private.
  @protected
  void dispatch<T>(Box<T, dynamic> child, T value) =>
      child._updateInput(value);

  /// Async variant of [dispatch] for `AsyncBox` children.
  @protected
  void dispatchAsync<T>(AsyncBox<T, dynamic> child, T value) =>
      child._updateInput(value);

  /// Register a cancel function to be called at [dispose] time.
  ///
  /// Use for stream subscriptions and other transient resources whose
  /// lifetime should match the multibox. Idiomatic usage with streams:
  /// `track(stream.listen(...).cancel);`
  @protected
  void track(Cancel cancel) => _cancels.add(cancel);

  /// Releases all [track]-ed cancels. Subclasses that hold their own
  /// resources (e.g. native plugins) should override and call
  /// `super.dispose()`.
  @mustCallSuper
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final c in _cancels) {
      try {
        c();
      } catch (_) {
        // swallow — best-effort cleanup
      }
    }
    _cancels.clear();
  }

  // Internal entry point — the graph calls this through addMultiBox.
  // Mirrors the role of _SyncBoxBase._updateInput for ordinary boxes.
  void _updateInput(I input) {
    if (_disposed) return;
    final prev = _hasPrevious ? _previous : null;
    compute(input, prev);
    _previous = input;
    _hasPrevious = true;
  }
}
