# blackbox_example

Flutter example app for Blackbox state management.

Two demos:
- **Counter** — sync + async box chain with persistence
- **Account / Auth / Profile** — cascading async dependencies with DI and per-service persistence

Persistence is initialized with `SharedPrefsStore.preload()` from
`blackbox_flutter`.

## Run

```bash
flutter run
```
