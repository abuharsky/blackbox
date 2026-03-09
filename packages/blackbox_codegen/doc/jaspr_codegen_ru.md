# `blackbox_codegen` и `blackbox_jaspr`

Текущее решение не требует отдельного builder для `jaspr`.

## Как это работает

- `blackbox_codegen` генерирует один и тот же `.box.g.dart`
- generated output использует только:
  - `ObservableOutputSource<T>`
  - `reportRead()`
  - указанный в `@persistent(...)` store type
- эти API теперь одинаково есть и в `blackbox_flutter`, и в `blackbox_jaspr`

Поэтому один и тот же generator работает для обоих runtime.

## Что нужно в исходном файле

Для Flutter:

```dart
import 'package:blackbox_flutter/blackbox_flutter.dart';
```

Для Jaspr:

```dart
import 'package:blackbox_jaspr/blackbox_jaspr.dart';
```

Если используется persistence, в `@persistent(...)` указывается store из выбранного runtime:

- `SharedPrefsStore` для Flutter
- `LocalStorageStore` для Jaspr

## Что было изменено для поддержки Jaspr

- из generated output убраны framework-specific meta annotations
- `blackbox_codegen` больше не требует косвенного импорта `flutter/foundation.dart`
- документация обновлена под оба runtime

Итог: `blackbox_jaspr` подключается как второй runtime-пакет, а не как отдельная ветка codegen.
