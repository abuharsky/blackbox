part of blackbox_jaspr;

/// Provides already-created [OutputSource] instances down the component tree.
///
/// This provider does NOT manage lifecycle. You create/dispose boxes yourself.
class BoxProvider extends InheritedComponent {
  const BoxProvider._({
    super.key,
    required Map<Type, OutputSource<dynamic>> boxes,
    required super.child,
  }) : _boxes = boxes;

  final Map<Type, OutputSource<dynamic>> _boxes;

  /// Convenience: single box.
  factory BoxProvider.single({
    Key? key,
    required OutputSource<dynamic> box,
    required Component child,
  }) {
    return BoxProvider._(key: key, boxes: {box.runtimeType: box}, child: child);
  }

  /// Convenience: multiple boxes (stored by their runtimeType).
  factory BoxProvider.multi({
    Key? key,
    required List<OutputSource<dynamic>> boxes,
    required Component child,
  }) {
    final map = <Type, OutputSource<dynamic>>{};
    for (final box in boxes) {
      map[box.runtimeType] = box;
    }
    return BoxProvider._(key: key, boxes: map, child: child);
  }

  static BoxProvider _must(BuildContext context) {
    final provider = context.dependOnInheritedComponentOfExactType<BoxProvider>();
    if (provider == null) {
      throw StateError(
        'BoxProvider not found in the component tree. '
        'Wrap your subtree with BoxProvider(...).',
      );
    }
    return provider;
  }

  /// Get a box by its concrete box type.
  ///
  /// Example: `final counter = BoxProvider.of<CounterBox>(context);`
  static T of<T extends OutputSource<dynamic>>(BuildContext context) {
    final provider = _must(context);
    final box = provider._boxes[T];
    if (box == null) {
      throw StateError('Box $T not found in BoxProvider.');
    }
    return box as T;
  }

  @override
  bool updateShouldNotify(covariant BoxProvider oldComponent) => false;
}

extension BoxProviderContextExt on BuildContext {
  T box<T extends OutputSource<dynamic>>() => BoxProvider.of<T>(this);
}
