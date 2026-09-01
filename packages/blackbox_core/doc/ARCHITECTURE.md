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
  final selectedId = SelectedStationIdBox.late(appId: ctx.appId);
  final selected   = SelectedStationBox.late();
  final player     = PlayerBox(gateway: ctx.playerGateway);    // one input, many outputs
  final nowPlaying = NowPlayingBox.late();
  final phase      = AppPhaseBox.late();                       // projection (floor 6)

  return Graph.builder<AppContext>(context: ctx)
      .add(config)
      .add(onboarding, input: (d) => configOrNull(d))
      .addMultiBox(billing)                        // no input: self-driven
      .add(selectedId, input: (d) => (
        config: configOrNull(d),
        premium: d.onlyWhenReady(billing.isPremium),
      ))
      .add(selected, input: (d) => (
        config: configOrNull(d),
        stationId: d.onlyWhenReady(selectedId),
      ))
      .addMultiBox(player, input: (d) {
        final station = d.onlyWhenReady(selected);
        if (station == null) return null;
        final premium = d.onlyWhenReady(billing.isPremium);
        // Policy lives in the wire: a free listener never streams a
        // premium channel — by construction, not by discipline.
        if (!premium && !station.isAvailableInFree) return null;
        return station.streamUrlFor(premium: premium);
      })
      .add(nowPlaying, input: (d) => (
        station: d.onlyWhenReady(selected),
        playerState: d.onlyWhenReady(player.status),
        premium: d.onlyWhenReady(billing.isPremium),
      ))
      .add(phase, input: (d) => (
        configState: configState(d),
        onboarding:  d.onlyWhenReady(onboarding),
        isPremium:   d.onlyWhenReady(billing.isPremium),
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
- **A self-driven `MultiBox`** (lives off its own streams, needs nothing
  from the graph) is added without `input:` — compute runs once to
  start it.

## Floor 3 — Module: organize one flat graph

When one concern grows past a handful of boxes, move its construction
and wiring into a small composition function. This is code organization,
not a new runtime layer: every box is still added to the same graph, so
the graph remains flat and `toMermaid()` can see every wire.

```dart
({
  SelectedStationIdBox selectedId,
  SelectedStationBox selected,
  NowPlayingBox nowPlaying,
}) addFeatures(
  GraphBuilder<AppContext> graph, {
  required String appId,
  required OutputSource<AppConfig> config,
  required OutputSource<bool> premium,
  required OutputSource<PlayerState> playerState,
}) {
  final selectedId = SelectedStationIdBox.late(appId: appId);
  final selected = SelectedStationBox.late();
  final nowPlaying = NowPlayingBox.late();

  graph
    ..add(selectedId, input: (d) => (
      config: d.whenReadyOrNull(config),
      premium: d.onlyWhenReady(premium),
    ))
    ..add(selected, input: (d) => (
      config: d.whenReadyOrNull(config),
      stationId: d.onlyWhenReady(selectedId),
    ))
    ..add(nowPlaying, input: (d) => (
      station: d.onlyWhenReady(selected),
      playerState: d.onlyWhenReady(playerState),
      premium: d.onlyWhenReady(premium),
    ));

  return (
    selectedId: selectedId,
    selected: selected,
    nowPlaying: nowPlaying,
  );
}
```

Rules of the module pattern:

- A module is a function/file that adds ordinary nodes to the caller's
  graph. It does not own another graph and does not change lifecycle.
- Dependencies from other concerns are explicit function parameters.
  The function may wire them, but it must not reach into another module
  through a captured concrete box.
- `MultiBox` is not a module container. It is one atomic node with one
  input and several independently observable output cells — a player is
  the canonical example.
- Do not create a `Graph` inside a `Box` or `MultiBox`. If a group can be
  flattened, keep it flat; if it truly needs an independent lifecycle,
  create a separate top-level graph at the composition root.

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
  (d) => d.onlyWhenReady(equalizer),
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
  (d) => d.onlyWhenReady(onboarding),
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
   consumers genuinely wait (`onlyWhenReady` blocks until the truth exists).

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
| another graph | a wire: `d.onlyWhenReady(premium)` — subscribes, never owns; visible on the reader's map |
| a non-graph consumer (watch bridge, UI) | `listen` — the same thing `BoxObserver` does |
| another process (background isolate) | the persisted slot on disk |

The wire needs no declaration: the first resolver word that touches a
foreign source — a box driven by another graph, a multibox cell —
lazily registers it with the reading graph as a live dependency,
subscription and map row included. `add(...)` is the *driving* verb
(input, lifecycle, disposal); reading is free.

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

## Flows — the reverse splitter

The kids-blocks taxonomy of the model:

- **Box** — one input, one output.
- **MultiBox** — the splitter: one input, many outputs (its cells).
- **The fold** — the reverse splitter: many **wires**, one output.

Note the asymmetry, it is deliberate: outputs are multiplied by the
*box* (they are its cells), but inputs are converged by the *graph* —
because fan-in must be visible on the map. A fold is not a special
class; it is an ordinary `Box` whose input record is fed by many wires.
(The historical `FlowBox` was the reverse splitter from before record
inputs existed; record inputs absorbed its job.)

The three resolver words are three answers to one question — *what
should arrive in the snapshot when a source is not ready?*

| word | answer | use when |
| --- | --- | --- |
| `onlyWhenReady(x)` | not ready → **this whole node skips the pump** | the value is a precondition (url without a station is meaningless) |
| `whenReadyOrNull(x)` | not ready → `null`, the node runs | absence is a valid case |
| `outputOf(x)` | the **phase itself** — loading/error/data — as a value | the phase *is* your input (a wizard step) |

One `onlyWhenReady` gates the entire snapshot — choosing the word per
wire is choosing the policy of the whole node.

Readiness is not nullability: a nullable box showing `null` is a
**ready** answer ("nothing selected"), and a nullable `.late` box is
ready immediately. Which word fits depends on the output type:

| output type | `onlyWhenReady` | `whenReadyOrNull` |
| --- | --- | --- |
| non-nullable | wait | `null` unambiguously means "not yet" ✓ |
| nullable | delivers ready-`null` honestly ✓ (and rarely gates) | **ambiguous**: `null` = not ready OR a ready nothing ✗ |

On a nullable source, don't reach for `whenReadyOrNull` — use
`onlyWhenReady` (the ready `null` arrives honestly) or `outputOf` when
the difference between "no phase yet" and "a ready nothing" matters.
If `null` starts meaning two things, decode it explicitly — "don't
know" is a value. And wires carry values,
never live objects: `outputOf` returns an immutable snapshot with
content `==`, so dedup keeps working and compute stays pure. Handing a
box itself into an input is a closed door: the reference never changes
(compute would never re-run), and reading it inside the box is a hidden
link.

A multibox cell is **born ready**: `child(initial)` has a value from
construction, so there is no "not yet" phase and `onlyWhenReady` on a
cell never gates. Absence must be a value the cell itself speaks — a
nullable reading (`child<Reading?>(null)`) or an explicit phase cell
(`disconnected`). A gate that must hold consumers back belongs to a
box (`.late()`, non-nullable output), never to a cell.

A wizard, in full — the auth flow as a fold over atomic boxes:

```dart
enum AuthStep { waitingPhone, sendingCode, waitingCode, checking, authorized, failed }

final class AuthFlowBox extends Box<
    ({Session? saved, Output<Session?>? verify, Output<CodeTicket?>? send}),
    AuthStep> {
  AuthFlowBox.late() : super.late(initialValue: AuthStep.waitingPhone);

  @override
  AuthStep compute(i) => switch (i) {
        // Line order = priority, like the coordinator.
        _ when i.saved != null                  => AuthStep.authorized,
        _ when i.verify is AsyncData<Session?>  => AuthStep.authorized,
        _ when i.verify is AsyncLoading         => AuthStep.checking,
        _ when i.verify is AsyncError           => AuthStep.failed,
        _ when i.send is AsyncLoading           => AuthStep.sendingCode,
        _ when i.send is AsyncData<CodeTicket?> => AuthStep.waitingCode,
        _                                       => AuthStep.waitingPhone,
      };
}

// The wire IS the "subscribed to everyone at once":
.add(flow, input: (d) => (
  saved:  d.onlyWhenReady(savedSession),
  verify: d.outputOf(codeVerify),
  send:   d.outputOf(codeSend),
))
```

The fold sees the whole snapshot at once, so priorities *between*
sources are one switch table — a per-source subscriber model cannot
express them at all. A genuinely path-dependent bit ("lock after three
failures") is a `state(...)` cell in the same box; a full state machine
is a cell + a pure `next(state, event)` function + a `dispatch` button,
with graph events arriving through effects. `AppPhaseBox` and
`PremiumBox` from the production maps are folds; the auth wizard is the
third of the same genre.

## The graph as a function — pipelines

An application is a graph started to live; a **pipeline is a graph
started once for its result**. `Pipeline extends Graph`: same wires,
same map, same `own(...)` — plus one verb. It was the prototype the
whole model grew from, returned home as a run mode.

The canonical shape — a RAG request, steps starting as soon as they
can, converging in folds:

```dart
final answer = await Pipeline.builder<void, Rendered>()
    .add(classify, retry: 2)                       // re-driven via refresh()
    .add(validate)
    .add(phrases, input: (d) => d.onlyWhenReady(classify), retry: 2)
    .add(enrich, onFailure: FailurePolicy.skip)    // its failure won't fail the run
    .add(retrieved, input: (d) => (
          phrases: d.onlyWhenReady(phrases),       // required
          valid:   d.onlyWhenReady(validate),
          extra:   d.whenReadyOrNull(enrich),      // failed optional → null
        ))
    .add(answerLlm, input: (d) => d.onlyWhenReady(retrieved))
    .add(reranked, input: (d) => d.onlyWhenReady(answerLlm))
    .add(rendered, input: (d) => d.onlyWhenReady(reranked))
    .build(result: rendered, timeout: Duration(seconds: 30))
    .start();
```

The contract, in five lines: `start()` completes with the result step's
first value; a required step's `AsyncError` (after its retries) fails
the run immediately — no silent hang; the timeout belongs to the
assembly (a pipeline that can hang is misassembled); the graph disposes
itself in every outcome, releasing `own(...)`-ed clients; a second
`start()` returns the same future.

Two footnotes the contract implies. **"First value" is literal**: a
progressive result — nullable, "null until done" — completes the run
at once with that first null. The result step's output must *be* the
answer: non-nullable, its input gated on the steps that make it
(`onlyWhenReady`), so "not done yet" is no output at all, not a value.
And **run-constant parameters** (the user's query, the run's recipe)
ride as the builder's `context:` and are read in wires via
`d.context` — a wire is for values that can change during the run;
context is for those that cannot.

Error policy splits along the model's own seam: **whether a reader
proceeds without a step is the wire's word** (`onlyWhenReady` /
`whenReadyOrNull` / `outputOf` — required / skippable / failure-as-data);
**whether the run survives a step's failure is the step's `onFailure:`
policy** (`fail` — the default — or `skip`). Retries are the runner's job (`retry: n` re-drives the step's
`refresh()`); anything fancier — backoff, fallbacks — lives inside the
step's own `compute`, where a step's policy belongs:

```dart
Future<Phrases> compute(Query q) =>
    retry(3, delay: Duration(seconds: 1), () => _llm.phrases(q));
```

And `toMermaid()` of a pipeline is the architecture diagram of the
request — for free.

## Cross-cutting patterns

### The visibility rule

**Reading a public output is allowed; hiding a reactive link is not.**
A hidden link is: a `Graph` inside a box, a box holding another box to
read it, a direct `.value`/`.listen` on a foreign box inside box code,
a self-subscribing aggregate. Every one of them makes the map lie —
`toMermaid()` shows a structure that isn't the real one.

The refinement that keeps commands legal: a box must not **react** to
another box except through its own graph input; **commanding** another
box's buttons is fine, but belongs to facades and intents (best passed
per call: `activate(stationId, player)`), not to constructor-held
fields.

