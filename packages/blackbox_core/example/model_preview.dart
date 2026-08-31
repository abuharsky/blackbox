// EXPERIMENTAL — the docs/MODEL.md model on four real scenarios:
//
//   1. ThemeBox    — store: persisted memory, survives "restart"
//   2. CounterBox  — memory + context: step comes from the graph
//   3. CartBox     — slot per user: persistFor + user switch
//   4. MenuBox     — cached compute: TTL + disk slot (food-delivery menu)
//
// Run: dart run example/model_preview.dart

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:blackbox/blackbox.dart';

// ═══════════════════════════════════════════════════════════════════════
// 1. Store — no input. Shows what it remembers; memory is persisted.
// ═══════════════════════════════════════════════════════════════════════

class ThemeBox extends NoInputBox<String> {
  late final _theme = state('light', persist: 'theme');

  @override
  String compute() => _theme.value;

  void toggle() => _theme.value = _theme.value == 'light' ? 'dark' : 'light';
}

// ═══════════════════════════════════════════════════════════════════════
// 2. Memory + context. The step arrives from the graph; the button reads
//    `input` directly — no caching input into fields.
// ═══════════════════════════════════════════════════════════════════════

class StepBox extends NoInputBox<int> {
  late final _step = state(1);

  @override
  int compute() => _step.value;

  void set(int v) => _step.value = v;
}

class CounterBox extends Box<int, int> {
  late final _count = state(0);

  CounterBox({required int input}) : super(input);

  @override
  int compute(int step) => _count.value;

  void inc() => _count.value += input;
}

// ═══════════════════════════════════════════════════════════════════════
// 3. Slot per user. The cart's memory lives in a per-user slot; switching
//    the user re-slots the cell — Alice's items can't leak to Bob.
// ═══════════════════════════════════════════════════════════════════════

class SessionBox extends NoInputBox<String> {
  late final _user = state('alice');

  @override
  String compute() => _user.value;

  void login(String name) => _user.value = name;
}

class CartBox extends Box<String, List<String>> {
  late final _items = state<List<String>>(
    const [],
    persistFor: (user) => 'cart:$user',
    codec: const _StringListCodec(),
  );

  CartBox({required String input}) : super(input);

  @override
  List<String> compute(String user) => _items.value;

  void add(String item) => _items.value = [..._items.value, item];
}

// ═══════════════════════════════════════════════════════════════════════
// 4. Cached compute — the food-delivery menu. Not memory: the server can
//    always give it back. TTL keeps it fresh; the disk slot is only an
//    accelerator for cold start. One declaration, no mixins.
// ═══════════════════════════════════════════════════════════════════════

class MenuBox extends NoInputCachedBox<String> {
  int fetches = 0;

  @override
  Cache<void, String> get cache =>
      const Cache(ttl: Duration(minutes: 5), persist: 'menu');

  @override
  Future<String> fetch() async {
    fetches++;
    return 'menu v$fetches (fetched from api)';
  }
}

final class _StringListCodec extends PersistentCodec<List<String>> {
  const _StringListCodec();
  @override
  Object? encode(List<String> value) => value;
  @override
  List<String> decode(Object? stored) =>
      (stored as List<dynamic>).cast<String>();
}

final class _MemoryStore implements PersistentStore {
  final Map<String, Object?> values = {};
  @override
  Object? read(String key) => values[key];
  @override
  void write(String key, Object? value) => values[key] = value;
  @override
  void delete(String key) => values.remove(key);
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

Future<void> main() async {
  BlackboxPersistence.init(_MemoryStore());

  // ── 1. Theme: persist + "restart" ────────────────────────────────────
  print('— theme —');
  final theme = ThemeBox();
  print(theme.value); // light
  theme.toggle();
  print(theme.value); // dark

  final themeAfterRestart = ThemeBox(); // "restart": new box, same slot
  print('after restart: ${themeAfterRestart.value}'); // dark

  // ── 2. Counter with graph-driven step ────────────────────────────────
  print('— counter —');
  final step = StepBox();
  final counter = CounterBox(input: 1);

  final graph = Graph.builder()
      .add(step)
      .add(counter, input: (d) => d.onlyWhenReady<int>(step))
      .build(start: true);
  await pump();

  counter.inc();
  counter.inc();
  print(counter.value); // 2  (step 1)

  step.set(5);
  await pump(); // graph delivers the new step
  counter.inc();
  print(counter.value); // 7  (step 5)

  // ── 3. Cart per user ─────────────────────────────────────────────────
  print('— cart —');
  final session = SessionBox();
  final cart = CartBox(input: 'alice');

  final shopGraph = Graph.builder()
      .add(session)
      .add(cart, input: (d) => d.onlyWhenReady<String>(session))
      .build(start: true);
  await pump();

  cart.add('apple');
  cart.add('bread');
  print('alice: ${cart.value}'); // [apple, bread]

  session.login('bob');
  await pump();
  print('bob:   ${cart.value}'); // []  (fresh slot, no leak)

  cart.add('milk');
  print('bob:   ${cart.value}'); // [milk]

  session.login('alice');
  await pump();
  print('alice: ${cart.value}'); // [apple, bread]  (restored)

  // ── 4. Menu: cached compute with TTL + disk fallback ─────────────────
  print('— menu —');
  final menu = MenuBox();
  await pump();
  print((menu.output as AsyncData<String>).value); // menu v1 (fetched)

  // "Restart" while the cache is fresh: instant from disk, no fetch.
  final menuRestart = MenuBox();
  print('after restart: '
      '${(menuRestart.output as AsyncData<String>).value}'); // menu v1
  await pump();
  print('fetches after fresh restart: ${menuRestart.fetches}'); // 0

  // Pull-to-refresh bypasses the TTL.
  await menuRestart.refresh();
  print('fetches after pull-to-refresh: ${menuRestart.fetches}'); // 1

  graph.dispose();
  shopGraph.dispose();
}
