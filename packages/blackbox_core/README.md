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
  int computeValue(int? previous) => _value;

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

### Persistence

```dart
BlackboxPersistence.init(store);
// Then use persistKey in any box constructor:
MyBox() : super(persistKey: 'my_key');
```

### Lifecycle

- `prepare(I input, O? previous)` — called once before first compute
- `dispose()` — called by `graph.dispose()`
- `action(() { ... })` — mutate state and trigger recomputation

## License

MIT
