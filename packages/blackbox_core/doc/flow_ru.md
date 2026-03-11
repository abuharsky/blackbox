# FlowBox (RU)

`FlowBox<S extends FlowState>` — агрегированное реактивное состояние, построенное из нескольких источников и оформленное как `Box<S>` без input.

## FlowBox.builder()

```dart
abstract class CounterFlowState extends FlowState {
  const CounterFlowState();
}

final class CounterValue extends CounterFlowState {
  final String label;

  const CounterValue(this.label);
}

final flow = FlowBox.builder<CounterFlowState>()
  .on<int>(boxA, (v) => CounterValue('a=$v'))
  .on<int>(boxB, (v) => CounterValue('b=$v'))
  .build(initial: const CounterValue('init'));
```

`on(source, map)` — подписывает `FlowBox` на `source` и преобразует ready value в `FlowState`.

Это специально отсекает примитивы и «случайные» `String/int` состояния.

`on(...)` реагирует только на ready output:
- `SyncOutput<T>`
- `AsyncData<T>`

Для удобства есть sugar-методы:
- `onLoading(...)` — реагирует на `AsyncLoading`
- `onError(...)` — реагирует на `AsyncError`

Важно: `onLoading(...)` и `onError(...)` принимают только `AsyncOutputSource<T>`.
То есть обычный sync `Box<T>` туда не передаётся уже на уровне компиляции.

Так как это обычный `Box<T>` без input:

```dart
final cancel = flow.listen((out) {
  print(out.value);
});
```

---

## Семантика initial

`initial` — **fallback**, а не гарантированное первое событие.

- Если есть синхронные источники, которые сразу имеют значение, они **перебьют** initial немедленно.
- Если используется `on(...)`, то async `loading/error` игнорируются и initial живёт до readiness.
- Если используются `onLoading(...)` / `onError(...)`, то initial может быть сразу перебит `AsyncLoading` / `AsyncError`.

Это сделано, чтобы избежать «мигания init → real» в sync сценариях.

---

## Рекомендации по тестам FlowBox

- Для sync источников проверяйте, что initial не эмитится (или эмитится только если нет источников).
- Для async источников проверяйте последовательность:
  - initial
  - затем mapped value после readiness
