part of blackbox;

/// EXPERIMENTAL — an output cell of a [MultiBox].
///
/// The outward-pointing twin of [StateCell]: `state(...)` is what a box
/// remembers (invisible outside), `child(...)` is what a multibox shows
/// (an ordinary [OutputSource] — graph nodes depend on it via
/// `whenReady`, UI subscribes via `listen`/`BoxObserver`).
///
/// One writer: only the owning multibox writes, via `dispatch`. There is
/// no public setter and no way to construct a cell outside `child(...)`,
/// so the rule holds by construction.
final class ChildCell<T> implements OutputSource<T> {
  T _value;
  final bool _distinct;
  bool _disposed = false;
  final List<void Function(SyncData<T>)> _listeners = [];

  ChildCell._(T initial, {required bool distinct})
      : _value = initial,
        _distinct = distinct;

  /// Current value.
  T get value {
    BoxHooks.reportRead(this);
    return _value;
  }

  @override
  SyncData<T> get output {
    BoxHooks.reportRead(this);
    return SyncData(_value);
  }

  @override
  Cancel listen(void Function(Output<T>) listener, {bool skipFirst = false}) {
    void typed(SyncData<T> s) => listener(s);
    _listeners.add(typed);
    if (!skipFirst) typed(SyncData(_value));
    return _cancelGuarded(() => _listeners.remove(typed));
  }

  void _write(T next) {
    if (_disposed) return;
    if (_distinct && next == _value) return;
    _value = next;
    final snapshot = SyncData(_value);
    for (final listener in List.of(_listeners)) {
      listener(snapshot);
    }
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    _listeners.clear();
  }

  @override
  String toString() => 'ChildCell<$T>($_value)';
}

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
/// - Streams feeding cells go through [connect] — the subscription is
///   released automatically before the next [compute] and on [dispose].
/// - Any other resource follows the same rule as in ordinary boxes:
///   keep it in a field, release the old one at the top of [compute]
///   (compute runs exactly when the input changes) and in [dispose].
/// - [dispose] cancels every connection, then runs subclass cleanup
///   (override and call `super.dispose()`).
///
/// Example:
///
/// ```dart
/// class PlayerBox extends MultiBox<Stream> {
///   late final status     = child(PlayerStatus.idle);
///   late final position   = child(Duration.zero);
///   late final trackTitle = child('');
///
///   NativePlayer? _native;
///
///   @override
///   void compute(Stream current) {
///     _native?.release();
///     _native = NativePlayer.create(current.url);
///
///     connect(_native!.onStateChanged, status, map: _mapStatus);
///     connect(_native!.onPositionChanged, position,
///         map: (m) => Duration(microseconds: m));
///     connect(_native!.onTrackChanged, trackTitle,
///         map: (t) => t?.title ?? '');
///   }
///
///   @override
///   void dispose() {
///     _native?.release();
///     super.dispose();
///   }
/// }
/// ```
abstract class MultiBox<I> implements ProvidableBox {
  I? _input;
  bool _hasInput = false;
  bool _disposed = false;
  final List<Cancel> _cancels = [];
  final List<ChildCell<dynamic>> _children = [];

  /// Declares an output cell of this multibox and returns it. Declare
  /// children as `late final` fields:
  ///
  /// ```dart
  /// late final status = child(PlayerStatus.idle);
  /// ```
  ///
  /// The mirror of `state(...)`: `state` is a cell pointing inward
  /// (private memory), `child` is a cell pointing outward (an observable
  /// output). The outside world can read and subscribe; only this
  /// multibox can write, via [dispatch]. Cells are distinct by default —
  /// writing an equal (`==`) value is a no-op (native streams re-emit
  /// identical values constantly); pass `distinct: false` for values
  /// mutated in place.
  ///
  /// Children are disposed with the multibox. `late final` fields
  /// initialize on first access — a child nobody ever touches is never
  /// even created.
  @protected
  ChildCell<T> child<T>(T initial, {bool distinct = true}) {
    final cell = ChildCell<T>._(initial, distinct: distinct);
    _children.add(cell);
    return cell;
  }

