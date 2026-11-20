# Concepts

The words of Blackbox, one entry each: a definition, the rules, a minimal
example. Exact runtime behavior is in [SEMANTICS.md](SEMANTICS.md); the
reasons are in [DECISIONS.md](DECISIONS.md).

## The law

```
output = compute(input, state)
```

A box's output changes only when its input or its state changes. Each of
the three has exactly one writer:

| thing | written by | read by |
| --- | --- | --- |
| input | the graph (its wire) | the box |
| state | the box's own methods (buttons) | the box |
| output | `compute` | everyone outside |

Inside a box anything goes: native calls, handles, I/O. Outside, the box
promises one thing: its output follows its input and state.

## Box

A class with one input, one output and private state; the output is
`compute(input)`.

- **Must:** keep state in `state(...)` cells, private (`_name`).
- **Must:** compute the output from `input` and cells only.
- **Must not:** read other boxes, the clock or globals in `compute` (see
  [ANTI-PATTERNS.md](ANTI-PATTERNS.md)).

| class | input | compute returns |
| --- | --- | --- |
| `Box<I, O>` | `I` | `O` |
| `NoInputBox<O>` | none | `O` |
| `AsyncBox<I, O>` / `NoInputAsyncBox<O>` | `I` / none | `Future<O>` |
| `CachedBox<I, O>` / `NoInputCachedBox<O>` | `I` / none | `fetch` instead of `compute` |
| `CachedValueBox<I, O>` | `I` | `fetch`; always has a sync value |
| `MultiBox<I>` | `I` | nothing: writes several cells |

```dart
final class FullPriceBox extends Box<Order, int> {
  FullPriceBox.late() : super.late();
  @override
  int compute(Order order) => order.sum + order.delivery;
}
```

