import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

Future<void> flushMicrotasks([int times = 6]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// "Menu": expensive async compute, cached with TTL + disk slot.
final class MenuBox extends NoInputAsyncBox<String> {
  int computeCalls = 0;
  String nextValue = 'menu-1';

  @override
  Cache<void, String> get cache =>
      const Cache(ttl: Duration(minutes: 5), persist: 'menu');

  @override
  Future<String> compute(String? previous) async {
    computeCalls++;
    return nextValue;
  }
}

/// In-memory TTL only — no disk slot.
final class RatesBox extends NoInputAsyncBox<int> {
  int computeCalls = 0;

  @override
  Cache<void, int> get cache => const Cache(ttl: Duration(minutes: 1));

  @override
  Future<int> compute(int? previous) async {
    computeCalls++;
    return computeCalls * 100;
  }
}

/// Slot per input: menu per restaurant.
final class RestaurantMenuBox extends AsyncBox<String, String> {
  int computeCalls = 0;

  RestaurantMenuBox({required String input}) : super(input);

  @override
  Cache<String, String> get cache => Cache(
        ttl: const Duration(minutes: 5),
        persistFor: (id) => 'menu:$id',
      );

  @override
  Future<String> compute(String id, String? previous) async {
    computeCalls++;
    return 'menu-of-$id';
  }
}

/// Forced refresh shows loading when staleWhileRefresh is off.
final class NoStaleBox extends NoInputAsyncBox<String> {
  @override
  Cache<void, String> get cache => const Cache(
        ttl: Duration(minutes: 5),
        persist: 'nostale',
        staleWhileRefresh: false,
      );

  @override
  Future<String> compute(String? previous) async => 'fresh';
}

/// Plain async box — no cache declaration.
final class PlainBox extends NoInputAsyncBox<int> {
  int computeCalls = 0;

  @override
  Future<int> compute(int? previous) async {
    computeCalls++;
    return computeCalls;
  }
}

final class MemStore implements PersistentStore {
  final Map<String, Object?> values = {};
  @override
  Object? read(String key) => values[key];
  @override
  void write(String key, Object? value) => values[key] = value;
  @override
  void delete(String key) => values.remove(key);
}

void main() {
  late MemStore store;
  var currentTime = DateTime(2026, 1, 1, 12, 0, 0);

  void advance(Duration d) => currentTime = currentTime.add(d);

  Map<String, Object?> envelope(String v, DateTime at) => {
        'v': v,
        'ts': at.millisecondsSinceEpoch,
      };

  setUp(() {
    BlackboxPersistence.reset();
    store = MemStore();
    BlackboxPersistence.init(store);
    currentTime = DateTime(2026, 1, 1, 12, 0, 0);
    BlackboxPersistence.now = () => currentTime;
  });

  tearDown(BlackboxPersistence.reset);

  group('Cache with persist (the menu scenario)', () {
    test('first boot: computes, emits, saves to the slot', () async {
      final box = MenuBox();
      await flushMicrotasks();

      expect(box.computeCalls, 1);
      expect((box.output as AsyncData<String>).value, 'menu-1');
      final raw = store.values['menu'] as Map<String, Object?>;
      expect(raw['v'], 'menu-1');
    });

    test('fresh restart: instant value from disk, no fetch', () async {
      store.values['menu'] =
          envelope('menu-cached', currentTime.subtract(const Duration(minutes: 1)));

      final box = MenuBox();
      // Value is available synchronously — no loading state.
      expect((box.output as AsyncData<String>).value, 'menu-cached');
      await flushMicrotasks();
      expect(box.computeCalls, 0, reason: 'cache is fresh — no refetch');
    });

    test('expired restart: stale shown instantly, refreshed in background',
        () async {
      store.values['menu'] =
          envelope('menu-old', currentTime.subtract(const Duration(minutes: 10)));

      final box = MenuBox()..nextValue = 'menu-new';
      // Stale value visible immediately (no flicker)...
      expect((box.output as AsyncData<String>).value, 'menu-old');

      await flushMicrotasks();
      // ...then the background refresh lands and re-saves.
      expect(box.computeCalls, 1);
      expect((box.output as AsyncData<String>).value, 'menu-new');
      final raw = store.values['menu'] as Map<String, Object?>;
      expect(raw['v'], 'menu-new');
    });

    test('regular recompute returns cached value without fetching', () async {
      final box = MenuBox();
      await flushMicrotasks();
      expect(box.computeCalls, 1);

      // TTL not reached: reads don't refetch.
      box.output;
      await flushMicrotasks();
      expect(box.computeCalls, 1);
    });

    test('refresh() bypasses TTL; invalidateCache() clears the slot',
        () async {
      final box = MenuBox();
      await flushMicrotasks();
      expect(box.computeCalls, 1);

      box.nextValue = 'menu-2';
      await box.refresh();
      expect(box.computeCalls, 2);
      expect((box.output as AsyncData<String>).value, 'menu-2');

      box.nextValue = 'menu-3';
      await box.invalidateCache();
      expect(box.computeCalls, 3);
      expect((store.values['menu'] as Map<String, Object?>)['v'], 'menu-3');
    });

    test('expiry triggers refresh on access', () async {
      final box = MenuBox();
      await flushMicrotasks();
      expect(box.computeCalls, 1);

      advance(const Duration(minutes: 6));
      box.nextValue = 'menu-2';
      box.output; // access after expiry → deferred background refresh
      await flushMicrotasks();

      expect(box.computeCalls, 2);
      expect((box.output as AsyncData<String>).value, 'menu-2');
    });
  });

  group('Cache in-memory only', () {
    test('TTL works without a disk slot', () async {
      final box = RatesBox();
      await flushMicrotasks();
      expect(box.computeCalls, 1);

      box.output;
      await flushMicrotasks();
      expect(box.computeCalls, 1, reason: 'fresh — no refetch');

      advance(const Duration(minutes: 2));
      box.output;
      await flushMicrotasks();
      expect(box.computeCalls, 2, reason: 'expired — background refetch');
      expect(store.values, isEmpty, reason: 'nothing persisted');
    });
  });

  group('Cache with persistFor (slot per input)', () {
    test('input change re-slots: no leak, restore without refetch', () async {
      // Pre-fill both restaurant slots with fresh values.
      store.values['menu:r1'] = envelope('menu-r1-cached', currentTime);
      store.values['menu:r2'] = envelope('menu-r2-cached', currentTime);

      final box = RestaurantMenuBox(input: 'r1');
      await flushMicrotasks();
      expect(box.computeCalls, 0);
      expect((box.output as AsyncData<String>).value, 'menu-r1-cached');

      updateAsyncInputForTest(box, 'r2');
      await flushMicrotasks();
      expect(box.computeCalls, 0, reason: 'r2 slot is fresh too');
      expect((box.output as AsyncData<String>).value, 'menu-r2-cached');

      // r1 slot untouched by the switch.
      expect((store.values['menu:r1'] as Map<String, Object?>)['v'],
          'menu-r1-cached');
    });

    test('empty new slot fetches and saves under the new key', () async {
      final box = RestaurantMenuBox(input: 'r1');
      await flushMicrotasks();
      expect(box.computeCalls, 1);

      updateAsyncInputForTest(box, 'r2');
      await flushMicrotasks();
      expect(box.computeCalls, 2);
      expect((store.values['menu:r2'] as Map<String, Object?>)['v'],
          'menu-of-r2');
      expect((store.values['menu:r1'] as Map<String, Object?>)['v'],
          'menu-of-r1');
    });
  });

  group('staleWhileRefresh: false', () {
    test('forced refresh emits loading first', () async {
      final box = NoStaleBox();
      await flushMicrotasks();

      final states = <String>[];
      box.listen((o) {
        states.add(switch (o) {
          AsyncLoading<String>() => 'loading',
          AsyncData<String>() => 'data',
          AsyncError<String>() => 'error',
          _ => '?',
        });
      }, skipFirst: true);

      await box.refresh();
      expect(states.first, 'loading');
      expect(states.last, 'data');
    });
  });

  group('No cache declaration', () {
    test('refresh() on a plain async box just recomputes', () async {
      final box = PlainBox();
      await flushMicrotasks();
      expect(box.computeCalls, 1);

      await box.refresh();
      expect(box.computeCalls, 2);
    });
  });
}
