import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

final class _MemoryStore implements PersistentStore {
  final Map<String, Object?> _values = <String, Object?>{};

  @override
  Object? read(String key) => _values[key];

  @override
  void write(String key, Object? value) {
    _values[key] = value;
  }

  @override
  void delete(String key) {
    _values.remove(key);
  }
}

/// Sync box with TTL cache backed by an async fetch.
final class _CountBox extends Box<String, int>
    with ManagedCache<String, int> {
  final Duration ttl;
  final Map<String, Completer<int>> _completers = <String, Completer<int>>{};
  int fetchCalls = 0;

  _CountBox(super.input, {required this.ttl})
      : super(initialValue: 0);

  Completer<int> completerFor(String input) =>
      _completers.putIfAbsent(input, () => Completer<int>());

  @override
  Duration get cacheTtl => ttl;

  @override
  Future<int> fetch(String input) {
    fetchCalls++;
    return completerFor(input).future;
  }
}

/// Sync box whose fetch throws on demand — for error path testing.
final class _FailingBox extends Box<String, int>
    with ManagedCache<String, int> {
  final Duration ttl;
  int fetchCalls = 0;
  Object? error;

  _FailingBox(super.input, {required this.ttl})
      : super(initialValue: -1);

  @override
  Duration get cacheTtl => ttl;

  @override
  Future<int> fetch(String input) async {
    fetchCalls++;
    final e = error;
    if (e != null) throw e;
    return 100;
  }
}

/// Sync box composing Persisted + ManagedCache.
///
/// `initialValue` is only used when no disk-cached value exists. Pass
/// `null` (default) to let the disk value dominate on boot.
final class _PersistedCountBox extends Box<String, int>
    with Persisted<String, int>, ManagedCache<String, int> {
  final Duration ttl;
  int fetchCalls = 0;
  int nextValue;

  _PersistedCountBox(
    super.input, {
    required this.ttl,
    this.nextValue = 0,
    int initialValue = 0,
  }) : super(initialValue: initialValue);

  @override
  String persistKeyFor(String input) => 'count:$input';

  @override
  Duration get cacheTtl => ttl;

  @override
  Future<int> fetch(String input) async {
    fetchCalls++;
    return nextValue;
  }
}

