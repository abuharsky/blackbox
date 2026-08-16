## 0.10.4 (docs)
- Field corrections to the Shared truth chapters, from the app that
  applied 0.10.3 whole:
  - `.late` readiness is decided by the output type: nullable output →
    ready immediately with null (null is a value); consumers only wait
    on a non-nullable output without `initialValue`.
  - The driving module takes the shared truth as a **required**
    constructor parameter — a `?? PremiumBox.late(...)` default is a
    silent mode switch that can split the app into two truths without
    tripping the one-declarer guard.
  - `updateInputForTest` is the canonical way to move a shared truth in
    tests: the test plays the driving graph.
  - The "typed input for effects" pattern rewritten as a warning: its
    own canonical example was deleted in the field once every field
    failed the ring criterion. Such a box is scaffolding with a
    demolition date, not architecture.

## 0.10.3
- One declarer per box: declaring a box (`add`/`addMultiBox`) on a
  second live graph now throws — declaring means driving the input and
  owning dispose, and the law allows one writer. Reading a foreign box
  via `whenReady` remains a subscription and stays legal. Re-declaring
  after the previous owner's dispose is allowed. Closes the API gap
  found by the "one fact, three graphs" field report.
- ARCHITECTURE.md grew the missing chapters, all field-tested twice:
  the top floor (shared truth lives above the modules), shared-truth
  lifecycle (created above / driven by one / read by all, with the
  reader-nature table: graph → wire, non-graph → listen, other
  process → disk), feedback rings through memory, trigger-in-input vs
  condition-in-run, the coordinator (decision-as-state), time is
  delivered never read, "don't know" is a value, debug is data, no
  optimism, loud emptiness, external readers, and what a finished app
  map looks like.

## 0.10.2
- Ownership fix: `graph.dispose()` now disposes only what was
  **declared** on the builder (`add`/`addMultiBox`). Sources registered
  lazily — `whenReady` on another graph's box — are unsubscribed, never
  disposed: they belong to whoever declared them. Cross-graph reads are
  now safe by construction (field report from a two-graph catalog/player
  app that had to route them through manual subscriptions).
- ARCHITECTURE.md: three new field-proven rules — the three-roles
  question (cache / truth / small thing of its own), honest slot keys
  (if the answer depends on a value, the value is in the key; keys hold
  only things with `==`), and the typed-input-for-effects pattern.

## 0.10.1
- Docs now ship inside the package: `doc/MODEL.md` (the law),
  `doc/ARCHITECTURE.md` (the seven-floor application pattern),
  `doc/MIGRATION.md` (0.8/0.9 migration + script) — readable offline
  from the pub cache, greppable by tooling.
- README: "Coming from Riverpod" and "Coming from MobX" mapping tables —
  port the roles (truth → cells, fetch → Cache, formula → compute),
  not the lines.
- Fixed a stale `Cache` docstring that still showed the pre-0.10
  spelling.

## 0.10.0 — the subtraction release

**Breaking.** The road to 1.0 is subtraction; this release is most of it.
The law is now the whole signature: `output = compute(input, state)`.

- `previous` is gone from every `compute` and the `MultiBox` compute:
  `compute(input)`, `compute()` for no-input boxes, `void compute(input)`
  for multiboxes. Three field reports showed `previous` lying (two
  computes in one frame) and every real box that needed "what did I
  show before" ended up owning that memory anyway. Migration: delete
  the parameter; if you actually used it, hold the memory in a
  `state(...)` cell (boxes) or a private field (multiboxes).
- Deprecated legacy deleted: `Persisted`, `AsyncPersisted`,
  `AsyncManagedCache`, `ManagedCache` mixins, `ValueStateBox`/`valueBox`,
  `LateAsyncBox`, and the deprecated `MultiBox.track()` alias. Their
  replacements (`state(persist:)`, `CachedBox`/`CachedValueBox` +
  `Cache`, `AsyncBox.late`, `connect`) have been the documented
  spelling since 0.9.x. On-disk data is untouched — the envelope format
  and keys are the same, so persisted values written by old mixins are
  read by state cells and caches as before.
- docs/MODEL.md status updated: the released API now matches the
  contract verbatim.

## 0.9.5
- `graph.box<T>()` — type lookup for places where `context.box` is
  unavailable (background isolates, tests, composition code). Loud by
  design: throws on a missing type and on twins. Promoted from a
  hand-rolled extension in a production app.
