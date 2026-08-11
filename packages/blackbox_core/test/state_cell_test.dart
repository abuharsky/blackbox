import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

Future<void> flushMicrotasks([int times = 4]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Memory + context: count is remembered, step arrives as input.
final class CellCounterBox extends Box<int, int> {
  late final count = state(0);

  CellCounterBox({required int input}) : super(input);

  @override
  int compute(int step) => count.value;

  void inc() => count.value += input;

  void incTwiceBatched() => action(() {
        count.value++;
        count.value++;
      });
}

/// Store: persisted memory under a global key.
final class CellThemeBox extends NoInputBox<String> {
  late final theme = state('light', persist: 'theme');

  @override
  String compute() => theme.value;

  void toggle() => theme.value = theme.value == 'light' ? 'dark' : 'light';
}

/// Slot per user: cart memory lives in a per-input slot.
final class CellCartBox extends Box<String, List<String>> {
  late final items = state<List<String>>(
    const [],
    persistFor: (user) => 'cart:$user',
    codec: const StringListCodec(),
  );

  CellCartBox({required String input}) : super(input);

  @override
  List<String> compute(String user) => items.value;

  void add(String item) => items.value = [...items.value, item];
}

final class StringListCodec extends PersistentCodec<List<String>> {
  const StringListCodec();
  @override
  Object? encode(List<String> value) => value;
  @override
  List<String> decode(Object? stored) =>
      (stored as List<dynamic>).cast<String>();
}

final class SpyStore implements PersistentStore {
  final Map<String, Object?> values = {};
  int writes = 0;

  @override
  Object? read(String key) => values[key];

  @override
  void write(String key, Object? value) {
    writes++;
    values[key] = value;
  }

  @override
  void delete(String key) => values.remove(key);
}

void main() {
  group('StateCell basics (no persistence)', () {
    test('write recomputes and notifies', () {
      final box = CellCounterBox(input: 1);
      final seen = <int>[];
      box.listen((o) => seen.add((o as SyncData<int>).value), skipFirst: true);

      box.inc();
      box.inc();

      expect(box.value, 2);
      expect(seen, [1, 2]);
    });

    test('writing an equal value is a no-op', () {
      final box = CellCounterBox(input: 1);
      var emissions = 0;
      box.listen((_) => emissions++, skipFirst: true);

      box.count.value = 0; // already 0
      expect(emissions, 0);
      expect(box.value, 0);
    });

    test('update() shorthand works', () {
      final box = CellCounterBox(input: 1);
      box.count.update((v) => v + 10);
      expect(box.value, 10);
    });

    test('buttons read the current input', () {
      final box = CellCounterBox(input: 1);
      box.inc();
      expect(box.value, 1);

      updateInputForTest(box, 5); // graph delivers a new step
      box.inc();
      expect(box.value, 6);
    });

    test('input change alone does not lose memory', () {
      final box = CellCounterBox(input: 1);
      box.inc();
      updateInputForTest(box, 5);
      expect(box.value, 1, reason: 'memory is not derived from input');
    });

    test('action batches multiple writes into one emission', () {
      final box = CellCounterBox(input: 1);
      var emissions = 0;
      box.listen((_) => emissions++, skipFirst: true);

      box.incTwiceBatched();

      expect(box.value, 2);
      expect(emissions, 1);
    });
  });

  group('StateCell with persist (global slot)', () {
    late SpyStore store;

    setUp(() {
      BlackboxPersistence.reset();
      store = SpyStore();
      BlackboxPersistence.init(store);
    });

    tearDown(BlackboxPersistence.reset);

    test('first boot uses initial; writes save an envelope', () {
      final box = CellThemeBox();
      expect(box.value, 'light');

      box.toggle();

      final raw = store.values['theme'] as Map<Object?, Object?>;
      expect(raw['v'], 'dark');
      expect(raw['ts'], isA<int>());
    });

    test('disk value wins over initial on restore', () {
      CellThemeBox().toggle(); // saves 'dark'

      final restarted = CellThemeBox();
      expect(restarted.value, 'dark');
    });

    test('equal write does not hit the store', () {
      final box = CellThemeBox();
      final writesBefore = store.writes;

      box.theme.value = 'light'; // already light
      expect(store.writes, writesBefore);
    });

    test('legacy raw values (no envelope) are readable', () {
      store.values['theme'] = 'dark'; // pre-envelope format
      final box = CellThemeBox();
      expect(box.value, 'dark');
    });
  });

  group('StateCell with persistFor (slot per input)', () {
    late SpyStore store;

    setUp(() {
      BlackboxPersistence.reset();
      store = SpyStore();
      BlackboxPersistence.init(store);
    });

    tearDown(BlackboxPersistence.reset);

    test('input change re-slots: no leak, old slot intact, restore works',
        () {
      final cart = CellCartBox(input: 'alice');
      cart.add('apple');
      cart.add('bread');
      expect(cart.value, ['apple', 'bread']);

      // Switch to bob: fresh slot — Alice's items must not leak.
      updateInputForTest(cart, 'bob');
      expect(cart.value, isEmpty);

      cart.add('milk');
      expect(cart.value, ['milk']);

      // Alice's slot was not touched by bob's write.
      final aliceRaw = store.values['cart:alice'] as Map<Object?, Object?>;
      expect(aliceRaw['v'], ['apple', 'bread']);

      // Switch back: Alice's cart is restored from her slot.
      updateInputForTest(cart, 'alice');
      expect(cart.value, ['apple', 'bread']);
    });

    test('re-slot emits exactly once per input change', () {
      final cart = CellCartBox(input: 'alice');
      cart.add('apple');

      var emissions = 0;
      cart.listen((_) => emissions++, skipFirst: true);

      updateInputForTest(cart, 'bob');
      expect(emissions, 1);
    });

    test('same input does not re-slot or reset memory', () {
      final cart = CellCartBox(input: 'alice');
      cart.add('apple');

      updateInputForTest(cart, 'alice');
      expect(cart.value, ['apple']);
    });

    test('local codec override works without registry registration', () {
      // No registerCodec call anywhere — CellCartBox passes codec: inline.
      final cart = CellCartBox(input: 'alice');
      cart.add('apple');

      final restarted = CellCartBox(input: 'alice');
      expect(restarted.value, ['apple']);
    });
  });

  group('StateCell law enforcement', () {
    test('writing a cell inside compute asserts', () {
      expect(() => ComputeWritingBox(), throwsA(isA<AssertionError>()));
    });
  });

  group('StateCell lifecycle', () {
    test('writes after graph dispose do not notify', () async {
      final driver = CellThemeBoxDriver();
      final counter = CellCounterBox(input: 1);

      final g = Graph.builder()
          .add(driver)
          .add(counter, input: (d) => d.whenReady<int>(driver))
          .build();
      await flushMicrotasks();

      var emissions = 0;
      counter.listen((_) => emissions++, skipFirst: true);

      counter.inc();
      expect(emissions, 1);

      g.dispose();
      counter.inc(); // late button press after dispose
      expect(emissions, 1);
      expect(counter.value, 1, reason: 'output frozen after dispose');
    });
  });
}

/// Minimal int driver for the lifecycle test.
final class CellThemeBoxDriver extends NoInputBox<int> {
  late final v = state(1);
  @override
  int compute() => v.value;
}

/// Illegal box: compute writes a cell — must trip the law-enforcement
/// assert (compute is the only writer of output, never of state).
final class ComputeWritingBox extends NoInputBox<int> {
  late final counter = state(0);

  @override
  int compute() {
    counter.value++; // forbidden
    return counter.value;
  }
}
