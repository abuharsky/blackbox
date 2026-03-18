# Blackbox

Reactive state management for Dart, Flutter, and Jaspr.

All your business logic lives in **boxes**. All dependencies between boxes are declared in one place — the **graph**. No code generation. No boilerplate.

## Why Blackbox?

Most state management libraries (Riverpod, Bloc, MobX, Redux) are great — Blackbox was inspired by them. But they share a common problem: **dependencies between state units are scattered across the codebase**. In Riverpod, every `ref.watch` is an implicit edge in your dependency graph, spread across dozens of files. When something breaks in a chain of 5 providers, you have to mentally reconstruct the graph by reading every file.

Blackbox takes a different approach:

- **Graph in one place.** You see every dependency at a glance.
- **No code generation.** A box is a plain Dart class — 10-15 lines.
- **Built-in persistence.** Add `persistKey` to any box constructor — done.
- **Cross-platform.** Boxes are pure Dart. Same logic runs in Flutter and Jaspr (web).
- **Automatic cascading.** Logout? Auth outputs `null` → Profile, History, Loyalty recompute automatically. No manual reset needed.

## Installation

```yaml
# Core (pure Dart — works everywhere)
dependencies:
  blackbox: ^0.2.0

# Flutter app
  blackbox_flutter: ^0.0.4

# Jaspr web app
  blackbox_jaspr: ^0.0.1
```

## Core Concepts

### Box

A **box** is a unit of state. It holds a value, recomputes it when input changes, and notifies listeners.

There are 4 base classes:

| Class | Input | Sync/Async |
|-------|-------|------------|
| `NoInputBox<O>` | no input | sync |
| `Box<I, O>` | has input | sync |
| `NoInputAsyncBox<O>` | no input | async |
| `AsyncBox<I, O>` | has input | async |

### Graph

A **graph** wires boxes together. It declares which box depends on which and automatically propagates changes through the chain — when one box updates, all dependent boxes recompute.

### Action

An **action** is how you mutate state inside a box. Call `action(() { ... })` — it updates internal state and triggers recomputation.

### Pipeline

A **pipeline** is a one-shot graph. It runs once, returns the result from the final box, and disposes itself.

## Quick Start: Counter

```dart
import 'package:blackbox/blackbox.dart';

// A box with no input, outputs an int
class CounterBox extends NoInputBox<int> {
  int _value = 0;

  @override
  int compute(int? previous) => _value;

  void inc() => action(() => _value++);
  void dec() => action(() => _value--);
}

void main() {
  final counter = CounterBox();

  counter.listen((output) {
    print('counter = ${(output as SyncOutput<int>).value}');
  });

  counter.inc(); // prints: counter = 1
  counter.inc(); // prints: counter = 2
}
```

## Graph: Connecting Boxes

Boxes become powerful when you connect them. Here a `StepBox` controls the step size, and `CounterBox` uses it:

```dart
class StepBox extends NoInputBox<int> {
  int _step = 1;

  @override
  int compute(int? previous) => _step;

  void set(int step) => action(() => _step = step);
}

class CounterBox extends Box<int, int> {
  int _value = 0;
  late int _step;

  CounterBox({required int input}) : super(input);

  @override
  void prepare(int input, int? previous) {
    _step = input;
    _value = previous ?? 0;
  }

  @override
  int compute(int input, int? previous) {
    _step = input;
    return _value;
  }

  void inc() => action(() => _value += _step);
}

void main() {
  final step = StepBox();
  final counter = CounterBox(input: 1);

  // Wire dependencies — all in one place
  final graph = Graph.builder()
      .add(step)
      .add(counter, input: (d) => d.whenReady(step))
      .build(start: true);

  counter.inc(); // increments by 1
  step.set(5);   // now step is 5
  counter.inc(); // increments by 5

  graph.dispose();
}
```

`d.whenReady(step)` means: "when `step` is ready, take its value and pass as input to `counter`". If `step` is async and still loading, `counter` waits.

