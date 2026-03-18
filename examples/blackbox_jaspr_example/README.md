# blackbox_jaspr_example

Jaspr (web) example app for Blackbox state management.

Mirrors the Flutter example with the same two demos:
- **Counter** — sync + async box chain with persistence
- **Account / Auth / Profile** — cascading async dependencies with DI and per-service persistence

Same boxes, same logic — different UI layer.

## Run

```bash
jaspr serve
```

Persistence uses `LocalStorageStore` from `blackbox_jaspr`.
