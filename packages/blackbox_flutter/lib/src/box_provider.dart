part of blackbox_flutter;

/// Provides already-created [OutputSource] instances down the widget tree.
///
/// This provider does NOT manage lifecycle. You create/dispose boxes yourself.
class BoxProvider extends InheritedWidget {
  const BoxProvider._({
    super.key,
    required Map<Type, OutputSource> boxes,
    required super.child,
  }) : _boxes = boxes;

  final Map<Type, OutputSource> _boxes;

  /// Convenience: single box.
  factory BoxProvider.single({
    Key? key,
    required OutputSource box,
    required Widget child,
  }) {
    return BoxProvider._(key: key, boxes: {box.runtimeType: box}, child: child);
  }

  /// Convenience: multiple boxes (stored by their runtimeType).
  factory BoxProvider.multi({
    Key? key,
    required List<OutputSource> boxes,
    required Widget child,
  }) {
    final map = <Type, OutputSource>{};
    for (final b in boxes) {
      map[b.runtimeType] = b;
    }
    return BoxProvider._(key: key, boxes: map, child: child);
  }

  static BoxProvider _must(BuildContext context) {
    final p = context.dependOnInheritedWidgetOfExactType<BoxProvider>();
    if (p == null) {
      throw FlutterError(
        'BoxProvider not found in the widget tree.\n'
        'Wrap your subtree with BoxProvider(...).',
      );
    }
    return p;
  }

  /// Get an observable by its concrete observable type.
  ///
  /// Example: `final counter = BoxProvider.of<ObservableCounterBox>(context);`
  static T of<T extends OutputSource>(BuildContext context) {
    final p = _must(context);
    final v = p._boxes[T];
    if (v == null) {
      throw FlutterError('Box $T not found in BoxProvider.');
    }
    return v as T;
  }

  @override
  bool updateShouldNotify(covariant BoxProvider oldWidget) => false;
}

extension BoxProviderContextExt on BuildContext {
  T box<T extends OutputSource>() => BoxProvider.of<T>(this);
}
