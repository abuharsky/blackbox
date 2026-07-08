// EXPERIMENTAL — the docs/MODEL.md model on three real scenarios:
//
//   1. ThemeBox    — store: persisted memory, survives "restart"
//   2. CounterBox  — memory + context: step comes from the graph
//   3. CartBox     — slot per user: persistFor + user switch
//
// Run: dart run example/model_preview.dart

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:blackbox/blackbox.dart';

// ═══════════════════════════════════════════════════════════════════════
// 1. Store — no input. Shows what it remembers; memory is persisted.
// ═══════════════════════════════════════════════════════════════════════

class ThemeBox extends NoInputBox<String> {
  late final theme = state('light', persist: 'theme');

  @override
  String compute(String? previous) => theme.value;

  void toggle() => theme.value = theme.value == 'light' ? 'dark' : 'light';
}

// ═══════════════════════════════════════════════════════════════════════
// 2. Memory + context. The step arrives from the graph; the button reads
//    `input` directly — no caching input into fields.
// ═══════════════════════════════════════════════════════════════════════

class StepBox extends NoInputBox<int> {
  late final step = state(1);

  @override
  int compute(int? previous) => step.value;

  void set(int v) => step.value = v;
}

class CounterBox extends Box<int, int> {
  late final count = state(0);

  CounterBox({required int input}) : super(input);

  @override
  int compute(int step, int? previous) => count.value;

  void inc() => count.value += input;
}

// ═══════════════════════════════════════════════════════════════════════
// 3. Slot per user. The cart's memory lives in a per-user slot; switching
//    the user re-slots the cell — Alice's items can't leak to Bob.
// ═══════════════════════════════════════════════════════════════════════

class SessionBox extends NoInputBox<String> {
  late final user = state('alice');

  @override
  String compute(String? previous) => user.value;

  void login(String name) => user.value = name;
}

class CartBox extends Box<String, List<String>> {
  late final items = state<List<String>>(
    const [],
    persistFor: (user) => 'cart:$user',
    codec: const _StringListCodec(),
  );

  CartBox({required String input}) : super(input);

  @override
  List<String> compute(String user, List<String>? previous) => items.value;

  void add(String item) => items.value = [...items.value, item];
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
      .add(counter, input: (d) => d.whenReady<int>(step))
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
      .add(cart, input: (d) => d.whenReady<String>(session))
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

  graph.dispose();
  shopGraph.dispose();
}
