part of blackbox_flutter;

/// Rebuilds when any tracked box read during build changes.
///
class BoxObserver extends StatefulWidget {
  const BoxObserver({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<BoxObserver> createState() => _BoxObserverState();
}

class _BoxObserverState extends State<BoxObserver> {
  late final Reaction _reaction = Reaction(
    invalidate: _invalidate,
    scheduler: _FlutterReactionScheduler(),
  );

  void _invalidate() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _reaction.track(() => widget.builder(context));
  }

  @override
  void dispose() {
    _reaction.dispose();
    super.dispose();
  }
}

final class _FlutterReactionScheduler implements ReactionScheduler {
  _FlutterReactionScheduler({SchedulerBinding? scheduler})
      : _scheduler = scheduler ?? SchedulerBinding.instance;

  final SchedulerBinding _scheduler;

  @override
  void schedule(ReactionTask task) {
    if (_scheduler.schedulerPhase == SchedulerPhase.idle) {
      _scheduler.scheduleFrame();
    }
    _scheduler.addPostFrameCallback((_) => task());
  }
}
