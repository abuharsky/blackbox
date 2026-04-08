# blackbox

Reactive state management core for Dart.

Boxes hold state. Graphs wire dependencies. No code generation. No boilerplate.

See the full documentation with examples: [README](https://github.com/abuharsky/blackbox#readme)

## Quick Start

```dart
import 'package:blackbox/blackbox.dart';

class CounterBox extends NoInputBox<int> {
  int _value = 0;

  @override
  int compute(int? previous) => _value;

  void inc() => action(() => _value++);
}
```

## API

### Box Types

| Class | Input | Sync/Async |
|-------|-------|------------|
| `NoInputBox<O>` | none | sync |
| `Box<I, O>` | yes | sync |
| `NoInputAsyncBox<O>` | none | async |
| `AsyncBox<I, O>` | yes | async |

### Graph

```dart
final graph = Graph.builder()
    .add(boxA)
    .add(boxB, input: (d) => d.whenReady(boxA))
    .build(start: true);
```

### Effects

```dart
Graph.builder()
    .add(checkoutState)
    .addEffect<CheckoutState>(
      (d) => d.whenReady(checkoutState),
      run: (current, previous) {
        if (previous is! CheckoutSuccess && current is CheckoutSuccess) {
          cart.clear();
        }
      },
    )
    .build(start: true);
```

Effects are explicit graph sinks:
- they run only when their input changes
- they receive `current` and `previous`
- async handlers are fire-and-forget

### Persistence

```dart
BlackboxPersistence.init(
  store,
  codecs: [UserJsonCodec()],
);

// Then use persistKey in any box constructor:
MyBox() : super(persistKey: 'my_key');
```

Built-in codecs exist for `int`, `double`, `String`, and `bool`.
Use `BlackboxPersistence.registerCodec(...)` or `init(..., codecs: [...])`
for any other persisted type.

In Flutter and Jaspr apps, prefer the platform adapters:
- `await SharedPrefsStore.preload()` from `blackbox_flutter`
- `await LocalStorageStore.preload()` from `blackbox_jaspr`

### Lifecycle

- `prepare(I input, O? previous)` — called once before first compute
- `dispose()` — called by `graph.dispose()`
- `action(() { ... })` — mutate state and trigger recomputation

## License

MIT
