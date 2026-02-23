# blackbox_flutter

Flutter bindings for `blackbox`.

This package adds UI integration primitives:
- `BoxProvider` to expose boxes in the widget tree
- `BoxObserver` to rebuild widgets when tracked boxes change
- `SharedPrefsStore` as a `PersistentStore` implementation based on `shared_preferences`

## Features

- Fine-grained rebuilds through tracked box reads
- Simple dependency access via `context.box<T>()`
- Persistence adapter for generated persistent boxes

## Installation

```yaml
dependencies:
  blackbox_flutter: ^0.2.0
  blackbox: any
```

## Initialize SharedPrefsStore

Call preload once before using persistent boxes:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPrefsStore.preload();
  runApp(const MyApp());
}
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
class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final counter = context.box<AsyncCounterBox>();

    return BoxObserver(
      builder: (_) {
        final out = counter.output;
        return out.when(
          data: (value) => Text('Count: $value'),
          loading: () => const Text('Loading...'),
          error: (error, _) => Text('Error: $error'),
        );
      },
    );
  }
}
```

## Notes

- `BoxProvider` does not manage lifecycle of boxes. Dispose connectors/subscriptions manually where needed.
- `BoxObserver` tracks boxes read during `builder` execution and rebuilds when those outputs change.

## License

MIT
