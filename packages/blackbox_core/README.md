# blackbox

State management for Dart, Flutter and Jaspr with one law:

```
output = compute(input, state)
```

An app is **boxes** connected by **wires** in a **graph**, plus
**effects** that act on the outside world. A box has one input, private
state and one output. The graph writes inputs, the box's own methods
(**buttons**) write state, `compute` writes the output. Nothing else
changes anything.

No code generation. Boxes are plain Dart classes.

## Install

```yaml
dependencies:
  blackbox: ^0.11.0
  blackbox_flutter: ^0.3.0   # Flutter: BoxObserver, BoxProvider, SharedPreferences
  # blackbox_jaspr: ^0.4.0   # Jaspr (web)
```

## Example

```dart
import 'package:blackbox/blackbox.dart';

final class StepBox extends NoInputBox<int> {
  late final _step = state(1);                    // state: private, remembered
  @override
  int compute() => _step.value;                   // output
  void set(int step) => _step.value = step;       // button
}

final class CounterBox extends Box<int, int> {
  CounterBox.late() : super.late(initialValue: 0); // input comes from the graph
  late final _count = state(0);
  @override
  int compute(int step) => _count.value;
  void increment() => _count.value += input;      // a button may read the input
}

Future<void> main() async {
  final step = StepBox();
  final counter = CounterBox.late();
  final graph = Graph.builder()
      .add(step)
      .add(counter, input: (d) => d.onlyWhenReady(step))   // a wire
      .addEffect<int>((d) => d.onlyWhenReady(counter),     // an effect
          name: 'log', run: (now, was) => print('count: $was → $now'))
      .build();
  await graph.settled();        // count: null → 0

  counter.increment();          // count: 0 → 1
  step.set(5);
  await graph.settled();
  counter.increment();          // count: 1 → 6
  await graph.settled();
  graph.dispose();
}
```

`state(0, persist: 'count')` makes a cell survive restarts. A server
value is a `CachedBox` with `Cache(ttl:, persist:)`. Several outputs from
one device are a `MultiBox`. Time is a `ClockBox`.

## In Flutter

```dart
BoxProvider.multi(boxes: graph.boxes, child: const App());

BoxObserver(builder: (context) {
  final counter = context.box<CounterBox>();
  return TextButton(onPressed: counter.increment, child: Text('${counter.value}'));
});
```

`BoxObserver` rebuilds only when a box it read changes.

## Where code goes

| you need | write |
| --- | --- |
| a value the user chose | a state cell in a box |
| a value from a server | a `CachedBox` |
| a value derived from others | a box whose wire reads them |
| something done to the outside world | a named effect |
| which screen to show | a projection box and a `switch` |

## Documentation

All docs ship inside the package, in `doc/`:

| file | read it for |
| --- | --- |
| [CONCEPTS.md](https://github.com/abuharsky/blackbox/blob/main/packages/blackbox_core/doc/CONCEPTS.md) | the words: box, cell, wire, effect, … — one entry each |
| [SEMANTICS.md](https://github.com/abuharsky/blackbox/blob/main/packages/blackbox_core/doc/SEMANTICS.md) | exact runtime behavior, each rule linked to its test |
| [ARCHITECTURE.md](https://github.com/abuharsky/blackbox/blob/main/packages/blackbox_core/doc/ARCHITECTURE.md) | how an app is laid out; the map file |
| [RECIPES.md](https://github.com/abuharsky/blackbox/blob/main/packages/blackbox_core/doc/RECIPES.md) | task → solution |
| [ANTI-PATTERNS.md](https://github.com/abuharsky/blackbox/blob/main/packages/blackbox_core/doc/ANTI-PATTERNS.md) | symptom → cause → fix |
| [DECISIONS.md](https://github.com/abuharsky/blackbox/blob/main/packages/blackbox_core/doc/DECISIONS.md) | why it is this way |
| [MIGRATION.md](https://github.com/abuharsky/blackbox/blob/main/packages/blackbox_core/doc/MIGRATION.md) | upgrading from older versions |

## Coming from Riverpod or MobX

| Riverpod / MobX | blackbox |
| --- | --- |
| `Provider`, `@computed` | a box's `compute` |
| `StateProvider`, `Notifier`, `@observable` + `@action` | a box with `state(...)` cells and button methods |
| `FutureProvider` | `AsyncBox`; with caching: `CachedBox` + `Cache` |
| `ref.watch(a)` inside a provider | a wire: `input: (d) => d.onlyWhenReady(a)` |
| `ref.watch` in a widget, `Observer` | `BoxObserver` |
| `.family(arg)` | the box's input; per-arg storage: `persistFor:` |
| `ref.listen`, `reaction` | `addEffect` in the graph |
| `ref.onDispose` | `graph.own(release)` |
| `ProviderScope(overrides:)` | `BoxProvider.overrides` |
| a graph discovered at runtime | the graph written in one function, and a generated map |

Port roles, not lines: a user's choice becomes a cell, a fetch becomes a
cached box, a formula becomes `compute`.
