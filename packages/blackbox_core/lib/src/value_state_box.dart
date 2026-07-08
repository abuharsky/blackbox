part of blackbox;

/// A simple state box with identity compute.
///
/// `ValueStateBox<T>` is a `Box<T, T>` whose [compute] passes the input
/// through unchanged. The simplest possible reactive cell — read via
/// [value], subscribe via [listen]. Driven only by the graph or by a
/// `MultiBox` parent (no public write API).
///
/// By default the box is **distinct**: pushing a value equal (`==`) to the
/// current one is a no-op — no listeners fire, no graph pump is scheduled.
/// Native platform streams routinely re-emit identical statuses/titles many
/// times per second; distinct cells absorb that noise at the source. Pass
/// `distinct: false` for values mutated in place (where `==` can't detect
/// the change).
///
/// Typical uses:
/// - leaf state inside a [MultiBox] composite (e.g. `currentTrack`,
///   `playerStatus`)
/// - graph-driven observable cells with no transform of their own
///
/// Subclass to compose with capability mixins (e.g. `Persisted`):
///
/// ```dart
/// class ThemeBox extends ValueStateBox<ThemeMode>
///     with Persisted<ThemeMode, ThemeMode> {
///   ThemeBox() : super(ThemeMode.system);
///   @override
///   String persistKeyFor(ThemeMode _) => 'theme';
/// }
/// ```
@Deprecated(
  'Use MultiBox.child(initial) for composite outputs, or state(...) cells '
  'for internal memory. ValueStateBox will be removed before 1.0.',
)
class ValueStateBox<T> extends Box<T, T> {
  final bool _distinct;

  ValueStateBox(T initial, {bool distinct = true})
      : _distinct = distinct,
        super(initial, initialValue: initial);

  @override
  void onFirstCompute(T input, T? previous) {
    // Identity box: a restored/previous value (e.g. from `Persisted`)
    // becomes the effective initial input, so the box starts from it
    // instead of the constructor default.
    if (previous != null) _input = previous;
  }

  @override
  void _updateInput(T input) {
    if (_distinct && input == _state.value) {
      _input = input;
      return;
    }
    super._updateInput(input);
  }

  @override
  T compute(T input, T? previous) => input;
}

/// Factory shorthand for [ValueStateBox<T>].
@Deprecated(
  'Use MultiBox.child(initial) for composite outputs, or state(...) cells '
  'for internal memory. valueBox will be removed before 1.0.',
)
// ignore: deprecated_member_use_from_same_package
ValueStateBox<T> valueBox<T>(T initial, {bool distinct = true}) =>
    // ignore: deprecated_member_use_from_same_package
    ValueStateBox<T>(initial, distinct: distinct);
