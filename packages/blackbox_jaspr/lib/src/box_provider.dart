part of blackbox_jaspr;

/// A typed override entry for [BoxProvider.overrides].
///
/// Associates a concrete [ProvidableBox] with a type key [T], allowing a mock
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
class BoxOverride<T extends ProvidableBox> {
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
  static BoxOverride<T> of<T extends ProvidableBox>(T box) =>
      BoxOverride._(T, box);
}

/// Provides already-created [ProvidableBox] instances down the component tree.
///
/// This provider does NOT manage lifecycle. You create/dispose boxes yourself.
class BoxProvider extends InheritedComponent {
  const BoxProvider._({
    super.key,
    required Map<Type, ProvidableBox> boxes,
    required super.child,
  }) : _boxes = boxes;

  final Map<Type, ProvidableBox> _boxes;

  /// Convenience: single box.
  factory BoxProvider.single({
    Key? key,
    required ProvidableBox box,
    required Component child,
  }) {
    return BoxProvider._(key: key, boxes: {box.runtimeType: box}, child: child);
  }

  /// Convenience: multiple boxes (stored by their runtimeType).
  ///
  /// Two boxes of the same runtime type cannot share one provider —
  /// `context.box<T>()` would silently return the last one. The factory
  /// asserts on duplicates: give twins distinct types, or scope the
  /// second instance with its own [BoxProvider] / [BoxProvider.overrides].
  factory BoxProvider.multi({
    Key? key,
    required List<ProvidableBox> boxes,
    required Component child,
  }) {
    final map = <Type, ProvidableBox>{};
    for (final box in boxes) {
      assert(
        !map.containsKey(box.runtimeType),
        'BoxProvider.multi: two boxes of type ${box.runtimeType}. '
        'context.box<${box.runtimeType}>() cannot tell them apart — give '
        'them distinct types, or provide the second one via a nested '
        'BoxProvider / BoxProvider.overrides.',
      );
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
    final map = <Type, ProvidableBox>{};
    for (final o in overrides) {
      map[o._key] = o._box;
    }
    return BoxProvider._(key: key, boxes: map, child: child);
  }

  /// Get a box by its concrete box type.
  ///
  /// Example: `final counter = BoxProvider.of<CounterBox>(context);`
  static T of<T extends ProvidableBox>(BuildContext context) {
    ProvidableBox? match;
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
  T box<T extends ProvidableBox>() => BoxProvider.of<T>(this);
}
