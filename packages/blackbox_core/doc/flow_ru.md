# FlowBox (RU)

`FlowBox<S extends FlowState>` — агрегированное реактивное состояние, построенное из нескольких источников и оформленное как `Box<S>` без input.

## FlowBoxBuilder

```dart
abstract class CounterFlowState extends FlowState {
  const CounterFlowState();
}

final class CounterValue extends CounterFlowState {
  final String label;

  const CounterValue(this.label);
}

final flow = FlowBoxBuilder<CounterFlowState>()
  .on<int>(boxA, (v) => CounterValue('a=$v'))
  .on<int>(boxB, (v) => CounterValue('b=$v'))
  .build(initial: const CounterValue('init'));
```

`on<S>(source, map)` — подписывает `FlowBox` на `source` и преобразует ready value в `FlowState`.

Это специально отсекает примитивы и «случайные» `String/int` состояния.

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
- Если источники асинхронные и ещё loading, initial будет эмитнут до readiness.

Это сделано, чтобы избежать «мигания init → real» в sync сценариях.

---

## Рекомендации по тестам FlowBox

- Для sync источников проверяйте, что initial не эмитится (или эмитится только если нет источников).
- Для async источников проверяйте последовательность:
  - initial
  - затем mapped value после readiness
