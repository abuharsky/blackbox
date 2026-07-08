## Unreleased (state-cells branch, experimental)
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