- `MultiBox.input` getter — the current input, mirroring `Box.input`:
  readable from buttons, listeners and helpers (inside `compute` it
  already holds the new input). Kills the manual mirror field
  (`_streamUrl`) every real multibox grew.
- `docs/ARCHITECTURE.md` — the seven-floor application pattern
  (runtime / skeleton / module / leaf / effects / projection / UI),
  the resource ladder, the events-as-numbered-values pattern, ports
  and the headless graph. Distilled from a production radio app.
- Feature freeze: from here to 1.0 the plan is subtraction only —
  remove `previous` from compute signatures, drop the deprecated
  legacy, add lints that guard the law.

## 0.9.4
- `addMultiBox` no longer requires `input:` — omit it for a
  self-driven module (`MultiBox<void>` or nullable input) that lives
  off its own streams: the graph delivers a single `null` input on the
  first pump, so `compute` runs exactly once to start the module.
  `.addMultiBox(billing)` replaces the last dummy in the system,
  `input: (d) {}`. Omitting `input:` for a non-nullable input type
  asserts loudly.

## 0.9.3
- `graph.own(release)` — the graph becomes the owner of resources
  created for it (HTTP clients, databases, files): they are released in
  `dispose()`, after every box has stopped, in reverse registration
  order. Kills the composition-wrapper class whose only job was to
  remember two `close()` calls: `buildApp(ctx)..own(client.close)`.
  Own only what was created for the graph — injected gateways belong to
  their creators. Extends the existing rule (graph dies → everything
  its own dies) to non-box resources; no new concept.
- `MultiBox.track()` is deprecated and gone from the public
  vocabulary. One resource rule for the whole library: streams feeding
  cells go through `connect()` (auto-released before the next compute
  and on dispose, as before); everything else lives in a field and is
  released at the top of `compute` and in `dispose` — same as in
  ordinary boxes. Also removes the name collision with UI read-tracking.

## 0.9.2
- `Box.late(initialValue:)` / `AsyncBox.late(initialValue:)` (and
  `CachedBox.late` / `CachedValueBox.late`) — create a box without an
  input; the graph delivers the first one. Kills the dummy-input
  problem: no more `MyBox(input: (config: null, ...))` seeds in
  composition roots. Until the first input a sync late box shows
  `initialValue` (or `null` for nullable outputs) or has no output yet
  (dependents wait, `value` throws a clear `StateError`); an async late
  box shows `AsyncLoading`/`AsyncData(initialValue)`. Field report from
  a real radio app's ~280-line AppBox.
- `graph.boxes` — boxes declared on the builder (`add`/`addMultiBox`),
  in declaration order. The provider list in one line:
  `BoxProvider.multi(boxes: graph.boxes, child: ...)` — no hand-rolled
  `exports` list to keep in sync.
- `LateAsyncBox` is deprecated — extend `AsyncBox` and use the
  `super.late(initialValue:)` constructor; same behavior, one class
  fewer.

## 0.9.1
- Added `ProvidableBox` — the common marker of everything deliverable
  through a BoxProvider. `OutputSource` and `MultiBox` implement it, so
  a composite (e.g. a player) goes into `BoxProvider` and comes out via
  `context.box<PlayerBox>()` like any other box — no second delivery
  mechanism (custom InheritedWidget) needed. Field report from a real
  audio-player app.

## 0.9.0
- The model (docs/MODEL.md): a box is `output = compute(input, state)` —
  input is what it is given, state is what it remembers, output is what
  it shows; one writer per thing.
- Added `state(...)` / `StateCell<T>` — declared box memory: a write
  re-runs compute and emits (equal writes are no-ops); `persist:` binds a
  global storage slot, `persistFor: (input) => key` binds a slot per
  input (re-slots on input change — no cross-slot leaks by construction);
  `codec:` overrides the registry locally.
