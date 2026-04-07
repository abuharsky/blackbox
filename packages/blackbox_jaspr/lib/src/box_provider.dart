part of blackbox_jaspr;

/// A typed override entry for [BoxProvider.overrides].
///
/// Associates a concrete [OutputSource] with a type key [T], allowing a mock
/// or alternative implementation to be resolved under the original type.
///
/// Example:
/// ```dart
/// BoxProvider.overrides(
///   overrides: [
///     BoxOverride.of<CounterBox>(mockCounterBox),
///     BoxOverride.of<UserBox>(mockUserBox),
///   ],
///   child: componentUnderTest,
/// )
/// ```
class BoxOverride<T extends OutputSource<dynamic>> {
  final Type _key;
  final T _box;

  BoxOverride._(this._key, this._box);

  /// Creates an override that registers [box] under type key [T].
  ///
  /// [T] defaults to the static type of [box] but can be set explicitly to
  /// register the box under a parent type or interface:
  /// ```dart
  /// BoxOverride.of<AbstractCounterBox>(MockCounterBox())
  /// ```
  static BoxOverride<T> of<T extends OutputSource<dynamic>>(T box) =>
      BoxOverride._(T, box);
}

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

  /// Overrides boxes by explicit type key, for testing or scoped DI.
  ///
  /// Each [BoxOverride.of<T>] entry registers a box under type [T], so
  /// components that call `context.box<T>()` will receive the overridden
  /// instance — regardless of the box's actual runtime type.
  ///
  /// Typical uses:
  /// - Component tests: inject mocks/fakes without changing component code.
  /// - Scoped state: give each list item its own isolated box instance.
  /// - Platform/environment switching: swap implementations at runtime.
  factory BoxProvider.overrides({
    Key? key,
    required List<BoxOverride> overrides,
    required Component child,
  }) {
    final map = <Type, OutputSource<dynamic>>{};
    for (final o in overrides) {
      map[o._key] = o._box;
    }
    return BoxProvider._(key: key, boxes: map, child: child);
  }

  /// Get a box by its concrete box type.
  ///
  /// Example: `final counter = BoxProvider.of<CounterBox>(context);`
  static T of<T extends OutputSource<dynamic>>(BuildContext context) {
    OutputSource<dynamic>? match;
    var hasProvider = false;

    context.visitAncestorElements((element) {
      final component = element.component;
      if (component is! BoxProvider) return true;

      hasProvider = true;
      final localMatch = component._boxes[T];
      if (localMatch == null) return true;

      match = localMatch;
      return false;
    });

    if (match == null) {
      if (!hasProvider) {
        throw StateError(
          'BoxProvider not found in the component tree. '
          'Wrap your subtree with BoxProvider(...).',
        );
      }
      throw StateError('Box $T not found in BoxProvider or its ancestors.');
    }
    return match as T;
  }

  @override
  bool updateShouldNotify(covariant BoxProvider oldComponent) => false;
}

extension BoxProviderContextExt on BuildContext {
  T box<T extends OutputSource<dynamic>>() => BoxProvider.of<T>(this);
}