**`.late()`** constructs a box whose input will come from the graph.
`initialValue:` makes it ready before that; see
[SEMANTICS § 3](SEMANTICS.md#3-readiness).

## Input

The value a box is given. Only the graph writes it.

- **Must:** be a value with `==` (records, ids, value classes), so an
  unchanged input does not recompute.
- **May:** be read by buttons as `input` (the current one).
- **Must not:** be a live object (a box, a stream, a mutable list that
  changes in place).

## State cell

What a box remembers: `late final _x = state(initial)`.

- **Must:** be written only by the box's buttons, never in `compute`.
- Writing an equal value does nothing.
- `persist: 'key'` saves it on every write and restores it on creation.
  `persistFor: (input) => 'key:$id'` keeps one slot per input.

```dart
late final _theme = state(ThemeMode.system, persist: 'theme');
```

## Button

A public method of a box that writes its cells (or commands a device the
box owns).

- **May:** read `input` and `value`.
- **Must not:** be called from another box's `compute`; call it from UI,
  an effect, or app code.
- Several writes in one gesture: wrap them in `action(() { ... })` to
  publish once.

```dart
void toggle() => _theme.value =
    _theme.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
```

## Output

What a box shows: `box.output` (`SyncData` / `AsyncLoading` / `AsyncData`
/ `AsyncError`), `box.value` for a sync box.

- An output equal to the current one is not published. For a type
  without content `==`, override `sameOutput`.
- Plain code reads it with `valueOrNull`, `requireValue` or
  `await firstReady`.

## Graph

The list of boxes, their wires and effects:
`Graph.builder().add(...).addEffect(...).build()`.

- **Must:** be built in one function you can read top to bottom.
- A box is declared (`add` / `addMultiBox`) by one graph; any graph may
  read it.
- `graph.dispose()` disposes the boxes it declared and everything it
  `own`s.

```dart
final graph = Graph.builder()
    .add(step)
    .add(counter, input: (d) => d.onlyWhenReady(step))
    .build();
```

## Wire

The `input:` function of a node: reads sources, returns the input. Its
type is `Wire<I>`.

- **Must:** be a pure function of what it reads.
- **Must not:** decide anything (`if`, computations). A rule is a box.
- A wire reading several sources is best declared by its box, as a
  static `wire(...)` returning a `Wire`; the graph passes the sources
  ([recipe](RECIPES.md#a-box-declares-how-it-reads-its-input)).
- Three words read a source; they differ only in what happens when the
  source is not ready:

| word | not ready |
| --- | --- |
| `d.onlyWhenReady(x)` | the node does not run this time |
| `d.whenReadyOrNull(x)` | gives `null`, the node runs |
| `d.outputOf(x)` | gives the `Output` (loading / error / data), the node runs |

```dart
.add(phase, input: (d) => (
  config: d.onlyWhenReady(config),
  premium: d.onlyWhenReady(billing.isPremium),
))
```

## Effect

A graph node that does something to the outside world when its input
changes: `addEffect(input, name:, run: (current, previous) { ... })`.

- **Must:** have a `name` — the subsystem it is the only writer of
  (`'equalizer'`).
- **May:** press buttons of boxes and call services.
- **Must not:** return a value; nothing reads an effect.
- A body longer than a line lives in a class with `input` and `apply`
  ([recipe](RECIPES.md#an-effect-in-its-own-class)).

```dart
.addEffect<EqState>((d) => d.onlyWhenReady(equalizer),
    name: 'equalizer',
    run: (now, was) => gateway.setBands(now.bands))
```

## MultiBox

One node with one input and several output cells: `child(initial)`.

- **Must:** write its cells only itself: `dispatch(cell, value)` or
  `connect(stream, cell)`.
- `connect` subscriptions end on the next input and on dispose.
- Cells are ready from birth and ignore equal values (unless
  `distinct: false`).
- Readers wire to a cell directly: `d.onlyWhenReady(player.status)`.

```dart
final class PlayerBox extends MultiBox<String?> {
  late final status = child(PlayerStatus.paused, name: 'status');
  @override
  void compute(String? url) {
    connect(gateway.onStatus, status);
    gateway.setSource(url);
  }
}
```

## Cache and fetch

A box whose value is fetched and kept for a while:
`CachedBox` + `Cache(ttl:, persist:/persistFor:)` + `fetch`.

- `fetch` gets a fresh value; the cache decides when it runs (first boot,
  TTL, `refresh()`, a new input).
- Cache is for values you can fetch again. Values you would lose
  (user choices) are state cells with `persist`.

```dart
final class MenuBox extends NoInputCachedBox<Menu> {
  @override
  Cache<void, Menu> get cache =>
      const Cache(ttl: Duration(minutes: 5), persist: 'menu');
  @override
  Future<Menu> fetch() => api.menu();
}
```

## Persistence

Saving state cells and caches to a key-value store.

- Set up once at startup: `BlackboxPersistence.init(store, codecs: [...])`,
  or `SharedPrefsStore.preload()` / `LocalStorageStore.preload()`.
- Primitives need no codec; other types register a `PersistentCodec<T>`
  or pass `codec:`.
- Output is never persisted: it is recomputed.

## ClockBox

The one source of time as a value; a multibox whose cells are moments.

- `clock.at(moment)` — a `bool` cell, `true` from the moment on.
- `clock.every(period)` — a `DateTime` cell that ticks.
- Cells nobody listens to are dropped and their timers stopped.

```dart
.add(timer, input: (d) => d.onlyWhenReady(clock.at(fireDate)))
```

## DebounceBox and HysteresisBox

Boxes that delay their input.

- `DebounceBox<T>(window)` — shows the input once it has stopped changing
  for `window`.
- `HysteresisBox(on:, off:)` — a `bool` that turns on after `on` and off
  after `off` of steady input.

## Pipeline

A graph run once for one result:
`Pipeline.builder().add(...).build(result: step).start()`.

- `start()` completes with the result step's first value; the pipeline
  then disposes itself.
- The result step must not be ready before the run.
- `retry:` and `onFailure:` per step; `timeout:` per pipeline.

## own

`graph.own(release)` — a resource created for the graph, released when
the graph is disposed (HTTP clients, databases).

## The map

A Markdown file describing all graphs, generated by
`graphMap({...})` from `package:blackbox/map.dart` and kept current by a
test. See [ARCHITECTURE.md § The map](ARCHITECTURE.md#the-map).