- Added `CachedBox` / `NoInputCachedBox` — an async box whose compute is
  a cached `fetch`. One `Cache(ttl: ..., persist: 'menu')` declaration
  replaces the `AsyncPersisted` + `AsyncManagedCache` mixin pair; the
  contract lives in the names (`fetch` = "go get fresh, the cache decides
  when"; `compute` on a cached box is sealed). In-memory TTL by default;
  `persist:` adds a disk slot (instant cold start, disk timestamp drives
  expiration); `persistFor: (input) => key` keeps one slot per input;
  `refresh()`/`invalidateCache()` are now available on every async box.
  Plain async boxes cannot declare a cache — only the named classes can.
  Mixins remain as the legacy spelling with identical semantics and
  on-disk format.
- Added protected `input` getter on sync and async boxes — actions read
  the current input instead of caching it into fields inside compute.
- Cells work on async boxes too: a write re-runs the async compute
  (emitting `AsyncLoading` with the previous data first) — the search-box
  pattern; `persist:`/`persistFor:` behave as on sync boxes.
- Added `CachedValueBox` — the sync twin of `CachedBox` (the
  `ManagedCache` semantics, declaratively): the value is always readable
  synchronously starting from `initialValue`/the disk slot, `fetch` runs
  in the background, fetch errors are swallowed. `refresh()`,
  `invalidateCache()`, TTL-on-access included.
- `action(...)` now batches: cell writes inside it emit once at the end
  (on async boxes — for the synchronous part of the body).
- `codecFor` falls back to identity for nullable primitives and to an
  assignable registered codec (e.g. a `Service` codec serves `Service?`).
- Breaking: removed `FlowBox.state` getter (collided with the `state(...)`
  declarator) — use `value`.
- Graph tools:
  - `graph.settled()` — resolves when synchronous propagation is done;
    the test-friendly replacement for microtask-flushing loops.
  - `graph.toMermaid()` — renders the dependency graph as a Mermaid
    flowchart (edges recorded during pumps; multibox ownership dashed).
  - Pump-storm detector: a dependency cycle (or a box emitting a
    never-equal value each recompute) no longer freezes the isolate —
    after a bounded number of consecutive pump cycles the graph stops
    pumping and throws a diagnostic StateError.
- Deprecated the legacy spelling (removal before 1.0): `Persisted`,
  `AsyncPersisted`, `AsyncManagedCache`, `ManagedCache` — each replaced
  by one declaration (`state(persist:)`, `CachedBox`, `CachedValueBox`).
  Example apps ported; on-disk data stays compatible.
- README rewritten around the model (three things, one law, three
  words); migration table from the 0.8 mixins included.
- `MultiBox.connect(stream, cell, {map})` — the one-word form of the
  dominant compute pattern (stream → output cell): subscribes, maps,
  dispatches, and auto-releases on the next input cycle and on dispose.
  Asserts on a type mismatch when `map` is omitted.
- `MultiBox.child(initial)` now declares a `ChildCell` — the outward twin
  of a state cell: an ordinary `OutputSource` the graph/UI observe, with
  no public setter (only the owning multibox writes via `dispatch`);
  distinct by default; disposed with the multibox. `ValueStateBox` /
  `valueBox` are deprecated (`child(initial)` replaces the composite-leaf
  use; `state(...)` replaces the internal-memory use); `dispatchAsync`
  removed — an async child belongs in the graph, fed by a multibox
  output.


## 0.8.0
- Breaking / Fixed (persistence):
  - Restore precedence is now uniform: a disk-cached value wins over
    `initialValue` for `Persisted` and `AsyncPersisted`, matching
    `ManagedCache`. `initialValue` is only the first-boot fallback.
    Previously `initialValue` silently shadowed the persisted value.
  - A persist-key change (`persistKeyFor` returning a new key after an input
    change) now **re-initializes the box in the new slot**: `onFirstCompute`
    runs again with the new slot's cached value (or `null` for an empty
    slot), and the old slot's value no longer leaks into — or gets saved
    under — the new key. Previously a key switch could expose and persist
    the previous slot's data (e.g. one user's cart saved under another
    user's key).
  - `AsyncPersisted` severs the old slot's state on rekey: it never appears
    as `previousData` in loading/error outputs of the new slot.
  - `ManagedCache` on a slot switch adopts the new slot's cached value, or
    falls back to the constructor `initialValue` for an empty slot; an
    in-flight fetch for the previous input is invalidated and a fetch for
    the new input is started.
  - `ValueStateBox` composed with `Persisted` now actually restores: the
    persisted value becomes the effective initial input. The documented
    `ThemeBox` pattern previously never restored from disk.
- Added:
  - `MultiBox<I>` — composite black box: a single graph-driven input and N
    observable child cells. Children are owned via `child(...)`
    (`late final status = child(valueBox(...))`), driven only through the
    guarded `dispatch`/`dispatchAsync` bridge (asserts ownership in debug),
    and disposed together with the multibox. `track(...)` registers
    per-input-cycle cancels (auto-released before every `compute` and on
    dispose). Wire with `GraphBuilder.addMultiBox(mb, input: ..., onError:
    ...)` — `onError` mirrors `add`.
  - `ValueStateBox<T>` / `valueBox<T>` — identity-compute leaf cell.
    **Distinct by default**: pushing a value equal (`==`) to the current one
    is a no-op — no listener notifications, no graph pump. Native platform
    streams re-emit identical values constantly; distinct cells absorb that
    noise at the source. Pass `distinct: false` for values mutated in place.
  - `resolvePreviousForInput(I input, O? previous)` — protected hook on sync
    and async boxes that maps the effective `previous` value when a new
    input arrives; the persistence mixins use it for slot re-initialization.
