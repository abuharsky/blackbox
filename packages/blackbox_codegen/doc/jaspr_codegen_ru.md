# `blackbox_codegen` и `blackbox_jaspr`

Текущее решение не требует отдельного builder для `jaspr`.

## Как это работает

- `blackbox_codegen` генерирует один и тот же `.box.g.dart`
- tracking чтений `output` встроен в `blackbox` core hooks
- generated output знает только про runtime-agnostic box API и глобальный store из `BlackboxPersistence`
- UI runtime (`blackbox_flutter` или `blackbox_jaspr`) использует общий tracking runtime из `blackbox_support`

Поэтому один и тот же generator работает для обоих runtime.

## Что нужно в исходном файле

Для box source достаточно:

```dart
import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
```

Если используется persistence, приложение должно вызвать preload выбранного runtime:

- `await SharedPrefsStore.preload()` для Flutter
- `await LocalStorageStore.preload()` для Jaspr

## Что было изменено для поддержки Jaspr

- из generated output убраны framework-specific meta annotations
- `@observable` и специальные observable mixin-обвязки больше не нужны
- документация обновлена под оба runtime

Итог: `blackbox_jaspr` подключается как второй runtime-пакет, а не как отдельная ветка codegen.