## Async Boxes

For operations like API calls, use `AsyncBox` or `NoInputAsyncBox`:

```dart
class UsersBox extends NoInputAsyncBox<List<User>> {
  final ApiClient _api;

  UsersBox(this._api);

  @override
  Future<List<User>> compute(List<User>? previous) =>
      _api.fetchUsers();

  void refresh() => action(() {});
}
```

Async boxes emit `AsyncLoading` → `AsyncData` (or `AsyncError`). Handle all states:

```dart
usersBox.output.when(
  loading: () => print('loading...'),
  data: (users) => print('got ${users.length} users'),
  error: (e, st) => print('error: $e'),
);
```

## Persistence

Add `persistKey` to any box — its output is automatically saved and restored:

```dart
class ThemeBox extends NoInputBox<String> {
  String _theme = 'light';

  // This box remembers its value across app restarts
  ThemeBox() : super(persistKey: 'theme');

  @override
  String compute(String? previous) => previous ?? _theme;

  void toggle() => action(() {
    _theme = _theme == 'light' ? 'dark' : 'light';
  });
}
```

Setup at app start:

```dart
// Flutter
BlackboxPersistence.init(SharedPrefsStore(await SharedPreferences.getInstance()));

// Jaspr
BlackboxPersistence.init(LocalStorageStore());

// For complex types, register a codec
BlackboxPersistence.registerCodec<User>(UserJsonCodec());
```

## Lifecycle Hooks

### `prepare(I input, O? previous)`

Called once before the first `compute`. Use it to restore state from persistence:

```dart
class CartBox extends Box<String, List<Item>> {
  List<Item> _items = [];

  CartBox({required String input}) : super(input, persistKey: 'cart');

  @override
  void prepare(String input, List<Item>? previous) {
    _items = previous ?? []; // restore from disk
  }

  @override
  List<Item> compute(String input, List<Item>? previous) => _items;

  void addItem(Item item) => action(() => _items.add(item));
}
```

### `dispose()`

Called when `graph.dispose()` is invoked. Use it to release resources:

```dart
@override
void dispose() {
  _socket.close();
}
```

## Flutter Integration

```dart
import 'package:blackbox_flutter/blackbox_flutter.dart';

// 1. Create boxes and graph
final step = StepBox();
final counter = CounterBox(input: 1);

final graph = Graph.builder()
    .add(step)
    .add(counter, input: (d) => d.whenReady(step))
    .build(start: true);

// 2. Provide boxes to the widget tree
BoxProvider.multi(
  boxes: [step, counter],
  child: MyApp(),
);

// 3. Observe changes — rebuilds automatically
BoxObserver(
  builder: (context) {
    final counter = context.box<CounterBox>();
    return Text('${counter.value}');
  },
);
```

`BoxObserver` tracks which boxes you read during `builder` and rebuilds only when those boxes change. No manual `select`, no `Consumer` — just read and it works.

## Jaspr Integration

Same boxes, same graph — different UI:

```dart
import 'package:blackbox_jaspr/blackbox_jaspr.dart';

// Identical setup — BoxProvider.multi, BoxObserver
// Just swap Flutter widgets for Jaspr components
```

## Real-World Example: Auth Flow

A realistic cascading dependency chain:

