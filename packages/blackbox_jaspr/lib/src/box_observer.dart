part of blackbox_jaspr;

/// Rebuilds when any tracked box read during build changes.
///
class BoxObserver extends StatefulComponent {
  const BoxObserver({super.key, required this.builder});

  final Component Function(BuildContext context) builder;

  @override
  State<BoxObserver> createState() => _BoxObserverState();
}

class _BoxObserverState extends State<BoxObserver> {
  late final Reaction _reaction = Reaction(
    invalidate: _invalidate,
    scheduler: const MicrotaskReactionScheduler(),
  );

  void _invalidate() {
    if (!mounted) return;
    setState(() {});
  }

  bool _warnedEmpty = false;

  @override
  Component build(BuildContext context) {
    final result = _reaction.track(() => component.builder(context));
    // An observer that read nothing will never rebuild. The usual cause:
    // box reads moved into a nested builder — separate builds run
    // outside tracking.
    assert(() {
      if (_reaction.trackedCount == 0 && !_warnedEmpty) {
        _warnedEmpty = true;
        print(
          'BoxObserver: build read no boxes — this observer will never '
          'rebuild. Read boxes directly in this builder, or give the '
          'nested component its own BoxObserver.',
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
