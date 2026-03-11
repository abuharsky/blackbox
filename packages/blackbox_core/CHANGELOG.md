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
