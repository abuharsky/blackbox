# Blackbox Architecture

**Status: field-proven pattern catalog.** MODEL.md states the law
(`output = compute(input, state)`, one writer per thing). This document
states how to build an application out of it. Every pattern here is a
distilled slice of a real production app (an internet-radio player:
config, billing, onboarding, a native player, alarms, an equalizer) —
none of it is invented for the docs.

An application is **seven floors**, read top-down. Each floor is one
idea. A new feature is always one of three things: another node,
another effect, or another branch in the projection. There is no
fourth place for code to go — that is the point.

---

## Floor 1 — Runtime: one create/dispose pair

The composition root is a **function returning a `Graph`**, not a
class. Everything created *for* the graph is owned *by* the graph via
`own(...)`; everything injected from outside stays owned by the caller.

```dart
Graph<AppContext> createApp({
  required String appId,
  required Uri configEndpoint,
  required PlayerGateway playerGateway,   // caller owns, caller disposes
  Uri? metadataEndpoint,
}) {
  final config = ConfigApiClient(endpoint: configEndpoint);
  final metadata =
      metadataEndpoint == null ? null : MetadataApiClient(endpoint: metadataEndpoint);

  return buildApp(AppContext(
    appId: appId,
    configRepository: ConfigRepository(client: config),
    playerGateway: playerGateway,
    trackRepository: metadata == null
        ? MockTrackRepository()
        : MetadataRepository(client: metadata),
  ))
    ..own(config.close)
    ..own(() => metadata?.close());
}
```

The runtime holds exactly one pair:

```dart
_graph = createApp(...);
// ...
_graph.dispose();          // boxes, subscriptions, HTTP clients — everything
_playerGateway.dispose();  // the runtime created it, the runtime closes it
```

Real-vs-mock decisions (is there a metadata endpoint? is billing
wired?) live here and nowhere else, as plain `?:` expressions.

## Floor 2 — Skeleton: nodes and wires

`buildApp` is the whole application on one screen: declare the nodes,
draw the wires. A wire **is** a dependency; sequencing is not a step
manager, it is the fact that a downstream box does not run until the
upstream has output.

```dart
Graph<AppContext> buildApp(AppContext ctx) {
  final config     = ConfigBox(ctx.configRepository);   // trunk
  final onboarding = OnboardingBox(appId: ctx.appId);
  final billing    = BillingBox(gateway: ctx.purchaseGateway); // self-driven
  final player     = PlayerBox(gateway: ctx.playerGateway);    // stands apart
  final features   = FeaturesBox(player: player, ...);         // module (floor 3)
  final phase      = AppPhaseBox.late();                       // projection (floor 6)

  return Graph.builder<AppContext>(context: ctx)
      .add(config)
      .add(onboarding, input: (d) => configOrNull(d))
      .addMultiBox(billing)                        // no input: self-driven
      .addMultiBox(features, input: (d) => (
        config:  configOrNull(d),
        premium: d.whenReady(billing.isPremium),
      ))
      .addMultiBox(player, input: (d) {
        final station = d.whenReady(features.selectedStation);
        if (station == null) return null;
        final premium = d.whenReady(billing.isPremium);
        // Policy lives in the wire: a free listener never streams a
        // premium channel — by construction, not by discipline.
        if (!premium && !station.isAvailableInFree) return null;
        return station.streamUrlFor(premium: premium);
      })
      .add(phase, input: (d) => (
        configState: configState(d),
        onboarding:  d.whenReady(onboarding),
        isPremium:   d.whenReady(billing.isPremium),
      ))
      // ... effects (floor 5)
      .build(start: true);
}
```

Notes that matter:

- **Data flows; nothing is recreated.** `premium` is a value on a
  wire. A purchase flips it and the graph re-pumps — no box is torn
  down or rebuilt.
- **Projections are your functions.** `configOrNull` / `configState`
  ("last good config survives a refresh") are one-line helpers over
  the resolver, declared once in app code. The library deliberately
  has no `latestData` — a value that is always present hides whether
  it is stale, and downstream code stops handling errors.
