# Architecture

How an application is laid out with Blackbox: where each piece of code
goes. Words are defined in [CONCEPTS.md](CONCEPTS.md); task-sized
solutions are in [RECIPES.md](RECIPES.md).

## Where code goes

A new feature is one of three things: **a node** (a box and its wires),
**an effect**, or **a branch in a projection**. If a change fits none of
them, re-read the map before writing it.

| you need | put it in |
| --- | --- |
| a value the user chose | a state cell in a box (`persist:` if it must survive restarts) |
| a value from a server | a `CachedBox` (or `CachedValueBox` if it must always be readable) |
| a value derived from others | a box whose wire reads them |
| several values from one device at different rhythms | a `MultiBox` with one cell each |
| something done to the outside world | a named effect |
| which screen to show | a projection box (a phase enum) and a branch in its `compute` |
| time as a value | `ClockBox`; a delay: `DebounceBox` / `HysteresisBox` |
| a client, a connection, a database | `graph.own(release)` |
| a native SDK | a pure-Dart interface (port) used by a box, implemented by an adapter |

## The layers

| layer | what it is | rule |
| --- | --- | --- |
| composition root | a function that creates the graphs and shared boxes | real vs fake decided here, nowhere else |
| graphs | one per module, one file each | a graph declares the boxes it drives |
| shared boxes | boxes two modules need | created at the root, driven by one graph, read by any |
| boxes | one value each | state in cells, output from `compute` |
| effects | the list of what the app does to the world | one effect per subsystem it writes |
| projection | a box that turns the graph into "what to show" | product rules live in its `switch` |
| UI | widgets reading boxes | reads and calls buttons; holds no logic |

## Composition root

A function returns the graphs. Everything created for them is `own`ed by
them; everything passed in is owned by the caller.

```dart
App createApp({required PlayerGateway gateway, required Uri api}) {
  final http = ApiClient(api);
  final premium = PremiumBox.late(initialValue: Premium.closed); // shared
  final selection = SelectionBox();                              // shared

  final purchases = buildPurchases(premium: premium)..own(http.close);
  final player = buildPlayer(gateway, selection: selection, premium: premium);
  final catalog = buildCatalog(http, selection: selection, premium: premium);
  return App(purchases, player, catalog);
}
```

`App.dispose()` disposes the graphs; the caller disposes `gateway`.

## Modules and several graphs

- **A module is a file with one function that builds one graph.**
  Several graphs in an app are normal.
- **A box is declared by one graph** (`add` / `addMultiBox`): that graph
  drives its input and disposes it. A second live declaration throws.
- **Any graph may read any box** through a wire. Reading subscribes; it
  does not own.
- **A value two modules need is a shared box**, created at the root
  and passed to both. The module that drives it takes it as a *required*
  parameter, never `premium ?? PremiumBox.late()`.
- **An intent that spans modules** (select a station, then play it)
  lives at the root or in a facade, not inside one module.
- **The owner outlives its readers.** Dispose readers first; a wire into
  a disposed box sees its last value forever (debug builds warn).
- **No graph inside a box**, and a `MultiBox` is not a container for
  boxes.

| reader | how it reads a box |
| --- | --- |
| another graph | a wire: `d.onlyWhenReady(box)` |
| UI, a bridge to another system | `listen` / `BoxObserver` |
| another isolate | the persisted slot on disk |

## A module

The graph function is a table: **one line per node**, saying only what
plugs into what.

```dart
Graph<void> buildPlayer(PlayerGateway gateway,
    {required SelectionBox selection, required PremiumBox premium}) {
  final stream = StreamUrlBox.late();
  final player = PlayerBox(gateway: gateway);
  final nowPlaying = NowPlayingBox.late();
  final session = MediaSessionEffect(gateway);
  return Graph.builder()
      .add(stream, input: StreamUrlBox.wire(station: selection, premium: premium))
      .addMultiBox(player, input: (d) => d.onlyWhenReady(stream))
      .add(nowPlaying, input: NowPlayingBox.wire(station: selection, status: player.status))
      .addEffect(session.input(nowPlaying), name: 'media session', run: session.apply)
      .build();
}
```

