# The Blackbox Model

> **Status: design contract.** The code is aligned to this text — not
> the other way around. As of 0.10.0 the released API matches the
> contract: `compute(input)` takes no `previous`, and the legacy
> spellings (`Persisted`/`ManagedCache` mixins, `ValueStateBox`,
> `LateAsyncBox`) are gone. The migration table at the end maps old
> spellings to current ones.

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
  late final _theme = state(ThemeMode.system, persist: 'theme');

  @override
  ThemeMode compute() => _theme.value;

  void toggle() => _theme.value =
      _theme.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}
```

**Both — memory plus context.** Buttons may read the current `input`;
they never write it:

```dart
class CounterBox extends Box<int /* step */, int> {
  late final _count = state(0);

  @override
  int compute(int step) => _count.value;

  void inc() => _count.value += input;
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
  late final _selected = state<Service?>(null, persist: 'selected');

  @override
  Service? compute(List<Service> services) =>
      services.contains(_selected.value) ? _selected.value : null;

  void select(Service s) => _selected.value = s;
}
```

## What follows from the law

Nothing below is a new rule — each line is the law applied.

- **Persistence saves state, never output.** Output is always
  reproducible from input and state, so there is nothing to save.
  Caching the output of an *expensive* compute — with a TTL — is a
  different, explicitly named tool (the `Cache` declaration), not
  persistence.
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
- Merely expensive to recompute → **cache** it, with a TTL. Cache is never
  persistence.

Both are one declaration. Memory:

```dart
// Global slot — one word.
late final _theme = state(ThemeMode.system, persist: 'theme');

// Slot per input — the key is built from the box input.
class CartBox extends Box<String /* userId */, List<Item>> {
  late final _items = state<List<Item>>(
    [],
    persistFor: (user) => 'cart:$user/items',
  );

  @override
  List<Item> compute(String user) => _items.value;

  void add(Item i) => _items.value = [..._items.value, i];
}
```

And cache — a box whose compute is a cached fetch:

```dart
class MenuBox extends NoInputCachedBox<Menu> {
  final Api _api;
  MenuBox(this._api);

  @override
  Cache get cache => Cache(ttl: Duration(minutes: 5), persist: 'menu');

  @override
  Future<Menu> fetch() => _api.fetchMenu();
}
```

The contract lives in the names, so nothing has to be kept in mind:
`compute` always runs; `fetch` runs when the cache decides (first boot,
expiration, `refresh()`). Whatever `fetch` returns becomes the cached
value. A plain async box cannot be silently turned into a cached one —
caching requires the class that says so.

`Cache(ttl: ...)` alone is an in-memory TTL; `persist:` adds a disk slot —
instant cold start, and the disk timestamp drives expiration, so a stale
restore refreshes itself in the background (no "forever-old menu");
`persistFor: (id) => 'menu:$id'` keeps one slot per input. `refresh()` and
`invalidateCache()` are available on the box.

The sync twin is `CachedValueBox` — for values that must always be
readable synchronously: the box shows `initialValue` (or the disk slot)
immediately, `fetch` updates it in the background, and fetch errors are
swallowed (the previous value stays). The stop-list pattern:

```dart
class StopListBox extends CachedValueBox<String, StopList> {
  StopListBox({required super.input}) : super(initialValue: StopList.empty);

  @override
  Cache<String, StopList> get cache =>
      Cache(ttl: Duration(seconds: 60), persistFor: (store) => 'stop:$store');

  @override
  Future<StopList> fetch(String store) => api.getStopList(store);
}
```

Three words, three contracts:

| you write | it means               | who triggers it            |
|-----------|------------------------|----------------------------|
| `state`   | what I remember        | my buttons                 |
| `compute` | what I show            | any input or state change  |
| `fetch`   | go get a fresh value   | the cache decides          |

The cell contract:

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
| `AsyncPersisted` + `AsyncManagedCache` mixin pair  | one `Cache(ttl: ..., persist: ...)` declaration |
