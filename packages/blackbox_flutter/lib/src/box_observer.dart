part of blackbox_flutter;

/// Rebuilds when any [ObservableBox] read during build changes.
///
/// Generated observable output getters must call [ObservableBox.reportRead]
/// (typically via `reportRead(); return ...;`) to participate in tracking.
class BoxObserver extends StatefulWidget {
  static void trackBox(box) => _BoxTracker._reportRead(box);

  const BoxObserver({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<BoxObserver> createState() => _BoxObserverState();
}

class _BoxObserverState extends State<BoxObserver> {
  late final _Reaction _reaction = _Reaction(_invalidate);

  void _invalidate() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _reaction.startTracking();
    try {
      return widget.builder(context);
    } finally {
      _reaction.stopTracking();
    }
  }

  @override
  void dispose() {
    _reaction.dispose();
    super.dispose();
  }
}
