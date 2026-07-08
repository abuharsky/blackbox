# Blackbox

Reactive state management for Dart, Flutter, and Jaspr.

All your business logic lives in **boxes**. All dependencies between boxes
are declared in one place — the **graph**. No code generation. No
boilerplate.

## The model

A **box** has three things:

- **input** — what it is given,
- **state** — what it remembers,
- **output** — what it shows.

One law connects them:

```
output = compute(input, state)
```

New input arrives → compute runs. State changes → compute runs. There is
no other way output can change. Each thing has exactly one writer:

| thing  | written by                         | seen by                         |
|--------|------------------------------------|---------------------------------|
| input  | the graph                          | everything inside the box       |
| state  | the box's own methods ("buttons")  | compute; invisible from outside |
| output | compute                            | everyone outside                |

Inside a box you may do anything — call native code, hold handles, be
impure. The box's promise to the outside world is only this: *output
follows input and state*.

Three words cover every task:

| you write | it means             | who triggers it           |
|-----------|----------------------|---------------------------|
| `state`   | what I remember      | my buttons                |
| `compute` | what I show          | any input or state change |
| `fetch`   | go get a fresh value | the cache decides         |

## Why Blackbox?

Most state management libraries (Riverpod, Bloc, MobX, Redux) are great —
Blackbox was inspired by them. But they share a common problem:
**dependencies between state units are scattered across the codebase**.
When something breaks in a chain of 5 providers, you reconstruct the
graph by reading every file.

Blackbox takes a different approach:

- **Graph in one place.** You see every dependency at a glance — and can
  render it: `print(graph.toMermaid())`.
- **No code generation.** A box is a plain Dart class — 5-15 lines.
- **Persistence is one word.** `state(0, persist: 'counter')` — restored
  on creation, saved on every write. No hooks, no manual restore.
- **Cache is one declaration.** `Cache(ttl: ..., persist: ...)` — TTL,
  stale-while-refresh, instant cold start from disk.
- **Cross-platform.** Boxes are pure Dart. Same logic runs in Flutter
  and Jaspr (web).

## Installation

```yaml
dependencies:
  blackbox: ^0.9.0          # core (pure Dart — works everywhere)
  blackbox_flutter: ^0.1.0  # Flutter bindings
  blackbox_jaspr: ^0.1.0    # Jaspr (web) bindings
```

## Quick start: a counter

```dart
import 'package:blackbox/blackbox.dart';

class CounterBox extends NoInputBox<int> {
  late final _count = state(0);              // what I remember

  @override
  int compute(int? _) => _count.value;       // what I show

  void inc() => _count.value++;              // button
}

void main() {
  final counter = CounterBox();
  counter.listen((o) => print('counter = ${(o as SyncData<int>).value}'));

  counter.inc(); // counter = 1
  counter.inc(); // counter = 2
}
```

Writing a cell recomputes and notifies automatically. Writing an equal
value is a no-op. Declare cells as `_private` fields — state is the
box's internals; output is its only public face.

Want it to survive restarts? One word:

```dart
late final _count = state(0, persist: 'counter');
```

## Graph: connecting boxes

Dependencies are declared in one place. Here a `StepBox` controls the
step size and `CounterBox` uses it as *context* — buttons read the
current `input` directly:

```dart
class StepBox extends NoInputBox<int> {
  late final _step = state(1);
  @override
  int compute(int? _) => _step.value;
  void set(int v) => _step.value = v;
}

class CounterBox extends Box<int /* step */, int> {
  late final _count = state(0);

  CounterBox({required int input}) : super(input);

  @override
  int compute(int step, int? _) => _count.value;

  void inc() => _count.value += input;   // input = always-current step
}

void main() async {
  final step = StepBox();
  final counter = CounterBox(input: 1);

  final graph = Graph.builder()
      .add(step)
      .add(counter, input: (d) => d.whenReady(step))
      .build(start: true);

  counter.inc();        // +1
  step.set(5);
  await graph.settled(); // propagation done
  counter.inc();        // +5

  print(graph.toMermaid()); // the app map, as a picture

  graph.dispose();
}
```

`d.whenReady(step)` means: "when `step` has a value, pass it as input".
If the upstream is async and still loading, the dependent box waits.
`d.whenReadyOrNull(step)` passes `null` instead of waiting.

### Effects

Side effects live in the graph too — not hidden in widgets:

```dart
Graph.builder()
    .add(checkoutState)
    .addEffect<CheckoutState>(
      (d) => d.whenReady(checkoutState),
      run: (current, previous) {
        if (previous is! CheckoutSuccess && current is CheckoutSuccess) {
          cart.clear();
        }
      },
    )
    .build(start: true);
```

### Safety

The graph fails loudly instead of freezing: a dependency cycle (or a box
that emits a never-equal value on every recompute) is detected after a
bounded number of pump cycles, stops the graph, and throws a diagnostic
error. In tests, `await graph.settled()` replaces micro-task flushing
hacks.

## Async boxes

For API calls, use `AsyncBox` / `NoInputAsyncBox` — same law, output
takes time:

```dart
class ProfileBox extends AsyncBox<Token, Profile> {
  final Api _api;
  ProfileBox(this._api, {required Token input}) : super(input);

  @override
  Future<Profile> compute(Token token, Profile? _) => _api.profile(token);
}
```

Async output passes through `AsyncLoading` → `AsyncData` (or
`AsyncError`); handle all states in the UI:

