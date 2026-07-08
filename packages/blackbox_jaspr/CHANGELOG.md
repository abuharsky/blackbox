## 0.1.1
- `BoxProvider`/`BoxOverride`/`context.box` accept `ProvidableBox` —
  MultiBox composites can now be provided and resolved like any box.

## 0.1.0
- Requires `blackbox ^0.9.0` — the model release: state cells
  (`state(..., persist: ...)`), `CachedBox`/`CachedValueBox` with `fetch`,
  `MultiBox.child(initial)`/`connect`, `graph.settled()`/`toMermaid()`.
  See the blackbox changelog and README migration table.

## 0.0.6
- Update dependency: blackbox ^0.8.0, blackbox_support ^0.0.7

## 0.0.5
- Update dependency: blackbox ^0.7.0, blackbox_support ^0.0.6

## 0.0.4
- Refresh README examples and persistence setup docs for `LocalStorageStore.preload()`.
- Update dependency: blackbox ^0.4.1

## 0.0.3
- Add `BoxOverride<T>` and `BoxProvider.overrides(...)` for type-safe dependency injection and component testing.

## 0.0.2
- Breaking: removed `ObservableFlowBox`.
- `BoxObserver` now uses shared tracking runtime from `blackbox_support`; tracked reads come from core hooks.
- Update dependency: blackbox ^0.2.0, blackbox_support ^0.0.2

## 0.0.1
- Initial release with `BoxObserver`, `BoxProvider`, `ObservableFlowBox`, and `LocalStorageStore`.
