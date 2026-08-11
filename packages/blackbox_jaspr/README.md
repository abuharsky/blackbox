# blackbox_jaspr

[Jaspr](https://pub.dev/packages/jaspr) bindings for
[blackbox](https://pub.dev/packages/blackbox) — state management with one
law: `output = compute(input, state)`.

Your boxes are pure Dart and identical between Flutter and Jaspr — this
package provides the web-side delivery and persistence:

- **`BoxObserver`** — rebuilds a component when the boxes it *actually
  read* change;
- **`BoxProvider`** + **`context.box<T>()`** — delivery down the
  component tree;
- **`LocalStorageStore`** — persistence backend for `state(persist:)`
  cells and `Cache(persist:)` on top of `window.localStorage`.

## Setup

```dart
void main() {
  LocalStorageStore.preload();           // persistence backend, once

  final app = createApp(...);            // your graph — pure Dart,
                                         // often the same createApp as the Flutter app
  runApp(BoxProvider.multi(
    boxes: app.boxes,
    child: const App(),
  ));
}
```

## Reading boxes

```dart
class CounterView extends StatelessComponent {
  @override
  Iterable<Component> build(BuildContext context) sync* {
    final counter = context.box<CounterBox>();
    yield BoxObserver(builder: (_) sync* {
      yield text('${counter.value}');
      yield button(onClick: counter.increment, [text('+')]);
    });
  }
}
```

`BoxObserver` subscribes to exactly what the builder reads — components
rebuild independently, at the rhythm of their own data.

## Testing — swap boxes by type

```dart
BoxProvider.overrides(
  overrides: [BoxOverride.of<CounterBox>(mockCounter)],
  child: componentUnderTest,
);
```

`BoxProvider.multi` asserts on two boxes of the same runtime type —
collisions are loud, never silent.

See the [blackbox README](https://pub.dev/packages/blackbox) for the
model, and [ARCHITECTURE.md](https://github.com/abuharsky/blackbox/blob/main/docs/ARCHITECTURE.md)
for how a whole production app is assembled.
