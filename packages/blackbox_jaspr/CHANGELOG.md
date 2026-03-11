## Next
- Breaking: removed `ObservableFlowBox`.
- `BoxObserver` now uses shared tracking runtime from `blackbox_support`; tracked reads come from core hooks.
- `LocalStorageStore.preload()` now registers the global `BlackboxPersistence` store for persistent generated boxes.

## 0.0.1
- Initial release with `BoxObserver`, `BoxProvider`, `ObservableFlowBox`, and `LocalStorageStore`.