/// Box with no initialValue — triggers StateError.
final class _NoInitialBox extends Box<String, int>
    with ManagedCache<String, int> {
  _NoInitialBox(super.input);

  @override
  Duration get cacheTtl => const Duration(minutes: 1);

  @override
  Future<int> fetch(String input) async => 0;
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

  group('ManagedCache (sync)', () {
    test('starts with initialValue, then updates when fetch completes',
        () async {
      final box = _CountBox('u1', ttl: const Duration(minutes: 1));

      final seen = <int>[];
      final cancel = box.listen((o) => seen.add((o as SyncData<int>).value));

      expect(seen.single, 0);
      expect(box.fetchCalls, 1);

      box.completerFor('u1').complete(42);
      await _flush();

      expect(box.value, 42);
      expect(seen, [0, 42]);

      cancel();
    });

    test('throws StateError when no initialValue is provided', () {
      expect(() => _NoInitialBox('x'), throwsStateError);
    });

    test('fresh cache is not refetched on access', () async {
      final now = DateTime(2026, 4, 9, 10);
      BlackboxPersistence.now = () => now;

      final box = _CountBox('u1', ttl: const Duration(minutes: 1));
      box.completerFor('u1').complete(5);
      await _flush();
      expect(box.value, 5);
      expect(box.fetchCalls, 1);

      // read output — fresh, no refresh
      box.output;
      box.output;
      await _flush();
      expect(box.fetchCalls, 1);
    });

    test('expired cache triggers background refresh on access', () async {
      var now = DateTime(2026, 4, 9, 10);
      BlackboxPersistence.now = () => now;

      final box = _CountBox('u1', ttl: const Duration(seconds: 30));
      box.completerFor('u1').complete(5);
      await _flush();
      expect(box.value, 5);
      expect(box.fetchCalls, 1);

      now = DateTime(2026, 4, 9, 10, 1); // advance past TTL

      // Replace the completer so the next fetch has a fresh future to await
      final pending = Completer<int>();
      box._completers['u1'] = pending;

      // accessing output while expired triggers a new fetch
      box.output;
      await _flush();
      expect(box.fetchCalls, 2);

      pending.complete(77);
      await _flush();
      expect(box.value, 77);
    });

    test('refresh() forces a new fetch and updates value', () async {
      final box = _CountBox('u1', ttl: const Duration(hours: 1));
      box.completerFor('u1').complete(5);
      await _flush();
      expect(box.value, 5);
      expect(box.fetchCalls, 1);

      // Replace completer for next fetch
      final pending = Completer<int>();
      box._completers['u1'] = pending;

      final task = box.refresh();
      pending.complete(99);
      await task;
      await _flush();

      expect(box.value, 99);
      expect(box.fetchCalls, 2);
    });

    test('concurrent refresh() returns same Future and calls fetch once',
        () async {
      final box = _CountBox('u1', ttl: const Duration(hours: 1));
      box.completerFor('u1').complete(1);
      await _flush();

      final pending = Completer<int>();
      box._completers['u1'] = pending;

      final f1 = box.refresh();
      final f2 = box.refresh();
      expect(identical(f1, f2), isTrue);

      pending.complete(42);
      await f1;
      expect(box.fetchCalls, 2);
    });

    test('invalidateCache() clears TTL and refetches', () async {
      var now = DateTime(2026, 4, 9, 10);
      BlackboxPersistence.now = () => now;

      final box = _CountBox('u1', ttl: const Duration(hours: 1));
      box.completerFor('u1').complete(5);
      await _flush();
      expect(box.lastFetchedAt, now);

      final pending = Completer<int>();
      box._completers['u1'] = pending;

      final task = box.invalidateCache();
      pending.complete(99);
      await task;
      await _flush();

      expect(box.value, 99);
      expect(box.fetchCalls, 2);
    });

    test('input change triggers new fetch', () async {
      final box = _CountBox('u1', ttl: const Duration(hours: 1));
      box.completerFor('u1').complete(1);
      await _flush();

      expect(box.value, 1);
      expect(box.fetchCalls, 1);

      box.completerFor('u2').complete(2);
      updateInputForTest(box, 'u2');
      await _flush();

      expect(box.value, 2);
      expect(box.fetchCalls, 2);
    });

    test('fetch error preserves previous value (fail-open)', () async {
      var now = DateTime(2026, 4, 9, 10);
      BlackboxPersistence.now = () => now;

      final box = _FailingBox('u1', ttl: const Duration(hours: 1));
      await _flush();

      // Initial fetch succeeds (no error yet), value = 100
      expect(box.value, 100);
      expect(box.fetchCalls, 1);

      // Next refresh fails — previous value is kept
      box.error = Exception('network down');
      await box.refresh();
      await _flush();

      expect(box.value, 100);
      expect(box.fetchCalls, 2);
      // TTL stamped — prevents tight retry loop
      expect(box.lastFetchedAt, isNotNull);
    });

    test('composition with Persisted saves fetched value to store', () async {
      final store = _MemoryStore();
      final now = DateTime(2026, 4, 9, 12);
      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _PersistedCountBox('u1',
          ttl: const Duration(hours: 1), nextValue: 7);
      await _flush();

      expect(box.value, 7);
      expect(box.fetchCalls, 1);

      final raw = store.read('count:u1') as Map;
      expect(raw['v'], 7);
    });

    test('composition with Persisted restores value from store on boot',
        () async {
      final store = _MemoryStore();
      final now = DateTime(2026, 4, 9, 12);
      store.write('count:u1', {
        'v': 33,
        'ts': now.subtract(const Duration(seconds: 10)).millisecondsSinceEpoch,
      });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _PersistedCountBox('u1',
          ttl: const Duration(hours: 1), nextValue: 99);

      // Value restored immediately from disk — no fetch yet
      expect(box.value, 33);
      expect(box.fetchCalls, 0);

      // Cache is fresh — no refresh on access
      box.output;
      await _flush();
      expect(box.fetchCalls, 0);
    });
  });
}