- Hardening:
  - Box disposal is idempotent and final: after dispose a box ignores input
    pushes and never notifies listeners again (late native events and
    in-flight async completions are swallowed); async dispose invalidates
    in-flight computes. Graph and MultiBox both go through the same
    idempotent path, so combining `mb.dispose()` with `graph.dispose()` is
    safe.

## 0.7.1
- Added:
  - `DependencyResolver.whenReadyOrNull<T>(source)` — returns the source value
    when ready, or `null` otherwise, without skipping the pump cycle. Use when
    a dependent box accepts an optional input and should compute regardless of
    whether the upstream has produced data yet. Complements `whenReady<T>`.

## 0.7.0
- Breaking:
  - Renamed the async cache mixin `ManagedCache` → `AsyncManagedCache`. Update
    `with AsyncPersisted<...>, ManagedCache<...>` to
    `with AsyncPersisted<...>, AsyncManagedCache<...>`.
  - `AsyncManagedCache` is now relaxed to `on _AsyncBoxBase` and works
    standalone (in-memory TTL) without `AsyncPersisted`.
- Added:
  - New sync `ManagedCache<I, O>` mixin on `Box<I, O>` — sync always-available
    value backed by an async `fetch(input)`. Provides TTL, background refresh
    on access, `refresh()`, `invalidateCache()`, fail-open error handling, and
    automatic re-fetch on input change. Compose with `Persisted` to persist
    the cached value.
  - Sync `ManagedCache` composed with `Persisted` prefers the disk-cached
    value over `initialValue` on boot — `initialValue` becomes the empty-
    disk fallback rather than a default that overwrites cached state.

## 0.6.0
- Breaking:
  - Removed `listenSync()` and `listenAsync()` — use `listen()` instead.
  - Renamed `SyncOutput` → `SyncData`.
  - Renamed `prepare()` → `onFirstCompute()`.
  - Renamed `shouldEmitLoadingBeforeCompute()` → `shouldEmitLoading()`.
  - Removed `Runtime` classes — state management inlined into box base classes.
  - Sync `action()` now returns `void` instead of `Future<void>`.
  - `AsyncBox.lateinit()` replaced by `LateAsyncBox` class.
- Added:
  - `listen()` accepts `{bool skipFirst}` to skip the immediate callback with current state.
  - `beforeCompute()` hook on sync boxes (symmetric with async).
  - `Persisted` mixin now supports dynamic rekey when input changes (symmetric with `AsyncPersisted`).
- Changed:
  - `LateAsyncBox` extracted into its own file.
  - Async box base simplified: removed `_initialized`, `_pendingListeners`, `_requireInput`.

## 0.5.1
- Fixed:
  - `ManagedCache` no longer starts duplicate stale-cache refreshes while the first refresh is still in flight.
  - `refresh()` now completes after the underlying async recompute finishes, not just after it is scheduled.

## 0.5.0
- Breaking:
  - Removed `persistKey` parameter from all box constructors (`Box`, `NoInputBox`, `AsyncBox`, `NoInputAsyncBox`).
  - Removed `CachedAsyncSupport` mixin — replaced by `ManagedCache`.
  - Removed `persistenceKey`, `persistedAt`, and `clearPersistedValue()` from `_AsyncBoxBase` — use mixin members instead.
- Added:
  - `Persisted<I, O>` mixin for sync boxes — add `with Persisted<I, O>` and implement `persistKeyFor(I input)`.
  - `AsyncPersisted<I, O>` mixin for async boxes — save/restore only.
  - `ManagedCache<I, O>` mixin (on `AsyncPersisted`) — TTL, stale-while-refresh, `refresh()`, `invalidateCache()`.
  - Lifecycle hooks on box base classes: `resolveInitialValue()`, `onInitialized()`, `beforeCompute()`.
- Changed:
  - Persistence is fully extracted from box base classes into opt-in mixins.
  - Cache management is a separate layer: `AsyncPersisted` for save/restore, add `ManagedCache` for TTL and refresh controls.
  - Persist key is resolved once at init and never changes — to switch keys, destroy the box and create a new one.