- **A box whose input arrives from the graph is constructed with
  `.late()`** — no dummy inputs, no seeding order.
- **A self-driven module** (lives off its own streams, needs nothing
  from the graph) is added without `input:` — compute runs once to
  start it.

## Floor 3 — Module: a black box with its own graph inside

When one concern grows past a handful of boxes, fold it into a
`MultiBox`: outside it is a single node with one input; inside it has
its own `Graph` wiring private boxes. Module input enters through
**port cells**; `compute` is a patch panel.

```dart
final class FeaturesBox extends MultiBox<({AppConfig? config, bool premium})> {
  // Ports: compute writes them, the inner graph reads them.
  late final _config  = child<AppConfig?>(null);
  late final _premium = child(false);

  FeaturesBox({required PlayerBox player, ...}) : _player = player {
    _inner = Graph.builder<void>()
        .add(_selectedStationId, input: (d) => (config: d.whenReady(_config), ...))
        .add(_selectedStation,   input: (d) => (stationId: d.whenReady(_selectedStationId), ...))
        .add(_nowPlaying, input: (d) => (
          station:     d.whenReady(_selectedStation),
          playerState: d.whenReady(_player.state),
          premium:     d.whenReady(_premium),
        ))
        .build(start: true);
  }

  @override
  void compute(input) {                    // external input → internal ports
    dispatch(_config, input.config);
    dispatch(_premium, input.premium);
  }

  // Outputs: expose internal boxes as they are, plus intents.
  NowPlayingBox get nowPlaying => _nowPlaying;
  void activate(String stationId) => _selectedStationId.activate(stationId, _player);

  @override
  void dispose() { _inner.dispose(); super.dispose(); }
}
```

Rules of the module pattern:

- A module is a **replaceable unit**; cross-module wires belong on the
  top map, not inside. (Reading a neighbour like `_player.state`
  directly works — `whenReady` lazily registers any source — but that
  wire will not appear on the top-level `toMermaid()` map. Do it
  knowingly, and document it, or lift the value into the module input.)
- Ports always have values (`child` requires an initial), so internal
  boxes receive `(null, false)` immediately. Waiting inside a module is
  null-propagation, not not-ready — internal boxes must accept it.
- An intent that coordinates two internal boxes (select + arm
  autoplay) is a method **on the module** — it finally has a home.
- Two floors are enough. Do not nest modules until a real app forces
  you to.

## Floor 4 — Leaf: an ordinary box, one thing

```dart
final class SelectedStationIdBox extends Box<SelectedStationIdInput, String?> {
  SelectedStationIdBox.late({required String appId}) : ..., super.late();

  late final _selected = state<String?>(null, persist: _key); // disk handled

  @override
  String? compute(input) { /* validate selection against config */ }

  void select(String stationId) => _selected.value = stationId;

  /// Intent "listen to this station": drop data into the graph, sound
  /// follows through the wires (station → streamUrl → player).
  void activate(String stationId, PlayerBox player, {bool autoPlay = true}) {
    if (value == stationId) { if (autoPlay) player.playCurrent(); return; }
    if (autoPlay) player.armAutoPlayOnNextSourceChange();
    select(stationId);
  }
}
```

The leaf is where the law is visible verbatim: memory in `state(...)`
(persistence declared in place), buttons write memory, `compute`
derives the output. Nothing else.

## Floor 5 — Effects: everything the app does to the world, in one list

Each effect reads a slice of the graph and is the **sole writer of one
external subsystem**. The input is a record; `run` diffs `current`
against `previous`. The whole list answers "what does this app
actually *do*?" on one screen.