- **A rule is a box.** "A free user never gets a premium URL" is
  `StreamUrlBox.compute`: a tested function and a node on the map, so
  the player cannot play what the rule forbids.
- **A box declares how it reads its input** (`StreamUrlBox.wire`, a
  `Wire` next to its input type); the graph passes the sources by name.
  A wire with one source stays inline.
- **An effect body is a class** (`MediaSessionEffect.apply`).

See [RECIPES: One line per node](RECIPES.md#one-line-per-node).

## Projection and UI

One box turns the graph into the phase to show; the router is a switch
over it.

```dart
final class AppPhaseBox extends Box<AppPhaseInput, AppPhase> {
  AppPhaseBox.late() : super.late(initialValue: const Loading());
  @override
  AppPhase compute(AppPhaseInput i) => switch (i.config) {
        AsyncData(:final value) => i.onboarded ? Home(value) : Onboarding(),
        AsyncError(:final error) => Failed('$error'),
        _ => const Loading(),
      };
}
```

```dart
BoxProvider.multi(
  boxes: [for (final g in app.graphs) ...g.boxes],
  child: BoxObserver(builder: (context) =>
      switch (context.box<AppPhaseBox>().value) {
        Loading() => const Splash(),
        Onboarding() => const OnboardingScreen(),
        Home(:final config) => HomeScreen(config),
        Failed(:final message) => ErrorScreen(message),
      }),
);
```

## Resources

| lives for | how |
| --- | --- |
| one input of a multibox | `connect(stream, cell)` |
| the box | a field, released at the top of `compute` and in `dispose` |
| the graph | `graph.own(release)` |

## Headless

The same `createApp` runs without UI (a background isolate, a CLI, a
test). A behavior that differs without a screen is an input, not a
second code path: a `ForegroundBox` set to `false`.

## The map

`graphMap` (`package:blackbox/map.dart`) renders all graphs as one
Markdown file: an overview, a picture of how the graphs connect, and for
every box the graph that drives it, the file it is wired in, its wires,
its readers, the effects that press it (`⇒`) and the boxes it touches
inside `compute` (`⚠`). Commit it as `doc/MAP.md` and keep it current
with a test:

```dart
test('doc/MAP.md is current', () async {
  final app = await startHeadless(fakes); // your composition, no UI
  app.selection.select(station);          // drive the scenarios whose
  await app.settled();                    // wires belong on the map
  final map = graphMap({'player': app.player, 'catalog': app.catalog});
  final file = File('doc/MAP.md');
  if (Platform.environment['UPDATE_MAP'] == '1') file.writeAsStringSync(map);
  expect(map, file.readAsStringSync(),
      reason: 'Wires changed. Regenerate: UPDATE_MAP=1 dart test test/map_test.dart');
});
```

Every PR that changes a wire shows it in the diff.

## For agents

Paste into the project's agent instructions (`CLAUDE.md`, `AGENTS.md`):

```markdown
## Blackbox
- Read `doc/MAP.md` first. A link between boxes that is not on it is not
  a wire — a command, a `listen` or a closure — and is the first suspect.
- A graph function is one line per node: what plugs into what. A rule
  (`if`, a computation) goes into a box; an effect body into a class with
  `input` and `apply`; a wire reading several sources is a static `wire`
  on the box (see blackbox doc/RECIPES.md "Writing the graph").
- Name every effect and multibox cell.
- After changing wires, regenerate the map: `UPDATE_MAP=1 dart test test/map_test.dart`.
```

The links the map shows besides wires (`⇒`, `⚠`, "wired in") are
recorded in debug builds only.

## Debugging

| question | tool |
| --- | --- |
| what ran in each pump, and why | `build(trace: true)` |
| how the app is wired | `doc/MAP.md`, `graph.toMermaid()` for one graph |
| a box reading another box behind the graph | the `touched … inside its compute` console warning; `⚠` on the map |
| a widget that does not rebuild | the `BoxReadCheck` warning (Flutter / Jaspr) |
| which node failed | `GraphNodeError` in the zone: node, stage, error |
