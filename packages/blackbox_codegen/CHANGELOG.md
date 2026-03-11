## Next
- Breaking: removed generator support for `@observable`.
- Generated boxes now rely on core output hooks instead of `ObservableOutputSource` mixins.
- Breaking: generated persistent boxes resolve the global `BlackboxPersistence` store instead of instantiating a runtime-specific store type.

## 0.0.5
- Make generated `.box.g.dart` output runtime-agnostic by removing framework meta annotations from generated methods.
- Document `blackbox_jaspr` as a supported runtime target for `@observable` and `@persistent`.

## 0.0.4
- Generate `ObservableOutputSource` mixins for `@observable` boxes and call `reportRead()` instead of `BoxObserver.trackBox(...)`.
- Keep generated observable tracking compatible with lazy wrappers and new `blackbox_flutter` docs/API.

## 0.0.3
- Fix `@lazy + @observable` generation so observable tracking is attached to the outer lazy wrapper read by UI.

## 0.0.2
- Initial release