```dart
// Actuator: the only writer of the native equalizer.
.addEffect<EqualizerState>(
  (d) => d.whenReady(equalizer),
  run: (current, previous) {
    if (current.enabled != previous?.enabled) {
      unawaited(ctx.playerGateway.setEqEnabled(current.enabled));
    }
    if (!listEquals(current.bands, previous?.bands)) {
      unawaited(ctx.playerGateway.setEqBandValues(current.bands));
    }
  },
)

// Telemetry: the funnel is a projection of the graph — zero calls in UI.
.addEffect<OnboardingFlowState>(
  (d) => d.whenReady(onboarding),
  run: (current, previous) => ctx.analytics.onOnboarding(current),
)
```

Safety-first actuators (an alarm that must ring even if the stream
fails) put the guarantee in the effect: start the stream on fire,
silence the fallback sound only after the graph reports `playing`.

## Floor 6 — Projection "what to show": a pure formula

One box turns the graph's state into a phase enum. Product rules
("premium skips the funnel") live here, in one `switch`.

```dart
final class AppPhaseBox extends Box<AppPhaseInput, AppPhase> {
  AppPhaseBox.late() : super.late(initialValue: const AppLoadingPhase());

  @override
  AppPhase compute(input) => switch (input.configState) {
    AppConfigLoading()            => const AppLoadingPhase(),
    AppConfigError(:final error)  => AppErrorPhase(error.toString()),
    AppConfigReady(:final config) => _resolve(config, input.onboarding, input.isPremium),
  };
}
```

## Floor 7 — UI: a projection of the skeleton, off to the side

The entire router is a switch over the phase box; screens read boxes
and draw values. `graph.boxes` feeds the provider — no hand-maintained
export list.

```dart
return BoxProvider.multi(
  boxes: graph.boxes,
  child: BoxObserver(builder: (context) =>
    switch (context.box<AppPhaseBox>().value) {
      AppLoadingPhase()      => const LoadingScreen(),
      AppErrorPhase(:final m)=> LoadingScreen.error(message: m),
      HomePhase(:final config, :final isPremium) =>
          HomeScreen(config: config, isPremium: isPremium),
    }),
);
```

Each `BoxObserver` subscribes only to what it reads — a progress bar
ticking five times a second does not rebuild the track title.

---

## Cross-cutting patterns

### The resource ladder

Three lifetimes, three words, one rule each:

| resource lives for | word | example |
|---|---|---|
| one input cycle | `connect(stream, cell)` | subscription to the current stream's events |
| the box | field + release in `compute` top / `dispose` | native player handle |
| the app | `graph.own(release)` | HTTP client, database |

There is no fourth mechanism. A gateway that outlives every input is a
constructor field with listeners bound once and cancelled in
`dispose` — exactly like in an ordinary class.

### Events are values with a sequence number

Cells are values and values are distinct — a repeating error would be
swallowed everywhere (cell guard, effect diffs). Encode occurrences as
data:

```dart
late final error = child<({int seq, PlayerError error})?>(null);
// ...
dispatch(error, (seq: ++_errorSeq, error: e));
```

Now every occurrence is distinct *as a value* and observable in UI,
graph and effects alike. This is the canonical answer to "what about
events?" — no separate event concept needed.

### Ports and adapters

Anything native or platform-specific sits behind a pure-Dart interface
(`PlayerGateway`). The box talks to the port; the adapter absorbs the
platform's lies (services that report the wrong state before binding,
late metadata frames from an abandoned stream, session adoption). The
box stays portable: cells map 1:1 onto any store, so the logic survives
even a framework change.

### Headless graph

The same `createApp` runs in a background isolate: build the graph,
skip the UI. If some boxes should behave differently without a screen
(skip artwork decoding), model that as data — a `ForegroundBox` node —
not as a second code path:

```dart
final graph = createApp(...);
graph.box<ForegroundBox>().set(false);
```

---

## What a new feature is

1. **Another node** — a new box (or module) plus its wires, or
2. **another effect** — a new sole-writer of some external subsystem, or
3. **another branch in the projection** — a new phase / a new case in
   an existing formula.

If a change does not fit any of the three, stop and re-read the map —
the design is trying to tell you something.