  /// Output cells declared via [child] so far, in declaration order.
  /// `late final` children appear here once first accessed.
  List<OutputSource<dynamic>> get children => List.unmodifiable(_children);

  /// Subclass hook. Receives the multibox's input on every change and
  /// routes it into child boxes (via [dispatch]) and/or sets up new
  /// stream subscriptions (via [connect]).
  ///
  /// Called for the first time when the graph delivers the initial
  /// input; called again whenever the input changes. The previous input,
  /// when needed, is a field the subclass owns — same as any memory.
  @protected
  void compute(I input);

  /// Writes [value] into an owned output cell: updates it and notifies
  /// its listeners (graph nodes and UI). Equal values are absorbed by
  /// the cell's distinct guard.
  ///
  /// Only callable from within a [MultiBox] subclass, and only for cells
  /// declared via [child] — the ownership invariant ("a multibox drives
  /// only its own children") is enforced with an assert in debug mode.
  @protected
  void dispatch<T>(ChildCell<T> cell, T value) {
    assert(
      _children.contains(cell),
      'dispatch target $cell is not a child of $runtimeType. '
      'Declare it via `late final field = child(initial)`.',
    );
    cell._write(value);
  }

  /// Connects a stream to an owned output cell: every event is written
  /// into [cell] (through [map], when given). The one-word form of the
  /// dominant `compute` pattern:
  ///
  /// ```dart
  /// connect(_native!.onPosition, position);
  /// connect(_native!.onState, status, map: _mapStatus);
  /// ```
  ///
  /// The subscription is released automatically — before the next
  /// `compute` and on [dispose], so it cannot leak past the current
  /// input cycle.
  @protected
  void connect<S, T>(
    Stream<S> source,
    ChildCell<T> cell, {
    T Function(S event)? map,
  }) {
    assert(
      map != null || source is Stream<T>,
      'connect: a Stream<$S> cannot feed a ChildCell<$T> — pass map:',
    );
    final sub = source.listen((event) {
      dispatch(cell, map != null ? map(event) : event as T);
    });
    _track(sub.cancel);
  }

  // Cycle-scoped cancels used by [connect]: invoked at the start of the
  // next [compute] and at [dispose]. One resource rule for the whole
  // library: streams feeding cells go through [connect]; anything else
  // lives in a field, released at the top of [compute] and in [dispose].
  void _track(Cancel cancel) => _cancels.add(cancel);

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

  /// Releases all [track]-ed cancels and disposes owned output cells
  /// (declared via [child]). Subclasses that hold their own resources
  /// (e.g. native plugins) should override and call `super.dispose()`.
  ///
  /// Safe to combine with `graph.dispose()` — disposal is idempotent.
  @mustCallSuper
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseTracked();
    for (final cell in _children) {
      cell._dispose();
    }
  }

  /// Current input, as last delivered by the graph. Mirrors [Box.input]:
  /// readable from buttons, listeners and helper methods — no manual
  /// mirror field needed. Inside [compute] it already holds the *new*
  /// input. Throws a [StateError] before the graph delivers the first
  /// input.
  I get input {
    if (!_hasInput) {
      throw StateError(
        '$runtimeType.input read before the graph delivered the first '
        'input.',
      );
    }
    return _input as I;
  }

  // Internal entry point — the graph calls this through addMultiBox.
  // Mirrors the role of _SyncBoxBase._updateInput for ordinary boxes.
  void _updateInput(I input) {
    if (_disposed) return;
    // Cancel all subscriptions tracked for the *previous* input cycle
    // before letting the subclass set up new ones for this cycle.
    _releaseTracked();
    // Publish before compute: `input` reads current inside compute too.
    _input = input;
    _hasInput = true;
    compute(input);
  }
}
