part of blackbox;

/// Hysteresis as a graph node: a yes/no whose switching up and down
/// costs different time, so jitter at the boundary does not toggle it.
///
/// A thermostat switches on at 19° and off at 21°; this box does the
/// same with time instead of degrees: it switches on after [on] of
/// continuous `true`, off after [off] of continuous `false`. Zero means
/// at once. Off from birth — a switch is off until switched on.
///
/// Two field shapes:
///
/// ```dart
/// // Up at once, down only after three quiet seconds: the analyzer
/// // survives the one-second `loading` dip its own switch causes.
/// final spectrum = HysteresisBox(off: const Duration(seconds: 3));
///
/// // Shown only if loading lasts longer than 300 ms, hidden at once:
/// // a spinner that does not blink on a fast buffer.
/// final spinner = HysteresisBox(on: const Duration(milliseconds: 300));
/// .add(spinner, input: (d) => d.onlyWhenReady(player.state) == PlayerState.loading)
/// ```
///
/// With `on == off` it is a `bool` debounce. It is the answer to the ring
/// that closes through a device (ARCHITECTURE.md "The ring through the
/// device") — after the first exit, intent instead of measurement, has
/// been tried.
///
/// A timer is a button pressed by time: the box remembers what it shows
/// (its one cell), `compute` compares the input to it — same → cancel
/// any pending switch; different → arm the timer of that direction —
/// and the timer presses the button. An input that returns to what is
/// shown before the timer fires cancels it: the dip is swallowed.
final class HysteresisBox extends Box<bool, bool> {
  HysteresisBox({this.on = Duration.zero, this.off = Duration.zero})
      : super.late() {
    if (on < Duration.zero) {
      throw ArgumentError.value(on, 'on', 'must not be negative');
    }
    if (off < Duration.zero) {
      throw ArgumentError.value(off, 'off', 'must not be negative');
    }
  }

  /// How long the input must stay `true` before the output switches on.
  final Duration on;

  /// How long the input must stay `false` before the output switches off.
  final Duration off;

  late final _shown = state(false);
  Timer? _timer;

  @override
  bool compute(bool wanted) {
    _timer?.cancel();
    _timer = null;
    if (wanted == _shown.value) return wanted;
    final delay = wanted ? on : off;
    if (delay == Duration.zero) {
      // At once: memory catches up in a microtask, before any further
      // input can arrive — a zero Timer would let a fast dip through.
      scheduleMicrotask(() => _shown.value = wanted);
      return wanted;
    }
    _timer = Timer(delay, () => _shown.value = wanted); // the button
    return _shown.value;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
