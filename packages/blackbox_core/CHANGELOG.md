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
