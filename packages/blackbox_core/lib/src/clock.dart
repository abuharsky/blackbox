part of blackbox;

/// The clock as a graph node — the library home of "time is delivered,
/// never read".
///
/// `compute` must not read the wall clock, so someone must deliver it.
/// `ClockBox` is that someone: one self-driven node owning every timer,
/// handing time out as keyed cells. **The schedule lives in the
/// subscription** — each reader names the moments it wants to see, and
/// pays only for those:
///
/// - [at] — "wake me at this moment": a cell that is `false` until the
///   moment and `true` from then on. A node or effect wiring it is
///   pumped exactly once, at the boundary — between boundaries the
///   clock is silent. A moment already in the past is `true` from
///   birth: a late reader sees a fired alarm, not a missed event.
/// - [every] — "I want each tick": a cell carrying the time of the
///   latest tick. Wiring it into the graph is choosing to pay one pump
///   per tick — a deliberate, visible cost.
/// - UI that only *displays* ticking (a stopwatch, a countdown)
///   subscribes to [every]'s cell via `listen` / `BoxObserver`,
///   bypassing the graph entirely: widgets rebuild, no node pumps.
///
/// Cells are memoized by their key (the moment / the period) — honest
/// slot keys: ask twice, get the same cell. Keys accumulate for the
/// clock's lifetime, so a clock belongs to a bounded scope — a session
/// graph (disposed with the run), or an app graph fed *recurring* keys,
/// not an unbounded stream of one-off moments.
///
/// ```dart
/// final clock = ClockBox();
/// Graph.builder<Recipe>(context: recipe)
///   .addMultiBox(clock)                          // self-driven
///   .addEffect<({BrewStep step, bool fired})>(
///     (d) {
///       final step = d.onlyWhenReady(flow);
///       final deadline = step.deadline;          // from delivered timestamps
///       return (
///         step: step,
///         fired: deadline != null && d.onlyWhenReady(clock.at(deadline)),
///       );
///     },
///     run: (cur, prev) {
///       if (cur.fired && prev?.fired != true) flow.dispatch(TimeUp());
///     },
///   )
/// ```
///
/// There is deliberately no `after(Duration)`: "after" hides its epoch
/// (after *what*?), and a hidden epoch is a dishonest key. Compute the
/// deadline from a delivered timestamp and ask for [at].
final class ClockBox extends MultiBox<void> {
  /// [now] is injectable for tests; production uses the wall clock.
  ClockBox({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<DateTime, ChildCell<bool>> _alarms = {};
  final Map<Duration, ChildCell<DateTime>> _tickers = {};
  final List<Timer> _timers = [];

  @override
  void compute(void _) {} // self-driven: nothing to start, cells arm on demand

  /// The moment [moment] as a value: `false` before it, `true` from
  /// then on — one notification, at the boundary. A past [moment] is
  /// `true` from birth. Memoized by [moment].
  OutputSource<bool> at(DateTime moment) => _alarms.putIfAbsent(moment, () {
        final delay = moment.difference(_now());
        if (delay <= Duration.zero) return child(true);
        final cell = child(false);
        _timers.add(Timer(delay, () => dispatch(cell, true)));
        return cell;
      });

  /// The latest tick of a [period] metronome, as the time it happened.
  /// Born with the current time, then one notification per tick.
  /// Memoized by [period].
  OutputSource<DateTime> every(Duration period) {
    if (period <= Duration.zero) {
      throw ArgumentError.value(period, 'period', 'must be positive');
    }
    return _tickers.putIfAbsent(period, () {
      final cell = child(_now());
      _timers.add(Timer.periodic(period, (_) => dispatch(cell, _now())));
      return cell;
    });
  }

  /// Cancels every timer, then disposes the cells with the multibox.
  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}
