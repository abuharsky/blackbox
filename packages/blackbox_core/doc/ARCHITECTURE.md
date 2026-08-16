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

## The top floor — when you have more than one graph

Real apps converge on a few graphs (player, catalog, purchases), and a
truth needed by two of them. The rule: **a truth needed by two modules
lives one floor up.** The smells that say you missed it: a *copy* of
someone's box synced by an effect, or a *closure* pulling into a
foreign module.

```dart
// SMELL — the selected station exists twice, synced by an effect;
// premium arrives as a pull that never re-pumps anything:
_catalog = Catalog(
  player: _player,
  isPremium: () => _purchases.premium.value.isPremium,
);

// THE TOP FLOOR — one truth, wires, modules unaware of each other:
final selection = SelectionBox();
final premium   = PremiumBox.late(initialValue: closedState);
final player    = Player(selection: selection, premium: premium);
final purchases = await createPurchases(premium: premium);
final catalog   = Catalog(selection: selection, premium: premium);

void play(List<Station> category, Station s) {   // cross-module intent
  selection.select(category, s);                 // lives here, not in a module
  player.playSelected(s);
}
```

*Paid for by:* a premium purchase mid-track that unlocked nothing until
the next song — the closure read fresh data, but nothing re-pumped.

### Shared truth: created above, driven by one, read by all

The enabling fact: **a box and a graph are different things with
different lifetimes.** Creating a box, wiring it into the graph that
computes it, and reading it from other graphs are three independent
events, in any order:

1. **Created at the top**, before any graph — with `.late()`, since its
   input arrives later. Pass `initialValue:` for a *declared* fallback
   (fail-closed premium: consumers must render now); omit it to make
   consumers genuinely wait (`whenReady` blocks until the truth exists).

   Readiness is decided by the **output type**: with `initialValue:`
   the box is ready immediately with the declared fallback; without it
   a *nullable* output is also ready immediately — with `null`, because
   null is a value; only a non-nullable output without `initialValue`
   makes consumers actually wait. If waiting is the point, make the
   output non-nullable.
2. **Driven by exactly one graph** — the producer module declares it
   (`add(premium, input: ...)`) whenever that module is born, even
   seconds later. Declaring a box on a second live graph throws: one
   declarer, one input-writer, one disposer.
3. **Read by everyone else**, mechanism chosen by the reader's nature:

| reader | mechanism |
| --- | --- |
| another graph | a wire: `d.whenReady(premium)` — subscribes, never owns; visible on the reader's map |
| a non-graph consumer (watch bridge, UI) | `listen` — the same thing `BoxObserver` does |
| another process (background isolate) | the persisted slot on disk |

One value, one mechanism per reader kind. If a fold seems to need a
late-born service in its constructor — it doesn't: a fold's
dependencies arrive as inputs by law; heavy services belong to producer
boxes upstream, inside the module that owns them.

Two consequences for everyday code:

- **The driving module takes the truth as a *required* constructor
  parameter.** A `premium ?? PremiumBox.late(...)` default reads as
  convenience but is a silent mode switch: forget to pass it in
  production and the app quietly splits into two premiums — the
  one-declarer guard cannot fire, because both graphs drive *different*
  instances. Creation belongs to whoever decides the sharing scope
  (main, or a test); the module only drives what it is given.
- **In tests, you are the driving graph.** A top-floor box has no
  buttons, so `updateInputForTest(box, (entitled: true, ...))` is the
  canonical way to move it — not a debug backdoor. It replaces the old
  lie of pushing the value through a shadow command that production
  never used.

### Feedback: the ring closes through memory

A graph that computes a value it also needs as input is not a cycle in
the graph — it is **state**. The sanctioned shape: an effect writes a
box's button; that box is a source; downstream reads it. One pump per
turn, and the loop is visible because the state is named.

The criterion that separates the pattern from a smell: *a copy of
someone else's truth → lift the truth instead; a result of your own
computation that you need back → memory, the ring is legal.*

Corollary for effects: **the trigger goes into the effect's input;
conditions of the moment are read inside `run`.** An effect that arms
autoplay on a station switch is triggered by the url change and merely
*checks* the play state at that moment — putting the state into the
input would wake the effect on every pause for nothing. (This is not
the closure smell above: the closure failed because premium had to
*trigger* re-computation, not be checked in passing.)

## Cross-cutting patterns

### The coordinator — a decision is state, not an event

One box encodes *all* auto-display priorities; **the order of lines in
compute is the priority**. The output is a decision or `null`. The
executor shows the surface and *confirms* via a button; an unconfirmed
decision doesn't burn — it is re-issued on the next trigger.

