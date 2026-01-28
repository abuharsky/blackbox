# Тестирование и покрытие (RU)

## Запуск тестов

```bash
dart test
```

## Покрытие (coverage)

```bash
dart test --coverage=coverage
dart pub global activate coverage
dart pub global run coverage:format_coverage \
  --packages=.dart_tool/package_config.json \
  --report-on=lib \
  --in=coverage \
  --out=coverage/lcov.info \
  --lcov
```

### Просмотр

- VS Code: Coverage Gutters → открыть `coverage/lcov.info`
- HTML (если установлен lcov): `genhtml coverage/lcov.info -o coverage/html`

---

## Как писать хорошие тесты для Blackbox

### 1) Не фиксируйте «точное число compute()»
Если контракт это явно не гарантирует — тест будет хрупким.

### 2) Фиксируйте инварианты:
- корректный output после signal
- корректное поведение Graph при missing dependency
- throw vs swallow при onError
- правильная последовательность для async readiness (initial → data)

### 3) Точки, которые часто ломают тесты
- `addWithDependencies` инициирует pump сразу → ошибки всплывают при add
- initial в Flow — fallback, а не первое событие
