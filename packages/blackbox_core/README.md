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

Add a mixin to any box — implement `persistKeyFor()` and you're done:

```dart
// Sync box
class ThemeBox extends NoInputBox<String> with Persisted<void, String> {
  @override
  String persistKeyFor(void _) => 'theme';
  // ...
}

// Async box with persistence only
class UserBox extends AsyncBox<String, User>
    with AsyncPersisted<String, User> {
  @override
  String persistKeyFor(String id) => 'user:$id';
  // ...
}

// Async box with persistence + managed cache
class CachedUserBox extends AsyncBox<String, User>
    with AsyncPersisted<String, User>, ManagedCache<String, User> {
  @override
  String persistKeyFor(String id) => 'user:$id';

  @override
  Duration get cacheTtl => Duration(minutes: 5);
  // ...
}
```

Initialize persistence once before creating persistent boxes:

```dart
BlackboxPersistence.init(store, codecs: [UserJsonCodec()]);
```

Built-in codecs exist for `int`, `double`, `String`, and `bool`.

| Mixin | For | Features |
|-------|-----|----------|
| `Persisted<I, O>` | `Box`, `NoInputBox` | save/restore |
| `AsyncPersisted<I, O>` | `AsyncBox`, `NoInputAsyncBox` | save/restore |
| `ManagedCache<I, O>` | on `AsyncPersisted` | TTL, stale-while-refresh, `refresh()`, `invalidateCache()` |

`ManagedCache.refresh()` is deduplicated per box instance and completes when the active refresh finishes.

In Flutter and Jaspr apps, prefer the platform adapters:
- `await SharedPrefsStore.preload()` from `blackbox_flutter`
- `await LocalStorageStore.preload()` from `blackbox_jaspr`

### Lifecycle

- `resolveInitialValue(I input, O? initialValue)` — seed the initial state before the first compute
- `onFirstCompute(I input, O? previous)` — called once before the first compute
- `beforeCompute(I input, O? previous)` — optionally short-circuit `compute()` with a ready `Future`
- `onReady()` — called after initialization, before the first recompute
- `dispose()` — called by `graph.dispose()`
- `action(() { ... })` — mutate state and trigger recomputation
- `await action(() async { ... })` — for async boxes, completes after the recompute finishes

## License

MIT
