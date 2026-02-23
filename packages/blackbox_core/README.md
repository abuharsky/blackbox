# blackbox

Deterministic reactive computation core for Dart.

`blackbox` provides explicit, testable building blocks for business logic:
- `Box` / `AsyncBox`
- `BoxWithInput` / `AsyncBoxWithInput`
- `Connector` for dependency wiring
- `Pipeline` for one-shot execution
- `StateObserver` for derived reactive state
- Persistence primitives (`PersistentStore`, `PersistentCodec`, `Persistent`)

## Features

- Explicit dependency graph via `Connector.builder()`
- Deterministic recomputation (no implicit widget/runtime magic)
- Sync and async outputs (`SyncOutput`, `AsyncOutput`)
- Fail-fast semantics for missing/not-ready dependencies
- Works without Flutter (CLI, backend, pure Dart)

## Installation

```bash
dart pub add blackbox
```

## Quick Start

```dart
import 'package:blackbox/blackbox.dart';

final class CounterBox extends Box<int> {
  int _value = 0;

  void inc() => action(() => _value++);

  @override
  int compute(int? previousOutputValue) => _value;
}

void main() {
  final counter = CounterBox();
  final cancel = counter.listen((out) {
    final value = switch (out) {
      SyncOutput<int>(:final value) => value,
      _ => -1,
    };
    print('counter=$value');
  });

  counter.inc();
  counter.inc();
  cancel();
}
```

## Connector Example

```dart
final step = StepBox();
final counter = CounterWithStepBox(input: 1);

final connector = Connector.builder()
    .connect(step)
    .connectWith(
      counter,
      dependencies: (d) => d.require(step),
    )
    .build(start: true);

// ... use boxes
connector.dispose();
```

## Pipeline Example

```dart
final pipeline = Pipeline.builder<void, int>()
    .add(sourceBox)
    .addWithDependencies(
      targetBox,
      dependencies: (d) => d.require(sourceBox),
    )
    .result(targetBox)
    .build();

final result = await pipeline.run();
pipeline.dispose();
```

## Output Model

- `SyncOutput<T>`: immediate ready value
- `AsyncLoading<T>`: pending
- `AsyncData<T>`: ready async value
- `AsyncError<T>`: async error state

For async outputs, use:

```dart
output.when(
  data: (v) => ...,
  loading: () => ...,
  error: (e, st) => ...,
);
```

## Persistence

Implement:
- `PersistentStore` for key-value storage
- `PersistentCodec<O>` for serialization

Then use `Persistent<O>` in your boxes (or generated code) to load/save values.

## Additional Docs

- Russian docs: `doc/README_RU.md`
- Internals: `doc/internals_ru.md`
- FAQ: `doc/faq_ru.md`

## License

MIT