```dart
profileBox.output.when(
  data: (profile) => ProfileView(profile),
  loading: (previous) => previous != null ? ProfileView(previous) : Spinner(),
  error: (e, st, previous) => ErrorView(e),
);
```

Every async box has built-in `refresh()` — no need to write your own.
Async boxes can own state cells too (the search-box pattern): writing
`_query.value` re-runs the async compute.

## Cache: expensive fetches

One question decides the tool: *can the value be recomputed?* Lose it
forever if not saved → **persist** it (a state cell). Merely expensive
to re-fetch → **cache** it:

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

`fetch` means "go get a fresh value" — *when* it runs is the cache's
concern: first boot, TTL expiration, `refresh()` (pull-to-refresh),
`invalidateCache()` (city/account change). With `persist:` the app cold
starts instantly from disk, and the disk timestamp drives expiration — a
stale restore refreshes itself in the background. `persistFor: (id) =>
'menu:$id'` keeps one slot per input.

For values that must always be readable synchronously (a stop-list, a
config), use the sync twin — `CachedValueBox`: shows
`initialValue`/disk immediately, fetches in the background, swallows
fetch errors:

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

## Persistence: memory that survives restarts

Persistence belongs to state cells — memory is the only thing worth
saving (output is always reproducible):

```dart
// Global slot.
late final _theme = state('light', persist: 'theme');

// Slot per input: switching user re-slots the cell. Alice's cart can
// never leak to Bob — by construction.
class CartBox extends Box<String /* userId */, List<Item>> {
  late final _items = state<List<Item>>(
    const [],
    persistFor: (user) => 'cart:$user',
  );

  CartBox({required String input}) : super(input);

  @override
  List<Item> compute(String user, List<Item>? _) => _items.value;

  void add(Item i) => _items.value = [..._items.value, i];
}
```

Initialize a store once at startup:

```dart
// Flutter
await SharedPrefsStore.preload();

// Jaspr
await LocalStorageStore.preload();

// Pure Dart / custom store
BlackboxPersistence.init(myStore, codecs: [UserJsonCodec()]);
```

Primitives (`int`, `double`, `String`, `bool`, nullable included) need
no codec. Register a `PersistentCodec<T>` for other types, or pass
`codec:` on the cell.

## MultiBox: one input, many outputs

Some units are naturally *one input → many outputs*: a player takes a
channel and shows status, position, and track. `MultiBox` owns N output
cells — `child(...)` is the outward twin of `state(...)`:

```dart
class PlayerBox extends MultiBox<Channel> {
  late final status   = child(PlayerStatus.idle);
  late final position = child(Duration.zero);

  NativePlayer? _native;

  void play() => _native?.play();    // commands go to the native side;
  void pause() => _native?.pause();  // truth comes back via its streams

  @override
  void compute(Channel channel, Channel? previous) {
    _native?.release();
    _native = NativePlayer.open(channel.url);

    // compute reads as a routing table: source → output.
    connect(_native!.onState, status, map: mapState);
    connect(_native!.onPosition, position);
  }

  @override
  void dispose() {
    _native?.release();
    super.dispose();
  }
}
```

The rules that keep it a black box:

- the graph drives the multibox's single input;
- only the multibox writes its cells (`connect` for streams, `dispatch`
  for single values) — cells have no public setter;
- `connect`-ed subscriptions die automatically on the next input and on
  dispose — nothing to leak;
- cells are distinct by default: duplicate native events are absorbed at
  the source, never waking the UI or the graph;
- graph nodes depend on children directly: `d.whenReady(player.status)`.

## Flutter integration

```dart
import 'package:blackbox_flutter/blackbox_flutter.dart';

// Provide boxes down the tree.
BoxProvider.multi(boxes: [step, counter], child: MyApp());

// Rebuilds only when the boxes read inside actually change.
BoxObserver(
  builder: (context) {
    final counter = context.box<CounterBox>();
    return Text('${counter.value}');
  },
);
```

`blackbox_jaspr` mirrors the same API for the web.

## Pipeline: a one-shot graph

Runs once, returns the final box's result, disposes itself:

```dart
final result = await Pipeline.builder<void, Report>()
    .add(loader)
    .add(parser, input: (d) => d.whenReady(loader))
    .result(parser)
    .build()
    .run();
```

## Testing

Boxes are plain Dart — construct, poke buttons, read outputs. For graphs
use `await graph.settled()` between mutation and assertion. In widget
tests, swap boxes via `BoxProvider.overrides`.

## Migrating from 0.8 (mixins)

The 0.8 mixins still work but are deprecated; each has a one-declaration
replacement:

| 0.8                                        | now                                  |
|--------------------------------------------|--------------------------------------|
| field + `onFirstCompute` + compute-returns-field | one `state(...)` cell          |
| `Persisted` mixin + `persistKeyFor`         | `persist:` / `persistFor:` on the cell |
| `AsyncPersisted` + `AsyncManagedCache`      | `CachedBox` + `Cache(...)` + `fetch` |
| `ManagedCache` (sync)                       | `CachedValueBox` + `Cache(...)` + `fetch` |
| `ValueStateBox` children                    | `child(initial)` output cells        |
| hand-written `void refresh()`               | built-in `refresh()`                 |

On-disk data is compatible: cells use the same storage envelope and
codecs — keep the same keys and user data survives the migration.

The full design contract lives in [docs/MODEL.md](docs/MODEL.md).
