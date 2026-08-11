# blackbox_flutter

Flutter bindings for [blackbox](https://pub.dev/packages/blackbox) —
state management with one law: `output = compute(input, state)`.

This package adds the three things a Flutter app needs on top of the
pure-Dart core:

- **`BoxObserver`** — rebuilds a widget when the boxes it *actually read*
  change (MobX-style tracking, no manual subscriptions);
- **`BoxProvider`** + **`context.box<T>()`** — delivery down the tree;
- **`SharedPrefsStore`** — persistence backend for `state(persist:)`
  cells and `Cache(persist:)` on top of `shared_preferences`.

## Setup

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPrefsStore.preload();      // persistence backend, once

  final app = createApp(...);            // your graph — pure Dart
  runApp(BoxProvider.multi(
    boxes: app.boxes,              // every declared box, one line
    child: const App(),
  ));
}
```

## Reading boxes — granularity for free

`BoxObserver` subscribes to exactly what the builder reads. A progress
bar ticking five times a second never rebuilds the track title:

```dart
final player = context.box<PlayerBox>();

BoxObserver(builder: (_) => Text(player.track.value?.title ?? '—'));
BoxObserver(builder: (_) => ProgressBar(at: player.position.value));
BoxObserver(builder: (_) => PlayButton(
  playing: player.status.value == PlayerStatus.playing,
  onTap: player.toggle,
));
```

The whole app router is a switch over one box:

```dart
BoxObserver(builder: (context) =>
  switch (context.box<AppPhaseBox>().value) {
    AppLoadingPhase() => const SplashScreen(),
    OnboardingPhase() => const OnboardingScreen(),
    HomePhase(:final config) => HomeScreen(config: config),
  });
```

## Testing — swap boxes by type

```dart
BoxProvider.overrides(
  overrides: [BoxOverride.of<CounterBox>(mockCounter)],
  child: widgetUnderTest,
);
```

`BoxProvider.multi` asserts on two boxes of the same runtime type —
collisions are loud, never silent.

## Non-primitive persistence

Register codecs once, before boxes are created:

```dart
await SharedPrefsStore.preload();
BlackboxPersistence.registerCodec(UserJsonCodec());
```

See the [blackbox README](https://pub.dev/packages/blackbox) for the
model, and [ARCHITECTURE.md](https://github.com/abuharsky/blackbox/blob/main/docs/ARCHITECTURE.md)
for how a whole production app is assembled.
