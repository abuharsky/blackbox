part of blackbox_jaspr;

typedef _Unsubscribe = void Function();

/// A local reaction for a single [BoxObserver].
///
/// Tracks which [OutputSource]s were read during build, subscribes to them,
/// and schedules a single invalidation in a microtask.
class _Reaction {
  _Reaction(this._onInvalidate);

  final VoidCallback _onInvalidate;

  final Set<OutputSource<dynamic>> _deps = <OutputSource<dynamic>>{};
  final Map<OutputSource<dynamic>, _Unsubscribe> _unsubs =
      <OutputSource<dynamic>, _Unsubscribe>{};

  bool _disposed = false;
  bool _scheduled = false;

  void startTracking() {
    if (_disposed) return;
    _clearDeps();
    _BoxTracker._push(this);
  }

  void stopTracking() {
    if (_disposed) return;
    _BoxTracker._pop(this);
  }

  void reportRead(OutputSource<dynamic> box) {
    if (_disposed) return;
    if (_deps.add(box)) {
      var isInitialValue = true;
      _unsubs[box] = box.listen((_) {
        if (isInitialValue) {
          isInitialValue = false;
          return;
        }
        _onDependencyChanged();
      });
    }
  }

  void _onDependencyChanged() {
    if (_disposed) return;
    if (_scheduled) return;
    _scheduled = true;

    scheduleMicrotask(() {
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

  static void _push(_Reaction reaction) => _stack.add(reaction);

  static void _pop(_Reaction reaction) {
    if (_stack.isEmpty) return;

    final last = _stack.removeLast();
    if (!identical(last, reaction)) {
      _stack.add(last);
      _stack.remove(reaction);
    }
  }

  static void _reportRead(OutputSource<dynamic> box) {
    if (_stack.isEmpty) return;
    _stack.last.reportRead(box);
  }
}
