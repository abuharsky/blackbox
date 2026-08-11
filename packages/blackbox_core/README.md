# blackbox

State management you can hold in your head. One law:

```
output = compute(input, state)
```

A **box** has one input, one output, and private memory. Three writers,
never overlapping: the **graph** writes inputs, your **buttons** write
memory, **compute** writes the output. The whole app is boxes and wires,
drawn in one place. That's the entire model — everything below is it,
applied.

No code generation. No build_runner. No `BuildContext` in your logic.
Every word is plain Dart you can cmd-click into.

## A box in 30 seconds

```dart
final class CounterBox extends Box<int, int> {
  CounterBox.late() : super.late(initialValue: 0); // input arrives from the graph

  late final _count = state(0);                    // MEMORY — invisible outside

  @override
  int compute(int step) => _count.value;           // OUTPUT — the only writer

  void increment() => _count.value += input;       // BUTTON — writes memory
}
```

Want the count to survive a restart? Change one line:

```dart
late final _count = state(0, persist: 'counter'); // disk is not your problem
```

Per-user slots, with no cross-user leaks by construction:

```dart
late final _cart = state(<Item>[], persistFor: (userId) => 'cart:$userId');
```

## Async: `fetch` means "go get a fresh one"

*When* it runs is not your concern — the cache decides (first boot, TTL
expiry, `refresh()`, an input change):

```dart
final class MenuBox extends NoInputCachedBox<Menu> {
  @override
  Cache<void, Menu> get cache =>
      const Cache(ttl: Duration(minutes: 5), persist: 'menu');

  @override
  Future<Menu> fetch() => api.fetchMenu();
}
```

Cold start is instant from disk; a stale value shows while a background
re-fetch runs. UI consumes a typed `AsyncOutput`: loading / data / error,
with the previous data still attached.

## Many outputs: MultiBox (a real player)

Status, position and track change at different rhythms — so they are
separate observable cells, and a progress bar ticking 5×/second never
rebuilds the track title:

```dart
final class PlayerBox extends MultiBox<String?> {      // input: one stream URL
  PlayerBox({required this.gateway});
  final PlayerGateway gateway;

  late final status = child(PlayerStatus.paused);      // OUTPUTS
  late final position = child(Duration.zero);
  late final track = child<TrackInfo?>(null);

  @override
  void compute(String? url) {                          // input changed:
    dispatch(track, null);                             //   old track isn't from this stream
    connect(gateway.onStatus, status);                 //   wire the streams
    connect(gateway.onPosition, position);             //   (auto-released on next input)
    gateway.setSource(url);
  }

  void toggle() => gateway.toggle();                   // BUTTON
}
```

Nobody outside can write a cell: `child` has no public setter, `dispatch`
asserts ownership, and `state` cells are `_private` — the compiler guards
the law, not your discipline.

## The graph is the app, on one screen

A wire *is* a dependency. Downstream simply doesn't run until upstream
has output — loading states never leak into your wiring:

```dart
Graph<AppContext> buildApp(AppContext ctx) {
  final config  = ConfigBox(ctx.api);
  final billing = BillingBox(ctx.store);          // self-driven: no input needed
  final player  = PlayerBox(gateway: ctx.gateway);
  final phase   = AppPhaseBox.late();             // "what to show" as a pure formula

  return Graph.builder<AppContext>(context: ctx)
      .add(config)
      .addMultiBox(billing)
      .addMultiBox(player, input: (d) {
        final station = d.whenReady(config).selectedStation;
        final premium = d.whenReady(billing.isPremium);
        // Policy lives in the wire: a free user never streams premium —
        // by construction, not by discipline.
        return station.streamUrlFor(premium: premium);
      })
      .add(phase, input: (d) => (
        config: d.whenReady(config),
        premium: d.whenReady(billing.isPremium),
      ))
      .build(start: true);
}
```

The graph owns lifecycles end to end:

```dart
final app = buildApp(ctx)
  ..own(httpClient.close);   // created for the graph → dies with the graph

app.dispose();               // boxes, subscriptions, clients — everything
```

And it can *show you the app*:

```dart
await app.settled();         // test-friendly: wait until propagation is done
print(app.toMermaid());      // the dependency map as a rendered diagram
```

A dependency cycle doesn't freeze your app — the graph detects the storm,
stops, and throws a diagnostic naming the trigger.

## Who writes what (the entire framework, honestly)

| thing            | written by                | read by                |
| ---------------- | ------------------------- | ---------------------- |
| input            | the graph                 | `compute`              |
| memory `state()` | the box's buttons         | `compute`              |
| output           | `compute` only            | UI, graph, effects     |
| module `child()` | its multibox (`dispatch`) | UI, graph, effects     |

