# blackbox_codegen

Code generator for Blackbox boxes.

`blackbox_codegen` works with `blackbox_annotations` and `build_runner` to generate strongly typed `.box.g.dart` implementations from annotated classes.

## What It Generates

From an annotated implementation class, generator creates:
- concrete box class wrappers
- input/output wiring for `blackbox` runtime types
- optional lazy wrappers (`@lazy`)
- optional observable output tracking integration (`@observable`)
- optional persistence integration (`@persistent`)

## Setup

Add dependencies:

```yaml
dependencies:
  blackbox: any
  blackbox_annotations: any
  # Optional runtime package:
  # blackbox_flutter: any
  # blackbox_jaspr: any

dev_dependencies:
  build_runner: ^2.10.5
  blackbox_codegen: any
```

## Annotated Source Example

```dart
import 'package:blackbox_annotations/blackbox_annotations.dart';

part 'counter_box.box.g.dart';

@box
class _CounterBox {
  int _value = 0;

  @boxCompute
  int _compute(int? previous) => _value;

  @boxAction
  void inc() {
    _value++;
  }
}
```

## Run Generator

```bash
dart run build_runner build --delete-conflicting-outputs
```

Generated file appears next to the source:

```text
counter_box.box.g.dart
```

## Notes

- Keep the implementation class private (for example, `_CounterBox`) and use generated public class.
- `@observable` is the supported way to integrate with `BoxObserver`; generated code inserts the tracking hook for you.
- Generated `.box.g.dart` files are runtime-agnostic: they work with `blackbox_flutter` or `blackbox_jaspr` as long as your source library imports the matching package.
- For `@persistent(...)`, choose the store class from the runtime package you use, for example `SharedPrefsStore` in Flutter or `LocalStorageStore` in Jaspr.
- Do not edit generated `.box.g.dart` files manually.

## License

MIT
