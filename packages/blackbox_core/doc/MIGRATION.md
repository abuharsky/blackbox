# Migrating to blackbox 0.10

Everything removed in 0.10 fails at **compile time**, never silently at
runtime — so the whole migration is "fix the red, and you're done".
Persisted data is untouched: the disk envelope format and keys are the
same, so values written by 0.8/0.9 boxes are read back as before.

Pin releases by tag when depending via git:

```yaml
dependencies:
  blackbox:
    git:
      url: git@github.com:abuharsky/blackbox.git
      ref: v0.10.0
      path: packages/blackbox_core
```

## 0.9.x → 0.10 (mechanical)

Run the script from your project root — it rewrites `compute`
signatures under `lib/` and `test/` and prints anything that needs a
human look:

```sh
dart run <path-to-blackbox>/tool/migrate_0_10.dart
```

Or do it by hand:

| was | now |
|---|---|
| `O compute(I input, O? previous)` | `O compute(I input)` |
| `O compute(O? previous)` (no-input box) | `O compute()` |
| `void compute(I input, I? previous)` (multibox) | `void compute(I input)` |
| body actually used `previous` | keep that memory yourself: a `state(...)` cell in a box, a private field in a multibox |
| `extends LateAsyncBox<I, O>` | `extends AsyncBox<I, O>` + `Ctor() : super.late()` |
| `track(sub.cancel)` | `connect(stream, cell)` for streams; a field released at the top of `compute` and in `dispose` for anything else |

Why `previous` is gone: it lied (two computes in one frame deliver a
stale value), and every real box that needed "what did I show before"
ended up owning that memory anyway.

## 0.8.x → 0.10 (the mixins)

The 0.9 spellings are now the only spellings:

| was | now |
|---|---|
| `with Persisted` + `persistKeyFor` + `onFirstCompute` | `late final _x = state(initial, persist: 'key')` (or `persistFor: (input) => ...`) |
| `with AsyncPersisted, AsyncManagedCache` | `extends CachedBox` / `NoInputCachedBox` + `Cache(ttl: ..., persist: ...)` + `fetch` |
| `with ManagedCache` (sync) | `extends CachedValueBox` + `Cache(...)` + `fetch` |
| `extends ValueStateBox` / `valueBox(...)` | a box with a `state(...)` cell, or a `child(...)` cell on a multibox |

Disk data written by the mixins is read by cells and caches unchanged.

## Free upgrades once you compile

None of these are required — each one deletes code:

- **Dummy inputs** → `.late()`: a box whose input comes from the graph
  is constructed with `MyBox.late(initialValue: ...)`; no more
  `MyBox(input: null)` seeds or factory ordering.
- **exports lists** → `BoxProvider.multi(boxes: graph.boxes, ...)`.
- **Composition wrapper classes** → `buildApp(ctx)..own(client.close)`:
  the graph owns what was created for it and releases it on dispose,
  after all boxes stop.
- **Self-driven modules** → `.addMultiBox(billing)` with no `input:` —
  compute runs once to start it (valid for `MultiBox<void>` / nullable
  inputs).
- **Input mirror fields in multiboxes** (`_streamUrl`) → the `input`
  getter; inside `compute` it already holds the new input.
- **Hand-rolled type lookup** (`boxOf` extensions) → `graph.box<T>()`
  (loud on missing and on twins) for background isolates and tests.
- **BoxProvider.multi** now asserts on two boxes of the same runtime
  type instead of silently keeping the last one — if it fires, give
  twins distinct types or scope one with a nested provider.
