import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

/// AsyncBox with in-memory TTL cache (no AsyncPersisted).
final class _InMemoryCachedBox extends AsyncBox<String, int>
    with AsyncManagedCache<String, int> {
  final Duration ttl;
  final Map<String, Completer<int>> _completers = <String, Completer<int>>{};
  int computeCalls = 0;

  _InMemoryCachedBox(super.input, {required this.ttl, super.initialValue});

  Completer<int> completerFor(String input) =>
      _completers.putIfAbsent(input, () => Completer<int>());

  @override
  Duration get cacheTtl => ttl;

  @override
  Future<int> compute(String input, int? previous) {
    computeCalls++;
    return completerFor(input).future;
  }
}

Future<void> _flush([int times = 5]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  tearDown(() {
    BlackboxPersistence.reset();
  });

  group('AsyncManagedCache (standalone, no persistence)', () {
    test('cold start without initialValue emits loading then data', () async {
      final box = _InMemoryCachedBox('u1', ttl: const Duration(minutes: 1));

      final seen = <AsyncOutput<int>>[];
      final cancel = box.listen((o) => seen.add(o as AsyncOutput<int>));

      expect(seen.first, isA<AsyncLoading<int>>());

      box.completerFor('u1').complete(42);
      await _flush();

      expect(seen.last, isA<AsyncData<int>>());
      expect((seen.last as AsyncData<int>).value, 42);
      expect(box.computeCalls, 1);

      cancel();
    });

    test('with initialValue skips initial compute and starts TTL now',
        () async {
      final now = DateTime(2026, 4, 9, 10);
      BlackboxPersistence.now = () => now;

      final box = _InMemoryCachedBox('u1',
          ttl: const Duration(minutes: 10), initialValue: 7);
      await _flush();

      expect(box.output, isA<AsyncData<int>>());
      expect((box.output as AsyncData<int>).value, 7);
      expect(box.computeCalls, 0);
      expect(box.lastFetchedAt, now);
    });

    test('fresh cache is not refetched on access', () async {
      var now = DateTime(2026, 4, 9, 10);
      BlackboxPersistence.now = () => now;

      final box = _InMemoryCachedBox('u1', ttl: const Duration(minutes: 5));
      box.completerFor('u1').complete(5);
      await _flush();
      expect(box.computeCalls, 1);

      // Advance a little but not past TTL
      now = DateTime(2026, 4, 9, 10, 2);
      box.output;
      await _flush();
      expect(box.computeCalls, 1);
    });

    test('expired cache triggers refresh on access', () async {
      var now = DateTime(2026, 4, 9, 10);
      BlackboxPersistence.now = () => now;

      final box = _InMemoryCachedBox('u1', ttl: const Duration(seconds: 30));
      box.completerFor('u1').complete(5);
      await _flush();
      expect(box.computeCalls, 1);

      now = DateTime(2026, 4, 9, 10, 1); // past TTL

      // Install new completer for the second compute
      box._completers['u1'] = Completer<int>();

      box.output;
      await _flush();
      expect(box.computeCalls, 2);

      box.completerFor('u1').complete(77);
      await _flush();
      expect(box.valueOrNull, 77);
    });

    test('refresh() forces a new compute', () async {
      final box = _InMemoryCachedBox('u1', ttl: const Duration(hours: 1));
      box.completerFor('u1').complete(5);
      await _flush();

      box._completers['u1'] = Completer<int>();
      final task = box.refresh();
      box.completerFor('u1').complete(99);
      await task;

      expect(box.valueOrNull, 99);
      expect(box.computeCalls, 2);
    });

    test('invalidateCache() clears TTL and refetches', () async {
      var now = DateTime(2026, 4, 9, 10);
      BlackboxPersistence.now = () => now;

      final box = _InMemoryCachedBox('u1', ttl: const Duration(hours: 1));
      box.completerFor('u1').complete(5);
      await _flush();
      expect(box.lastFetchedAt, now);

      box._completers['u1'] = Completer<int>();
      final task = box.invalidateCache();
      box.completerFor('u1').complete(42);
      await task;

      expect(box.valueOrNull, 42);
      expect(box.computeCalls, 2);
    });

    test('lastFetchedAt stamps on successful fetch', () async {
      var now = DateTime(2026, 4, 9, 10);
      BlackboxPersistence.now = () => now;

      final box = _InMemoryCachedBox('u1', ttl: const Duration(hours: 1));
      expect(box.lastFetchedAt, isNull);

      box.completerFor('u1').complete(5);
      await _flush();

      expect(box.lastFetchedAt, now);
    });
  });
}
