# Graph (RU)

`Graph` — планировщик и контейнер зависимостей для Boxes.

## Основные операции

### add(source)

```dart
g.add(sourceBox);
```

Регистрирует источник (box без input) как dependency source.

### addWithDependencies(dependent, dependencies, onError?)

```dart
g.addWithDependencies(
  dep,
  dependencies: (d) => d.of(source),
  onError: (e) => e is StateError,
);
```

Регистрирует input-box и описывает, как собрать его вход (input) через `DependencyResolver`.

---

## DependencyResolver.of(...)

`d.of(box)` возвращает **значение** зависимости, а не Output.

Инварианты:
- box **должен быть зарегистрирован** через `g.add(...)` раньше, чем его запросят.
- если dependency не зарегистрирован → `StateError("Dependency is not registered")`
- если dependency не ready (например, async loading) → `StateError` (по умолчанию)

---

## onError

`onError` — единственный корректный способ разрешить временно неготовые зависимости.

- `onError == null` → ошибка фатальна и пробрасывается.
- `onError(e) == true` → ошибка подавляется (узел может попытаться пересчитаться позже).
- `onError(e) == false` → ошибка пробрасывается.

Важно: подавление ошибки не означает «compute не вызовется».  
Зависимый узел может пытаться вычислиться повторно (и больше одного раза) — это часть семантики планировщика.

---

## Типовые ошибки (и что это значит)

### "Dependency is not registered: X"

Вы вызвали `d.of(X)`, но X не был добавлен как source в Graph.
Правильный порядок:

```dart
g.add(source);
g.addWithDependencies(dep, dependencies: (d) => d.of(source));
```

---

## Рекомендации по тестам

- Не тестируйте точное число `compute()` вызовов, если это не зафиксированная часть контракта.
- Тестируйте итоговый Output и инварианты:
  - корректность значения после readiness
  - корректность реакции на signal / изменение dependency
  - поведение onError (swallow vs throw)
