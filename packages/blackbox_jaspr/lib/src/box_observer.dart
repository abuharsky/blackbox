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

  @override
  Component build(BuildContext context) {
    return _reaction.track(() => component.builder(context));
  }

  @override
  void dispose() {
    _reaction.dispose();
    super.dispose();
  }
}
