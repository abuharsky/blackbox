# blackbox_jaspr

Jaspr bindings for `blackbox`.

This package adds UI integration primitives:
- `BoxProvider` to expose boxes in the component tree
- `BoxObserver` to rebuild components when tracked boxes change
- `LocalStorageStore` as a `PersistentStore` implementation for browser `localStorage`

## Features

- Fine-grained rebuilds through tracked box reads
- Simple dependency access via `context.box<T>()`
- Persistence adapter via `LocalStorageStore`
- SSR-safe fallback: outside the browser, `LocalStorageStore` becomes in-memory

## Installation

```yaml
dependencies:
  blackbox_jaspr: ^0.0.4
  blackbox: ^0.4.1
```

## Initialize LocalStorageStore

Call preload once before using persistent boxes:

```dart
Future<void> main() async {
  await LocalStorageStore.preload();
  runApp(const MyApp());
}
```

Register codecs before creating boxes if you persist non-primitive values:

```dart
await LocalStorageStore.preload();
BlackboxPersistence.registerCodec(UserJsonCodec());
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

`LocalStorageStore.preload()` registers the shared store in
`BlackboxPersistence`. In the browser it persists primitive values to
`localStorage`. Outside the browser, it falls back to an in-memory store so SSR
and tests stay deterministic.

## FlowBox Tracking

`FlowBox` participates in `BoxObserver` tracking automatically through core
hooks:

```dart
final flow = FlowBox.builder<MyFlowState>()
    .on(counterBox, (value) => CounterReady(value))
    .build(initial: const CounterIdle());

return BoxObserver(
  builder: (_) => Component.text('${flow.output.value}'),
);
```

## Notes

- `BoxProvider` does not manage lifecycle of boxes. Dispose graphs/subscriptions manually where needed.
- `BoxObserver` tracks boxes read during `builder` execution and rebuilds when those outputs change.
- Tracking runtime is shared through `blackbox_support`; Jaspr only provides component lifecycle and scheduling.
- Boxes with `persistKey` use the global `BlackboxPersistence` store registered by `LocalStorageStore.preload()`.
- `LocalStorageStore` persists primitive values in the browser and uses in-memory storage in SSR/tests; use codecs in core for custom types.

## License

MIT
