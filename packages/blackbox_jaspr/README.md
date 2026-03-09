# blackbox_jaspr

Jaspr bindings for `blackbox`.

This package adds UI integration primitives:
- `BoxProvider` to expose boxes in the component tree
- `BoxObserver` to rebuild components when tracked boxes change
- `LocalStorageStore` as a `PersistentStore` implementation for browser `localStorage`

## Features

- Fine-grained rebuilds through tracked box reads
- Simple dependency access via `context.box<T>()`
- Persistence adapter for generated persistent boxes
- SSR-safe fallback: outside the browser, `LocalStorageStore` becomes in-memory

## Installation

```yaml
dependencies:
  blackbox_jaspr: ^0.0.1
  blackbox: any
```

## Basic Usage

```dart
BoxProvider.multi(
  boxes: [
    counterBox,
    profileBox,
  ],
  child: const MyPage(),
);
```

```dart
class MyPage extends StatelessComponent {
  const MyPage({super.key});

  @override
  Component build(BuildContext context) {
    final counter = context.box<CounterBox>();

    return BoxObserver(
      builder: (_) {
        final out = counter.output;
        return Component.text('Count: ${out.value}');
      },
    );
  }
}
```

## LocalStorageStore

No preload is required:

```dart
final store = LocalStorageStore();
```

In the browser the store persists primitive values to `localStorage`. Outside
the browser, it falls back to an in-memory store so SSR and tests stay
deterministic.

## Observable FlowBox

Wrap an existing `FlowBox` when you want `BoxObserver` tracking for flow state:

```dart
final flow = FlowBox.builder<MyFlowState>()
    .on(counterBox, (value) => CounterReady(value))
    .build(initial: const CounterIdle());

final observableFlow = flow.observable();

return BoxObserver(
  builder: (_) => Component.text('${observableFlow.output.value}'),
);
```

## Notes

- `BoxProvider` does not manage lifecycle of boxes. Dispose graphs/subscriptions manually where needed.
- `BoxObserver` tracks boxes read during `builder` execution and rebuilds when those outputs change.
- For `@observable` boxes, tracking is injected by `blackbox_codegen`. Do not call `BoxObserver.trackBox(...)` manually from app code.
- `ObservableFlowBox` is the manual adapter for ready-made `FlowBox` instances. It forwards `dispose()` to the wrapped flow.

## License

MIT
