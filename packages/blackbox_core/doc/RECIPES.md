# Recipes

Task → solution. Words are in [CONCEPTS.md](CONCEPTS.md), exact behavior
in [SEMANTICS.md](SEMANTICS.md).

**State and data**
- [Save a setting](#save-a-setting)
- [Keep memory per user or per item](#keep-memory-per-user-or-per-item)
- [Cache a request](#cache-a-request)
- [A fetched value that is always readable](#a-fetched-value-that-is-always-readable)
- [One box for whichever item is open](#one-box-for-whichever-item-is-open)
- [Check memory against new data](#check-memory-against-new-data)

**Combining**
- [Combine several sources](#combine-several-sources)
- [A step from loading states (a wizard)](#a-step-from-loading-states-a-wizard)
- [Say "don't know"](#say-dont-know)
- [A state machine](#a-state-machine)
- [Remember an occurrence](#remember-an-occurrence)
- [A debug switch](#a-debug-switch)

**Modules and the world**
- [Share a box between modules](#share-a-box-between-modules)
- [Command the outside world](#command-the-outside-world)
- [Trigger vs condition in an effect](#trigger-vs-condition-in-an-effect)
- [Feed a result back](#feed-a-result-back)
- [Connect a native device](#connect-a-native-device)
- [Decide what to show first](#decide-what-to-show-first)

**Time**
- [Act at a moment](#act-at-a-moment)
- [A ticking display](#a-ticking-display)
- [Wait until the input settles](#wait-until-the-input-settles)
- [Ignore short flickers](#ignore-short-flickers)

**Running and testing**
- [Read a box in plain code](#read-a-box-in-plain-code)
- [A snapshot read inside compute](#a-snapshot-read-inside-compute)
- [Run a graph once for a result](#run-a-graph-once-for-a-result)
- [Test a box](#test-a-box)
- [Test a graph](#test-a-graph)
- [Test with time](#test-with-time)
- [Test UI with fake boxes](#test-ui-with-fake-boxes)

---

## Save a setting

A state cell with `persist:`; restored on creation, saved on every write.

```dart
final class ThemeBox extends NoInputBox<ThemeMode> {
  late final _mode = state(ThemeMode.system, persist: 'theme');
  @override
  ThemeMode compute() => _mode.value;
  void set(ThemeMode m) => _mode.value = m;
}
```

Set up the store once at startup: `await SharedPrefsStore.preload()`
(Flutter), `LocalStorageStore.preload()` (Jaspr), or
`BlackboxPersistence.init(store)`.

## Keep memory per user or per item

`persistFor:` builds the slot key from the input. A new input loads its
own slot; nothing crosses over.

```dart
final class CartBox extends Box<String /* userId */, List<Item>> {
  CartBox.late() : super.late();
  late final _items = state<List<Item>>(const [], persistFor: (u) => 'cart:$u');
  @override
  List<Item> compute(String user) => _items.value;
  void add(Item i) => _items.value = [..._items.value, i];
}
```

## Cache a request

`CachedBox` + `Cache` + `fetch`. The cache decides when `fetch` runs.

```dart
final class PlaylistBox extends CachedBox<String /* stationId */, Playlist> {
  PlaylistBox.late(this._api) : super.late();
  final Api _api;
  @override
  Cache<String, Playlist> get cache => Cache(
      ttl: const Duration(minutes: 5), persistFor: (id) => 'playlist:$id');
  @override
  Future<Playlist> fetch(String id) => _api.playlist(id);
}
```

`refresh()` for pull-to-refresh; `invalidateCache()` on logout.

## A fetched value that is always readable

`CachedValueBox`: shows `initialValue` (or disk) at once, fetches in the
background, keeps the old value on error.

```dart
final class StopListBox extends CachedValueBox<String, StopList> {
  StopListBox.late() : super.late(initialValue: StopList.empty);
  @override
  Cache<String, StopList> get cache => Cache(
      ttl: const Duration(seconds: 60), persistFor: (store) => 'stop:$store');
  @override
  Future<StopList> fetch(String store) => api.stopList(store);
}
```

## One box for whichever item is open

The open item's id is the input; the cache keeps one slot per id. Going
back to an item is instant, and nothing is created per item.

```dart
final openId = OpenStationBox();             // a cell: the open station id
final details = StationDetailsBox.late();    // CachedBox, persistFor: id
graph
  ..add(openId)
  ..add(details, input: (d) => d.onlyWhenReady(openId));
```

## Check memory against new data

`compute` decides what is shown when memory refers to the input.

```dart
@override
Service? compute(List<Service> services) =>
    services.contains(_selected.value) ? _selected.value : null;
```

## Combine several sources

One box, a record input, one wire per source.

```dart
.add(nowPlaying, input: (d) => (
  station: d.onlyWhenReady(selection),          // required
  status: d.onlyWhenReady(player.status),       // required
  cover: d.whenReadyOrNull(artwork),            // optional: null until ready
))
```

Any `onlyWhenReady` that is not ready skips the whole node.

## A step from loading states (a wizard)

`outputOf` gives the phase as a value; `compute` is a priority table.

```dart
@override
AuthStep compute(AuthInput i) => switch (i) {
      _ when i.saved != null => AuthStep.authorized,
      _ when i.verify is AsyncData => AuthStep.authorized,
      _ when i.verify is AsyncLoading => AuthStep.checking,
      _ when i.verify is AsyncError => AuthStep.failed,
      _ when i.send is AsyncLoading => AuthStep.sendingCode,
      _ when i.send is AsyncData => AuthStep.waitingCode,
      _ => AuthStep.waitingPhone,
    };
// wire: (saved: d.onlyWhenReady(session), verify: d.outputOf(verify),
//        send: d.outputOf(send))
```

## Say "don't know"

If readers may wait: a `.late()` box, non-nullable output, no
`initialValue`. If they must render now: a declared fallback, or a flag
in the value.

```dart
final premium = PremiumBox.late(initialValue: Premium.closed); // fail-closed

run: (now, was) {
  if (!now.hydrated || was == null || !was.hydrated) return; // not known yet
  if (now.entitled && !was.entitled) onPremiumGained();      // a real change
}
```

## A state machine

A sealed state, a pure `next(state, event)`, one cell, one button.

```dart
PlayerPhase next(PlayerPhase s, PlayerEvent e) => switch ((s, e)) {
      (Loading(:final attempt), DeviceError()) => Loading(attempt + 1),
      (_, DeviceState(s: PlayerState.playing)) => const Playing(),
      (Playing(), UserPause()) => const Paused(StopReason.user),
      _ => s,
    };

late final phase = child<PlayerPhase>(const Idle());
void _on(PlayerEvent e) => dispatch(phase, next(phase.value, e));
```

Test `next` as a table, without a box.

## Remember an occurrence

An equal value is not published, so a repeated "event" disappears.
Store what the box remembers about it instead:

| occurrence | remember |
| --- | --- |
| the user pressed pause | why it is quiet: `StopReason?` |
| the stream failed again | failures since the last start: `int failures` |
| the device confirmed a tare | when: `DateTime? lastTare` (device time) |

## A debug switch

The switch is an input, so the whole graph follows it.

```dart
.add(premium, input: (d) => (
  entitled: d.onlyWhenReady(billing.entitled) || d.onlyWhenReady(debugPremium),
))
```

## Share a box between modules

Create it at the root, let one graph drive it, pass it to the others.

```dart
final premium = PremiumBox.late(initialValue: Premium.closed);
final purchases = buildPurchases(premium: premium); // declares and drives it
final catalog = buildCatalog(premium: premium);     // reads it in wires
final player = buildPlayer(premium: premium);       // reads it in wires
```

The driving module takes it as a required parameter. In tests, drive it
with `updateInputForTest(premium, (entitled: true))`.

## Command the outside world

A named effect, the only writer of its subsystem. `run` compares
`current` with `previous`.

```dart
.addEffect<EqState>((d) => d.onlyWhenReady(equalizer), name: 'equalizer',
    run: (now, was) {
  if (now.enabled != was?.enabled) gateway.setEqEnabled(now.enabled);
  if (!listEquals(now.bands, was?.bands)) gateway.setBands(now.bands);
})
```

## Trigger vs condition in an effect

Put the trigger in the input; read conditions of the moment inside `run`.

```dart
.addEffect<String?>((d) => d.onlyWhenReady(streamUrl), name: 'autoplay',
    run: (url, _) {
  if (url != null && player.wantsToPlay) player.play(); // checked, not wired
})
```

Wiring the play state into the input would wake the effect on every
pause.

## Feed a result back

A value the graph computes and needs back is state: an effect presses a
button, the box is read downstream.

```dart
.addEffect<Track?>((d) => d.onlyWhenReady(nowPlaying), name: 'history',
    run: (track, _) { if (track != null) history.add(track); })
// history is a box with a cell; other boxes wire to it.
```

Not for copies of another box's value: wire to that box instead.

## Connect a native device

A `MultiBox` with a cell per signal; buttons command the device; truth
comes back through `connect`.

```dart
final class PlayerBox extends MultiBox<String?> {
  PlayerBox({required this.gateway});
  final PlayerGateway gateway;
  late final status = child(PlayerStatus.paused, name: 'status');
  late final position = child(Duration.zero, name: 'position');
  @override
  void compute(String? url) {
    connect(gateway.onStatus, status);
    connect(gateway.onPosition, position);
    gateway.setSource(url);
  }
  void toggle() => gateway.toggle(); // no cell written here
}
```

A cell moves when the device reports it, not when the button is pressed.

## Decide what to show first

One box decides which interruption to show; the line order is the
priority. The UI shows it and confirms with a button.

```dart
@override
Interrupt? compute(InterruptInput i) {
  if (!i.onboarded) return null;
  if (i.session == _handled.value) return null;   // once per session
  if (i.needsRestore) return Interrupt.restore;
  if (i.deal != null && !i.premium) return Interrupt.promo;
  return null;
}
void shown(SessionId s) => _handled.value = s;     // the UI confirms
```

## Act at a moment

`clock.at(moment)` on a wire; compute the moment from delivered data,
never from `now()`.

```dart
final clock = ClockBox();
graph
  ..addMultiBox(clock)
  ..addEffect<bool>((d) {
    final at = d.onlyWhenReady(sleepTimer).fireDate;
    return at != null && d.onlyWhenReady(clock.at(at, name: 'sleep'));
  }, name: 'sleep', run: (due, _) { if (due) player.stop(); });
```

## A ticking display

Listen to `clock.every(period)` in the UI; the graph never hears it.

```dart
BoxObserver(builder: (_) {
  final now = clock.every(const Duration(seconds: 1)).requireValue;
  return Text(format(fireDate.difference(now)));
});
```

## Wait until the input settles

`DebounceBox(window)` between the source and its readers.

```dart
final track = DebounceBox<TrackInfo?>(const Duration(seconds: 1));
graph
  ..add(track, input: (d) => d.onlyWhenReady(player.streamTrack))
  ..addEffect<TrackInfo?>((d) => d.onlyWhenReady(track),
      name: 'artwork', run: (t, _) => artwork.lookup(t));
```

Before adding one, check the cheaper answers:

1. **The same value again?** Already dropped: equal values are not
   published.
2. **Different pieces of one question?** Fix the key: artwork keyed by
   `(title, artist)` is not refetched when a cover URL arrives later.
3. **Does my own command change what I read?** That is an oscillating
   effect ([anti-pattern 8](ANTI-PATTERNS.md#8-an-oscillating-effect));
   a delay only slows it.
4. **Is the flicker harmless?** The graph always ends in the right
   state; two idempotent calls need nothing.

## Ignore short flickers

`HysteresisBox(on:, off:)` on a `bool`.

```dart
final spinner = HysteresisBox(on: const Duration(milliseconds: 300));
final analyzer = HysteresisBox(off: const Duration(seconds: 3));
graph
  ..add(spinner, input: (d) => d.onlyWhenReady(player.status) == PlayerStatus.loading)
  ..add(analyzer, input: (d) => d.onlyWhenReady(player.status) == PlayerStatus.playing);
```

## Read a box in plain code

| need | read |
| --- | --- |
| the value or nothing | `box.valueOrNull` |
| the value, or an error if not ready | `box.requireValue` |
| wait for the first value | `await box.firstReady` |

## A snapshot read inside compute

Rare: a value you deliberately do not want to react to. Say so.

```dart
final rate = BoxHooks.untracked(() => rates.valueOrNull);
```

If the box should react to it, wire it into the input instead.

## Run a graph once for a result

```dart
final answer = await Pipeline.builder<void, Answer>()
    .add(classify, retry: 2)
    .add(enrich, onFailure: FailurePolicy.skip)
    .add(retrieve, input: (d) => (
          query: d.onlyWhenReady(classify),
          extra: d.whenReadyOrNull(enrich)))
    .add(answerBox, input: (d) => d.onlyWhenReady(retrieve))
    .build(result: answerBox, timeout: const Duration(seconds: 30))
    .start();
```

## Test a box

A box is a plain object: construct it, press buttons, read the output.
`updateInputForTest` gives a `.late()` box its input.

```dart
test('select keeps a known station', () {
  final box = SelectedStationBox.late();
  updateInputForTest(box, [a, b]);
  box.select(b);
  expect(box.value, b);
});
```

## Test a graph

Build it, change a source, `await graph.settled()`, assert.

```dart
test('premium unlocks the stream', () async {
  final graph = buildPlayer(fakeGateway, selection: sel, premium: premium);
  updateInputForTest(premium, (entitled: true));
  await graph.settled();
  expect(fakeGateway.source, station.premiumUrl);
  graph.dispose();
});
```

`settled()` does not wait for async computes in flight; await them, then
`settled()` again.

## Test with time

Build the clock and the graph inside `fakeAsync`; `elapse` fires timers
and the pumps they cause.

```dart
fakeAsync((async) {
  final clock = ClockBox(now: () => async.getClock(start).now());
  final graph = buildTimerGraph(clock);
  async.flushMicrotasks();
  async.elapse(const Duration(minutes: 30));
  expect(player.stopped, isTrue);
  graph.dispose();
});
```

## Test UI with fake boxes

```dart
BoxProvider.overrides(
  overrides: [BoxOverride.of<CounterBox>(FakeCounterBox())],
  child: const CounterScreen(),
);
```