## 0.4.4
- Add `CachedAsyncSupport` for persisted async cache with TTL-based lazy refresh.
- Let async boxes control loading emission via `shouldEmitLoadingBeforeCompute(...)`.
- Persist timestamps alongside cached values while keeping legacy raw cache reads compatible.

## 0.4.3
- Add `OutputSource.valueOrNull` and `OutputSource.requireValue` for ergonomic ready-value access.
- Improve not-ready `StateError` messages to include the current output state.

## 0.4.2
- Add `GraphBuilder.addEffect(...)` for explicit fire-and-forget graph effects with `current` and `previous` inputs.

## 0.4.1
- Add `awaitNextValueAfterAction(...)` as a `@visibleForTesting` helper for box and graph assertions.
- Refresh persistence and setup documentation across the package README.

## 0.4.0
- Breaking:
  - Removed `Box.lateinit()` constructor — sync boxes always require input at construction. Use `AsyncBox.lateinit()` for deferred initialization.
  - `_SyncBoxBase._runtime` is now `late final` (non-nullable)

## 0.3.2
- Fixed:
  - `AsyncBox.lateinit()` now returns `AsyncLoading` from `output` and `listen` before initialization (instead of throwing `StateError`)
  - Pending listeners are automatically flushed to the runtime when the box receives its first input

## 0.3.1
- Fixed:
  - `Graph.start()` no longer crashes on `lateinit` boxes — defers subscription until runtime is created by first pump cycle

## 0.3.0
- Breaking:
  - `when()` loading callback signature: `() → R` → `(T? previousData) → R`
  - `when()` error callback signature: `(Object, StackTrace?) → R` → `(Object, StackTrace?, T? previousData) → R`
- Added:
  - `AsyncLoading.previousData` — carries last known value during refresh
  - `AsyncError.previousData` — carries last known value on error after refresh

## 0.2.0
- Breaking:
  - Removed `LazyBox` — use `persistKey` parameter on Box/AsyncBox constructors
  - Removed `computeValue()` — `NoInputBox` and `NoInputAsyncBox` now use `compute()` directly
  - Renamed `dependencies:` parameter to `input:` in Graph.add()
  - Renamed `d.ready()` to `d.whenReady()` in DependencyResolver
  - Removed `d.output()` from DependencyResolver (use `box.output` directly)
  - Removed public `input` getter from Box/AsyncBox
- Added:
  - `prepare(I input, O? previous)` lifecycle hook — called once before first compute
  - `dispose()` lifecycle hook — called by Graph.dispose() for resource cleanup
  - `persistKey` parameter on Box/AsyncBox constructors for built-in persistence
  - `BlackboxPersistence.registerCodec<T>()` for global codec registry
  - Graph signal tracing: `build(trace: true)` for console output, `onTrace:` for custom handler
  - `PumpTrace` / `BoxTrace` data classes for programmatic trace access
- Changed:
  - Box hierarchy refactored: shared `_SyncBoxBase`/`_AsyncBoxBase` internal base classes
  - `NoInputBox<O>` and `NoInputAsyncBox<O>` are now independent from `Box<I,O>` / `AsyncBox<I,O>` (both extend shared base)
  - All box types use `compute()` as the override method name

## 0.1.0
- Breaking:
  - `Connector` -> `Graph`
  - `ConnectorBuilder` -> `GraphBuilder`
  - `connect(...)` -> `add(...)`
  - `connectWith(...)` -> `addWith(...)`
  - `PipelineBuilder.addWithDependencies(...)` -> `addWith(...)`
  - `FlowBoxBuilder()` is now created via `FlowBox.builder()`
- Changed:
  - Updated docs, tests, and examples to the new graph/flow builder API

## 0.0.7
- Renamed:
  - StateObserver -> FlowBox
- Breaking:
  - `FlowBox<S>` now requires `S extends FlowState`
- Added:
  - `FlowBoxBuilder.onLoading(...)` and `onError(...)` for reacting to `AsyncLoading` and `AsyncError`
- Changed:
  - FlowBox is now a sync box without input (`Box<O>`)
  - `onLoading(...)` and `onError(...)` are compile-time restricted to async sources only
## 0.0.4
- Renamed:
  - Graph -> Connector
  - Flow -> StateObserver
## 0.0.3
- Added GraphBuilder
- Added Pipeline of Boxes
## 0.0.2
- Updated docs
## 0.0.1
- Initial release
