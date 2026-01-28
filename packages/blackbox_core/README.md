# Blackbox

[![Pub Version](https://img.shields.io/pub/v/blackbox.svg)](https://pub.dev/packages/blackbox)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.3-blue.svg)](https://dart.dev)
<!-- Optional CI badge (replace with your repo):
[![CI](https://github.com/<org>/<repo>/actions/workflows/ci.yml/badge.svg)](https://github.com/<org>/<repo>/actions)
-->

Blackbox is a small, explicit reactive computation core built around **Boxes**, a deterministic **Graph** scheduler, and a composable **Flow**.
It is designed for cases where you want *predictable recomputation*, *explicit dependencies*, and *testable business logic* without UI coupling or implicit magic.

> This package is intentionally low-level. It can be used standalone (CLI/backend) or as a foundation for application state management (including Flutter).

---

## Why Blackbox

Use Blackbox when you need:

- **Deterministic recomputation** (a clear dependency model, stable invariants)
- **Explicit dependency wiring** (no implicit context/watch trees)
- **Strict error semantics** (fail-fast by default, opt-in error handling)
- **High testability** (pure boxes, predictable scheduling)
- **Zero UI assumptions** (works equally well in Flutter, server, CLI)

Not a good fit if you want:
- an opinionated UI state manager out of the box,
- implicit reactivity with lots of reflection/magic,
- Redux-style global stores as the primary abstraction.


## How Blackbox compares

Blackbox operates in the same problem space as MobX, Redux, Riverpod, and Bloc,
but focuses on deterministic computation graphs and explicit dependency wiring
instead of implicit UI-driven state propagation.

| Library | Primary model |
|-------|---------------|
| MobX | Implicit observables |
| Redux | Global immutable state |
| Riverpod | Provider dependency graph |
| Bloc | Event → State pipelines |
| **Blackbox** | Deterministic computation graph |

For a detailed comparison, see [docs/COMPARISON.md](docs/COMPARISON.md).

---

## Installation

```bash
dart pub add blackbox
```

---

## Quick start

### 1) A synchronous Box

```dart
final class CounterBox extends Box<int> {
  int _value = 0;

  void inc() => signal(() => _value++);

  @override
  int compute() => _value;
}

final counter = CounterBox();

final cancel = counter.listen((o) {
  print("counter=${o.value}");
});

counter.inc(); // prints: counter=1
counter.inc(); // prints: counter=2
cancel();
```

### 2) A Graph with dependencies

```dart
final g = Graph();

final a = CounterBox();
final b = AddOneBox(); // BoxWithInput<int,int>

g.add(a);

g.addWithDependencies(
  b,
  dependencies: (d) => d.of(a), // <- explicit dependency
);

b.listen((o) => print("b=${o.value}"));
a.inc(); // b recomputes accordingly
```

### 3) A Flow that aggregates sources

```dart
final flow = FlowBuilder<String>()
  .on<int>(a, (v) => "a=$v")
  .build(initial: "init");

final cancel = flow.listen(print); // prints: "a=0" (sync overrides initial)
cancel();
```

---

## Concepts

### Output

Every box exposes an **Output** (sync or async). Output is a state container: ready / loading / error.

- `SyncOutput<T>`: always ready
- `AsyncLoading<T>`: not ready
- `AsyncData<T>`: ready
- `AsyncError<T>`: not ready (error state)

> `Output.value` is only valid when `Output.isReady == true`. Otherwise `StateError` is thrown (fail-fast by design).

### Box

A **Box** is a unit of computation that produces a value (`O`).

- `Box<O>`: synchronous box
- `AsyncBox<O>`: asynchronous box
- `BoxWithInput<I,O>` / `AsyncBoxWithInput<I,O>`: boxes that depend on an input value

Boxes are intentionally small and testable. Treat `compute()` as your pure(ish) business function.

### Graph

A **Graph** wires boxes together. It owns scheduling and recomputation order.

- `g.add(sourceBox)` registers a dependency source (no input)
- `g.addWithDependencies(dependentBox, dependencies: ...)` registers an input box and defines how to build its input

**Invariants (important):**
- Dependencies used via `DependencyResolver.of(x)` must be registered in the graph (added earlier).
- If a dependency is not ready, `DependencyResolver.of` throws `StateError` by default.
- You may swallow errors via `onError`, otherwise errors are fatal (re-thrown immediately).

### Flow

A **Flow<T>** represents aggregated reactive state. It subscribes to sources and emits mapped values.

- `initial` is a **fallback**, not a guaranteed “first emission”.
- If a sync source already has a value, it overrides `initial` immediately (no “init flicker”).

---

## Error handling

By default, Graph is **fail-fast**: if a dependency is missing or not ready, it throws.

To explicitly handle transient dependency states (e.g. async loading), provide `onError`:

```dart
g.addWithDependencies(
  dep,
  dependencies: (d) => d.of(asyncBox),
  onError: (e) => e is StateError, // swallow "not ready"
);
```

This makes the node resilient to temporary failures and allows recomputation later when dependencies become ready.

---

## Pub.dev readiness checklist

This repository layout usually scores well on pub.dev (pana) when you include:

- `README.md` (this file) with usage examples and concept explanation ✅
- `CHANGELOG.md` mentioning the current version ✅
- `LICENSE` file ✅
- `repository:` (or `homepage:`) field in `pubspec.yaml` ✅
- `dart analyze` clean (no warnings) ✅
- good `environment:` SDK constraints ✅

See `doc/` for detailed Russian documentation and internals.

---

## Documentation

- **Russian docs overview:** `doc/README_RU.md`
- API:
  - `doc/box_ru.md`
  - `doc/graph_ru.md`
  - `doc/flow_ru.md`
- Internals (design notes): `doc/internals_ru.md`
- Testing guidance: `doc/testing_ru.md`
- FAQ: `doc/faq_ru.md`

---

## License

MIT. See `LICENSE`.
