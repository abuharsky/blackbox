## Next
- Breaking: removed `ObservableFlowBox` and legacy `BoxObserver.trackBox(...)`.
- `BoxObserver` now uses shared tracking runtime from `blackbox_support`; tracked reads come from core hooks.
- `SharedPrefsStore.preload()` now registers the global `BlackboxPersistence` store for persistent generated boxes.

## 0.0.4
- Added `ObservableOutputSource.reportRead()` as the generated tracking hook for `@observable` boxes.
- Deprecated `BoxObserver.trackBox(...)`; keep it only for legacy generated code.
- Documented that observable tracking should be used through `blackbox_codegen`, not via manual calls.

## 0.0.3
- Updated dependency on `blackbox` to `^0.1.0`
- Updated docs/examples to the `Graph` naming

## 0.0.2
- Initial release
