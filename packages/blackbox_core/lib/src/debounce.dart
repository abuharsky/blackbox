part of blackbox;

/// Sentinel for "nothing shown yet" — a debounce over a nullable type
/// must tell a shown `null` from no value at all.
const Object _nothingShown = Object();

/// Debounce as a graph node: the input, once it has stopped changing
/// for [window].
///
/// Every change restarts the clock; only a value that is followed by a
/// full [window] of silence gets out. Changes that come faster than the
/// window collapse into the last one — three metadata sources reporting
/// the same track in three pieces become one change, one lookup. A value
/// that keeps changing without pause never gets out; that is the
/// contract, not a bug (a slider that never rests wants a throttle,
/// which this is not).
///
/// The first value passes at once — there is nothing to hold instead.
///
/// ```dart
/// final track = DebounceBox<TrackInfo?>(const Duration(seconds: 1));
/// // ...
/// .add(track, input: (d) => d.onlyWhenReady(player.streamTrack))
/// .addEffect<TrackInfo?>((d) => d.onlyWhenReady(track), name: 'artwork', run: ...)
/// ```
///
/// A timer is a button pressed by time: the box remembers what it shows
/// (its one cell), `compute` compares the input to it, and the timer
/// presses the button. On the map it is a node; in tests it runs on
/// virtual time (`fake_async`). Before reaching for one, run the four
/// cheaper checks in ARCHITECTURE.md "A timer is a button pressed by
/// time" — most "too often" problems need no timer.
final class DebounceBox<T> extends Box<T, T> {
  /// [window] is how long the input must stay unchanged to get out.
  DebounceBox(this.window) : super.late() {
    if (window <= Duration.zero) {
      throw ArgumentError.value(window, 'window', 'must be positive');
    }
  }

  final Duration window;

  late final _shown = state<Object?>(_nothingShown);
  Timer? _timer;

  @override
  T compute(T input) {
    _timer?.cancel();
    _timer = null;
    final shown = _shown.value;
    if (identical(shown, _nothingShown)) {
      // First value: passes at once; memory catches up before any
      // further input can arrive (a microtask runs before the next event).
      scheduleMicrotask(() => _shown.value = input);
      return input;
    }
    if (shown == input) return input;
    _timer = Timer(window, () => _shown.value = input); // the button
    return shown as T;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
