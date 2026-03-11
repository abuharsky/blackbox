part of blackbox_support;

typedef ReactionInvalidate = void Function();
typedef ReactionTask = void Function();
typedef ReactionUnsubscribe = void Function();

abstract interface class ReactionScheduler {
  void schedule(ReactionTask task);
}

final class MicrotaskReactionScheduler implements ReactionScheduler {
  const MicrotaskReactionScheduler();

  @override
  void schedule(ReactionTask task) => scheduleMicrotask(task);
}

final class Reaction implements BoxHooksSink {
  Reaction({
    required ReactionInvalidate invalidate,
    required ReactionScheduler scheduler,
  })  : _invalidate = invalidate,
        _scheduler = scheduler;

  final ReactionInvalidate _invalidate;
  final ReactionScheduler _scheduler;

  final Set<OutputSource<dynamic>> _deps = <OutputSource<dynamic>>{};
  final Map<OutputSource<dynamic>, ReactionUnsubscribe> _unsubs =
      <OutputSource<dynamic>, ReactionUnsubscribe>{};

  bool _disposed = false;
  bool _scheduled = false;

  T track<T>(T Function() body) {
    if (_disposed) return body();
    _clearDeps();
    return BoxHooks.runWith(this, body);
  }

  @override
  void onRead(OutputSource<dynamic> source) {
    if (_disposed) return;
    if (!_deps.add(source)) return;

    var isInitialValue = true;
    _unsubs[source] = source.listen((_) {
      if (isInitialValue) {
        isInitialValue = false;
        return;
      }
      _onDependencyChanged();
    });
  }

  void _onDependencyChanged() {
    if (_disposed || _scheduled) return;
    _scheduled = true;

    _scheduler.schedule(() {
      if (_disposed) return;
      _scheduled = false;
      _invalidate();
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
