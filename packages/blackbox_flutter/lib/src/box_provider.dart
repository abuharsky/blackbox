part of blackbox_flutter;

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
///   child: widgetUnderTest,
/// )
/// ```
class BoxOverride<T extends OutputSource> {
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
  static BoxOverride<T> of<T extends OutputSource>(T box) =>
      BoxOverride._(T, box);
}

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

  /// Overrides boxes by explicit type key, for testing or scoped DI.
  ///
  /// Each [BoxOverride.of<T>] entry registers a box under type [T], so widgets
  /// that call `context.box<T>()` will receive the overridden instance —
  /// regardless of the box's actual runtime type.
  ///
  /// Typical uses:
  /// - Widget tests: inject mocks/fakes without changing widget code.
  /// - Scoped state: give each list item its own isolated box instance.
  /// - Platform/environment switching: swap implementations at runtime.
  factory BoxProvider.overrides({
    Key? key,
    required List<BoxOverride> overrides,
    required Widget child,
  }) {
    final map = <Type, OutputSource>{};
    for (final o in overrides) {
      map[o._key] = o._box;
    }
    return BoxProvider._(key: key, boxes: map, child: child);
  }

  /// Get an observable by its concrete observable type.
  ///
  /// Example: `final counter = BoxProvider.of<ObservableCounterBox>(context);`
  static T of<T extends OutputSource>(BuildContext context) {
    OutputSource? match;
    var hasProvider = false;

    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is! BoxProvider) return true;

      hasProvider = true;
      final localMatch = widget._boxes[T];
      if (localMatch == null) return true;

      match = localMatch;
      return false;
    });

    if (match == null) {
      if (!hasProvider) {
        throw FlutterError(
          'BoxProvider not found in the widget tree.\n'
          'Wrap your subtree with BoxProvider(...).',
        );
      }
      throw FlutterError('Box $T not found in BoxProvider or its ancestors.');
    }
    return match as T;
  }

  @override
  bool updateShouldNotify(covariant BoxProvider oldWidget) => false;
}

extension BoxProviderContextExt on BuildContext {
  T box<T extends OutputSource>() => BoxProvider.of<T>(this);
}
