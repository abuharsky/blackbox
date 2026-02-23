part of blackbox_flutter;

typedef _Unsubscribe = void Function();

/// A local reaction for a single [BoxObserver].
///
/// Tracks which [ObservableBox]es were read during build, subscribes to them,
/// and schedules a single invalidation (batched + frame-debounced).
class _Reaction {
  _Reaction(this._onInvalidate, {SchedulerBinding? scheduler})
      : _scheduler = scheduler ?? SchedulerBinding.instance;

  final VoidCallback _onInvalidate;
  final SchedulerBinding _scheduler;

  final Set<OutputSource> _deps = <OutputSource>{};
  final Map<OutputSource, _Unsubscribe> _unsubs =
      <OutputSource, _Unsubscribe>{};

  bool _disposed = false;
  bool _scheduled = false;

  VoidCallback? _cancel;

  void startTracking() {
    if (_disposed) return;
    _clearDeps();
    _BoxTracker._push(this);
  }

  void stopTracking() {
    if (_disposed) return;
    _BoxTracker._pop(this);
  }

  void reportRead(OutputSource box) {
    if (_disposed) return;
    if (_deps.add(box)) {
      // Subscribe once per build-cycle.
      void listener(box) => _onDependencyChanged();
      _cancel = box.listen(listener);
      _unsubs[box] = _cancel!;
    }
  }

  void _onDependencyChanged() {
    if (_disposed) return;
    if (_scheduled) return;
    _scheduled = true;

    // Ensure there will be a frame. If we're idle, schedule one.
    if (_scheduler.schedulerPhase == SchedulerPhase.idle) {
      _scheduler.scheduleFrame();
    }

    // Rebuild once after the current frame completes.
    _scheduler.addPostFrameCallback((_) {
      if (_disposed) return;
      _scheduled = false;
      _onInvalidate();
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearDeps();
  }

  void _clearDeps() {
    for (final unsub in _unsubs.values) {
      unsub();
    }
    _unsubs.clear();
    _deps.clear();
  }
}

/// Global tracker implemented as a stack to support nested [BoxObserver]s.
class _BoxTracker {
  static final List<_Reaction> _stack = <_Reaction>[];

  static void _push(_Reaction r) => _stack.add(r);

  static void _pop(_Reaction r) {
    if (_stack.isEmpty) return;

    final last = _stack.removeLast();
    if (!identical(last, r)) {
      // Defensive: if mis-nested, try to recover without crashing.
      _stack.add(last);
      _stack.remove(r);
    }
  }

  static void _reportRead(dynamic box) {
    if (_stack.isEmpty) return;
    _stack.last.reportRead(box);
  }
}