Violations fail to compile or assert loudly in debug. Eight public words:
`state`, `compute`, `fetch`, `child`, `dispatch`, `connect`, `own`,
`.late`. There is no second way to spell anything.

## Runs anywhere — including headless

The same graph runs in a background isolate (Android audio service, CLI,
server): build it, skip the UI. Behavior differences are data, not code
paths:

```dart
final graph = createApp(...);
graph.box<ForegroundBox>().set(false);   // no screen → skip artwork decoding
```

## Bindings

| package | what |
| --- | --- |
| [blackbox_flutter](https://pub.dev/packages/blackbox_flutter) | `BoxObserver` (MobX-style read tracking), `BoxProvider`, `SharedPreferences` persistence |
| [blackbox_jaspr](https://pub.dev/packages/blackbox_jaspr) | the same for [Jaspr](https://pub.dev/packages/jaspr) web apps, `localStorage` persistence |

Boxes themselves are pure Dart — the logic ports across frameworks (and
away from blackbox: a cell maps 1:1 onto any store).

## Coming from Riverpod

Ask one question per provider: **is this a truth, a fetch, or a formula?**
Truths become cells, fetches become cached boxes, formulas become
`compute`.

| Riverpod | blackbox |
| --- | --- |
| `Provider` (derived value) | a box's `compute` — derivation is the law itself |
| `StateProvider` / `Notifier` | a box with `state(...)` cells and button methods |
| `FutureProvider` | `AsyncBox` / `NoInputAsyncBox` |
| `FutureProvider` + caching hacks | `CachedBox` + `Cache(ttl:, persist:)` |
| `ref.watch(a)` inside a provider | a **wire**: `input: (d) => d.whenReady(a)` in the graph |
| `ref.watch` in a widget | `BoxObserver` + reading the box (tracked automatically) |
| `ref.read(x.notifier).foo()` | `context.box<X>().foo()` — buttons are plain methods |
| `.family(arg)` | the box **input**; per-arg storage via `persistFor: (arg) => ...` |
| `.select(...)` | unnecessary — MultiBox cells are separate observables by design |
| `ref.listen` (side effects) | `addEffect` in the graph — all effects in one list |
| `ref.onDispose` | `graph.own(release)` |
| `ProviderScope(overrides:)` | `BoxProvider.overrides` |
| provider graph (implicit, discovered at runtime) | the graph is **explicit**: one function, renderable via `toMermaid()` |

The big difference is topological: Riverpod's dependency graph emerges
from scattered `ref.watch` calls; here the graph is written down in one
place and *is* the application.

## Coming from MobX

| MobX | blackbox |
| --- | --- |
| `Store` class | a box |
| `@observable` field | ask: user's truth → `state(...)` cell; fetched data → `CachedBox` |
| `@computed` | `compute` — the only writer of output |
| `@action` | a button method; multi-write batching via `action(() {...})` |
| `reaction` / `autorun` | graph `addEffect` (app-level) or `BoxObserver` (UI) |
| `ObservableList` mutated in place | immutable list replaced wholesale — distinct guards work, races don't |
| codegen + `*.g.dart` | none — `state(0)` is executable Dart, cmd-click goes to real code |
| hand-rolled `isLoading` / disk cache in a store | `AsyncOutput` already carries loading/error with previous data; `Cache(persist:)` is the disk |

A faithful 1:1 port of a MobX store usually re-implements the library
around the library (a `load()` with an in-flight flag *is* a hand-rolled
`CachedBox`). Port the *roles*, not the lines: truth → cells, fetch →
`Cache`, view state → its own tiny box.

## Learn more

The full docs ship **inside this package** (`doc/` in the pub archive) —
readable offline, greppable by tooling:

- [MODEL.md](https://github.com/abuharsky/blackbox/blob/main/packages/blackbox_core/doc/MODEL.md) — the law, in full: three things, one formula, one writer per thing.
- [ARCHITECTURE.md](https://github.com/abuharsky/blackbox/blob/main/packages/blackbox_core/doc/ARCHITECTURE.md) — how to build a whole app: seven floors, distilled from a production radio app (native player, billing, alarms, background isolate).
- [MIGRATION.md](https://github.com/abuharsky/blackbox/blob/main/packages/blackbox_core/doc/MIGRATION.md) — coming from 0.8/0.9: a script does the mechanical part.

Built and battle-tested on production apps first; every API here earned
its place by deleting code in a real codebase.