```dart
Interrupt? compute(InterruptInput i) {
  if (!i.onboarded) return null;                            // nobody interrupts onboarding
  if (i.session.entry == _handledEntry.value) return null;  // one per session entry
  if (i.premium.needsConfirmation && !i.premium.isPremium) {
    return (kind: InterruptKind.restoreDialog, entry: i.session.entry);
  }
  if (i.deal != null && !i.premium.isPremium) {
    return (kind: InterruptKind.promoSheet, entry: i.session.entry);
  }
  return null;
}
```

Because the decision is state, closing a paywall triggers nothing — the
executor has nothing to wake on except a real change in the graph.

### Time is delivered, never read

`compute` must not read the wall clock — it is neither input nor
memory, and an output depending on *when it was called* is not a
function. One observer owns the clock: it pokes `tick()` buttons on
session entry and arms a timer for the nearest *known-in-advance*
boundary (a promo window's end). "Is the timer running" is
`fireDate != null`, never a flag derived from now().

### "Don't know" is a value, not null

An absent truth has two honest spellings, chosen per consumer. If
consumers may wait: a `.late()` box without `initialValue` — no output,
`whenReady` holds them. If consumers must render now: a *declared*
fallback (`initialValue:` fail-closed) or an explicit flag in the fold:

```dart
// hydrated distinguishes "engine said false" from "engine hasn't spoken":
run: (now, was) {
  if (!now.hydrated || was == null || !was.hydrated) return;
  if (now.entitled && !was.entitled) onPremiumGained?.call();  // a sale —
}                                            // not a cold start of an owner
```

Never encode "don't know" as a default that happens to be safe — say it.

### Debug is data

A debug toggle enters the fold as an input
(`entitled: real || d.whenReady(debugPremium)`) — the whole graph flips,
persistence and the billing engine untouched, zero `if (kDebugMode)` in
logic.

### No optimism

A state cell moves only when the hardware moved it; truth flows up,
intent flows down, and they never impersonate each other. Intent is
captured at the facade — below it, "user stopped" and "stream died" are
indistinguishable.

### Loud emptiness

An empty showcase is an **error**, not an empty list: a paywall without
prices must be unrepresentable. Same for list projections: expose
`hasError` so a failed *first* load doesn't render as an honestly empty
category.

### External readers

The persistence envelope (`{v, ts}`) is a contract between cells. A
reader outside blackbox (an OS-alarm isolate calling `prefs.getBool`)
gets **raw keys, bypassing cells**; the cell syncs from them. Two such
places is a workaround; a third is a feature request.

### The finished map

A done application documents itself as: **boot order with paid-for
reasons → the tree (floors, graphs, graphless boxes) → the joints table
(who talks to whom, wire or callback) → the rules table (each rule
naming what it eliminates).** The maturity test: almost every "why" in
it is backed by a bug that no longer exists.

### The three-roles question

Before writing a box, answer one question: **is this a cache, a truth,
or a small thing of its own?** The answer determines the whole shape.

- **Truth** — there is nowhere to reload it from; it *is* the source
  (favorites, the selected station, settings). Persisted `state(...)`
  cells, synchronous restore before the first compute, **no `load()`**.
- **Cache** — a reproducible result of an expensive computation that
  expires (a fetched category, an iTunes lookup). `CachedBox` +
  `Cache(ttl:, persist:/persistFor:)`; none of `isLoading` / in-flight
  guards / try-finally is written by hand.
- **A small thing of its own** — a value living at its own rhythm (the
  view type of a list, the search query). A separate tiny box, not a
  field in someone else's output — or changing the layout rebuilds the
  list, and arriving metadata redraws the grid.

A faithful port of an old store usually smears all three into one class;
splitting by role is where the code disappears.

### Honest slot keys

**If the answer depends on a value, that value is in the key.** The
search region belongs in the search query; the station id belongs in the
playlist input. This kills generation counters, post-`await` field
comparison and "yesterday's answer under today's question" by
construction: the input key and the storage slot key are the same thing,
so a stale response *cannot* land on a fresh screen.

Corollary: **keys contain only values with `==`** — ids and records, not
entities that compare by identity. If `Genre` has no `==`, the key holds
`genreId`.

### The typed effect input — usually a waiting room

An earlier revision of this document blessed a box holding "two or
three loose values effects need from another module". The field killed
the pattern's own example: run through the ring criterion, every field
of that box turned out to be a copy of a foreign truth — one became a
top-floor box, one a derivation of the shared selection, one a
wire-driven box — and the class was deleted whole.

The honest form: **before creating a typed-input box, run every field
through the criterion** (a copy of someone's truth → lift it or wire
it; your own computation needed back → memory). What survives is
usually nothing, and the effect reads its record input straight from
wires. Such a box is legitimate only while a value genuinely cannot be
a wire *yet* — treat it as scaffolding with a demolition date, not as
architecture.

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
