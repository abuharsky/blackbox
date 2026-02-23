# blackbox_annotations

Annotation package for Blackbox code generation.

Use this package to mark classes and methods that should be processed by `blackbox_codegen`.

## Installation

```yaml
dependencies:
  blackbox_annotations: ^0.0.2
```

Usually used together with:
- `blackbox`
- `blackbox_codegen` (dev dependency)
- `build_runner` (dev dependency)

## Available Annotations

- `@box`: marks a class for generation
- `@boxInit`: marks optional initialization method
- `@boxCompute`: marks main compute method (required)
- `@boxAction`: marks mutating action methods
- `@lazy`: generate lazy wrapper (`LazyBox`-based)
- `@observable`: generate output getter with observer tracking hook
- `@persistent(...)`: configure persistence key/store/codec

## Example

```dart
import 'package:blackbox_annotations/blackbox_annotations.dart';

part 'sample.box.g.dart';

@box
@lazy
@observable
class _SampleBox {
  @boxCompute
  Future<int> _compute(int input, int? previous) async {
    return input;
  }

  @boxAction
  void reset() {}
}
```

## `@persistent` Example

```dart
@persistent(
  keyBuilder: _MyBox._persistentKey,
  store: SharedPrefsStore,
  codec: MyValueCodec,
)
```

`keyBuilder` must be a static or top-level function.

## License

MIT
