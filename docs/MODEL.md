# The Blackbox Model

> **Status: design contract.** This document is the target model for
> Blackbox 1.0, being developed on the `state-cells` branch. The code is
> aligned to this text — not the other way around. The released API still
> differs in details (`compute(input, previous)`, `onFirstCompute`,
> `Persisted` on outputs); those differences are listed at the end.

A **box** has three things:

- **input** — what it is given,
- **state** — what it remembers,
- **output** — what it shows.

One law connects them:

```
output = compute(input, state)
```

New input arrives → compute runs. State changes → compute runs. There is
no other way output can change.

Each thing has exactly one writer:

| thing  | written by                         | seen by                         |
|--------|------------------------------------|---------------------------------|
| input  | the graph (or the parent multibox) | everything inside the box       |
| state  | the box's own methods ("buttons")  | compute; invisible from outside |
| output | compute                            | everyone outside                |

Inside a box you may do anything — call native code, hold handles, be
impure. The box's promise to the outside world is only this: *output
follows input and state*.

## Every box is the same formula

There are no "kinds" of boxes to choose between. A box is defined by
which of the three things are non-empty.

**Computed — no state.** A pure function of its input:

```dart
class FullPriceBox extends Box<Order, int> {
  @override
  int compute(Order order) => order.sum + order.delivery;
}
```

**Store — no input.** Shows what it remembers:

```dart
class ThemeBox extends NoInputBox<ThemeMode> {
  late final theme = state(ThemeMode.system, persist: 'theme');

  @override
  ThemeMode compute() => theme.value;

  void toggle() => theme.value =
      theme.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}
```

**Both — memory plus context.** Buttons may read the current `input`;
they never write it:

```dart
class CounterBox extends Box<int /* step */, int> {
  late final count = state(0);

  @override
  int compute(int step) => count.value;

  void inc() => count.value += input;
}
```

**Async computed.** compute takes time; output shows "not yet", then the
value (or the error):

```dart
class ProfileBox extends AsyncBox<Token, Profile> {
  @override
  Future<Profile> compute(Token token) => api.profile(token);
}
```

**Reconciliation is compute's job.** When memory refers to the input,
the formula — not a lifecycle hook — decides what is shown:

```dart
class SelectedServiceBox extends Box<List<Service>, Service?> {
  late final selected = state<Service?>(null, persist: 'selected');

  @override
  Service? compute(List<Service> services) =>
      services.contains(selected.value) ? selected.value : null;

  void select(Service s) => selected.value = s;
}
```

## What follows from the law

Nothing below is a new rule — each line is the law applied.

- **Persistence saves state, never output.** Output is always
  reproducible from input and state, so there is nothing to save.
  Caching the output of an *expensive* compute — with a TTL — is a
  different, explicitly named tool (`ManagedCache`), not persistence.
- **Restoring is not your code.** State is declared (`state(...)`), so
  the library restores it on creation, saves it on every write, and
  swaps it per slot (e.g. per user) by itself.
- **No manual notifications.** Writing state re-runs compute and
  notifies listeners. Writing an equal value is a no-op. Several writes
  in one gesture? Wrap them in `action { ... }` to emit once — batching
  is the only job `action` has left.
- **The graph stays the only map.** Boxes connect to boxes. State never
  leaks outside its box, so logic cannot scatter into ad-hoc
  subscriptions — the failure mode of unscoped observables.
- **Many outputs = MultiBox.** A box that must show several things
  exposes child boxes. For each child the parent plays the graph's role:
  it writes the child's input, and nobody else does.
- **FlowBox is not special.** Its state is one cell written by event
  handlers — buttons pressed by sources instead of the UI — and its
  compute shows that cell.

## Persistence and cache, precisely

One question decides which tool you need: *can the value be recomputed?*

- Lose it forever if not saved → **persist** it. That is what state cells do.
- Merely expensive to recompute → **cache** it. That is `ManagedCache` /
  `AsyncManagedCache` on a computed, with a TTL. Cache is never persistence.

Declaring persistence is one word on the cell:

```dart
// Global slot — one word.
late final theme = state(ThemeMode.system, persist: 'theme');

// Slot per input — the key is built from the box input.
class CartBox extends Box<String /* userId */, List<Item>> {
  late final items = state<List<Item>>(
    [],
    persistFor: (user) => 'cart:$user/items',
  );

  @override
  List<Item> compute(String user) => items.value;

  void add(Item i) => items.value = [...items.value, i];
}
```

The contract:

- A persisted cell restores itself on creation: the disk value wins,
  `initial` is only the first-boot fallback.
- Every effective write saves to the current slot.
- With `persistFor`, an input change that changes the key **re-slots**
  the cell: it reloads from the new slot (`cached ?? initial`) before
  compute runs — one compute, one emission, and the previous slot's
  value can never leak into the new one.
- Cells reuse the storage envelope and codec registry of the existing
  persistence layer, so on-disk data written by `Persisted` boxes stays
  readable when a box migrates to cells (pick the same key).
- `codec:` on the cell overrides the global registry when the type is
  generic or nullable.

## For current users: what this replaces

| today                                             | in the model                       |
|---------------------------------------------------|------------------------------------|
| private field + `onFirstCompute` + compute returns the field | one `state(...)` cell   |
| caching `input` into a field inside compute        | read `input` directly anywhere     |
| `action(() {...})` as a required ritual            | optional batching tool             |
| `previous` parameter of compute                    | gone — memory lives in state       |
| `Persisted` mixin on sync boxes                    | `persist:` on the cell             |
| `AsyncPersisted` + `AsyncManagedCache` on fetches  | unchanged — that is a cache        |
