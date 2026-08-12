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

  bool _warnedEmpty = false;

  @override
  Widget build(BuildContext context) {
    final result = _reaction.track(() => widget.builder(context));
    // An observer that read nothing will never rebuild. The usual cause:
    // box reads moved into a nested builder (Builder, LayoutBuilder,
    // a child: closure) — those run as separate builds, outside tracking.
    assert(() {
      if (_reaction.trackedCount == 0 && !_warnedEmpty) {
        _warnedEmpty = true;
        debugPrint(
          'BoxObserver: build read no boxes — this observer will never '
          'rebuild. Read boxes directly in this builder, or give the '
          'nested widget its own BoxObserver.\n'
          'Location: ${context.widget}',
        );
      }
      return true;
    }());
    return result;
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