```dart
// 1. Load available services from API
class ServicesLoaderBox extends NoInputAsyncBox<List<Service>> {
  final Api _api;
  ServicesLoaderBox(this._api);

  @override
  Future<List<Service>> compute(List<Service>? previous) =>
      _api.fetchServices();
}

// 2. User selects a service (persisted)
class SelectedServiceBox extends Box<List<Service>, Service?> {
  Service? _selected;
  SelectedServiceBox({required List<Service> input})
      : super(input, persistKey: 'selected_service');

  @override
  void prepare(List<Service> input, Service? previous) {
    _selected = previous;
  }

  @override
  Service? compute(List<Service> input, Service? previous) => _selected;

  void select(Service s) => action(() => _selected = s);
}

// 3. Auth depends on selected service (per-service persistence)
class AuthBox extends AsyncBox<Service, Session?> {
  final Api _api;
  Session? _session;
  late Service _service;

  AuthBox(this._api, {required Service input})
      : super(input, persistKey: '_auth_${input.id}');

  @override
  void prepare(Service input, Session? previous) {
    _service = input;
    _session = previous;
  }

  @override
  Future<Session?> compute(Service input, Session? previous) async {
    _service = input;
    return _session;
  }

  Future<void> login() => action(() async {
    _session = await _api.login(_service);
  });

  void logout() => action(() => _session = null);
}

// 4. Profile depends on auth
class ProfileBox extends AsyncBox<Session?, Profile?> {
  final Api _api;
  ProfileBox(this._api, {required Session? input}) : super(input);

  @override
  Future<Profile?> compute(Session? input, Profile? previous) async {
    if (input == null) return null;
    return _api.fetchProfile(input);
  }
}
```

Wire it all together:

```dart
final api = Api();
final services = ServicesLoaderBox(api);
final selected = SelectedServiceBox(input: const []);
final auth = AuthBox(api, input: selectedService);
final profile = ProfileBox(api, input: null);

final graph = Graph.builder()
    .add(services)
    .add(selected, input: (d) => d.whenReady(services))
    .add(auth)
    .add(profile, input: (d) => d.whenReady(auth))
    .build(start: true);
```

### How cascading works

The graph propagates changes automatically through the dependency chain:

```
auth.logout()
  → Auth outputs Session? = null
    → Graph pushes null as input to ProfileBox
      → ProfileBox.compute(null, ...) returns null
        → UI rebuilds with "no profile"
```

No manual reset, no imperative "clear profile" call. The data flows through the graph like water through pipes. Logout in one box → every dependent box recomputes with the new value.

This is the key difference from Riverpod/Bloc where you'd manually dispatch a "reset profile" event or invalidate providers.

### `graph.dispose()` — a different thing

`dispose()` destroys the entire graph and all its boxes (calls `dispose()` on each box). Use it when the whole module is no longer needed — leaving a screen, switching tenant, etc. It's **not** for cascading resets within a living graph.

## Pipeline: One-Shot Execution

For tasks that run once and return a result (data migration, initialization, etc.):

```dart
final config = ConfigLoaderBox();
final validator = ValidatorBox(input: null);

final result = await Pipeline()
    .add(config)
    .add(validator, input: (d) => d.whenReady(config))
    .result(validator)
    .build()
    .run();

// result is the output of validator
```

## Scaling: Multiple Graphs

For large apps, split logic into independent graphs (modules):

```dart
// Each feature owns its graph
final authGraph = AuthGraph.create(api);      // auth, session, profile
final catalogGraph = CatalogGraph.create(api); // categories, products, search
final cartGraph = CartGraph.create(api);       // cart, promo, order

// Provide all boxes to the tree
BoxProvider.multi(
  boxes: [
    authGraph.session,
    authGraph.profile,
    catalogGraph.products,
    cartGraph.cart,
  ],
  child: MyApp(),
);
```

Each graph is self-contained. Disposing one module doesn't affect others.

## Packages

| Package | Description |
|---------|-------------|
| [`blackbox`](packages/blackbox_core) | Core: Box, AsyncBox, Graph, Pipeline, Persistence |
| [`blackbox_flutter`](packages/blackbox_flutter) | Flutter: BoxProvider, BoxObserver, SharedPrefsStore |
| [`blackbox_jaspr`](packages/blackbox_jaspr) | Jaspr: BoxProvider, BoxObserver, LocalStorageStore |
| [`blackbox_support`](packages/blackbox_support) | Shared tracking runtime for observer widgets |

## License

MIT