Cross-graph reads obey a lifetime rule: **the owner outlives its
readers** — a wire into a box whose graph died is frozen forever (the
debug build warns loudly). On the map, borrowed sources are drawn
dashed; owned ones solid.

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
function. The clock therefore has exactly one owner, and the library
provides it: **`ClockBox`**, a self-driven node that owns every timer
and hands time out as keyed cells. **The schedule lives in the
subscription** — each reader names the moments it wants and pays only
for those:

| reader wants | mechanism | cost |
| --- | --- | --- |
| a known-in-advance boundary | `d.onlyWhenReady(clock.at(deadline))` | one pump, at the boundary |
| every tick, in the graph | `d.onlyWhenReady(clock.every(period))` | one pump per tick — deliberate, visible on the map |
| a ticking display (stopwatch, countdown) | `listen` / `BoxObserver` on `clock.every(period)` | zero pumps — the graph never hears it |

Cells are memoized by their key — honest slot keys — and a fired
`at()` stays `true`, so a late reader sees a fired alarm, not a missed
event. Deadlines are computed from *delivered* timestamps (an event's
`enteredAt` plus a stage's duration): there is deliberately no
`after(Duration)`, because "after" hides its epoch, and a hidden epoch
is a dishonest key. "Is the timer running" is `fireDate != null`,
never a flag derived from now().

### "Don't know" is a value, not null

An absent truth has two honest spellings, chosen per consumer. If
consumers may wait: a `.late()` box without `initialValue` — no output,
`onlyWhenReady` holds them. If consumers must render now: a *declared*
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
(`entitled: real || d.onlyWhenReady(debugPremium)`) — the whole graph flips,
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
