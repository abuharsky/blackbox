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

final class _CachedIntBox extends AsyncBox<String, int>
    with AsyncPersisted<String, int>, ManagedCache<String, int> {
  final Map<String, Completer<int>> _completers = <String, Completer<int>>{};
  final Duration ttl;
  final bool staleWhileRefresh;
  int refreshCalls = 0;

  final String _persistKey;

  _CachedIntBox(
    super.input, {
    required String persistKey,
    required this.ttl,
    this.staleWhileRefresh = true,
  }) : _persistKey = persistKey;

  @override
  String persistKeyFor(String input) => _persistKey;

  @override
  Duration get cacheTtl => ttl;

  @override
  bool get keepStaleWhileRefresh => staleWhileRefresh;

  Completer<int> completerFor(String input) =>
      _completers.putIfAbsent(input, () => Completer<int>());

  @override
  Future<int> compute(String input, int? previous) {
    refreshCalls++;
    return completerFor(input).future;
  }
}

/// Immediate-resolve box: compute returns [_nextValue] synchronously.
/// Good for testing store updates and state transitions without Completers.
final class _ImmediateCachedBox extends AsyncBox<String, int>
    with AsyncPersisted<String, int>, ManagedCache<String, int> {
  final String _persistKey;
  final Duration ttl;
  final bool staleWhileRefresh;
  int refreshCalls = 0;
  int _nextValue;

  _ImmediateCachedBox(
    super.input, {
    required String persistKey,
    required this.ttl,
    required int nextValue,
    this.staleWhileRefresh = true,
  })  : _persistKey = persistKey,
        _nextValue = nextValue;

  set nextValue(int v) => _nextValue = v;

  @override
  String persistKeyFor(String input) => _persistKey;

  @override
  Duration get cacheTtl => ttl;

  @override
  bool get keepStaleWhileRefresh => staleWhileRefresh;

  @override
  Future<int> compute(String input, int? previous) async {
    refreshCalls++;
    return _nextValue;
  }
}

/// Box whose compute throws on demand — for error path testing.
final class _FailingCachedBox extends AsyncBox<String, int>
    with AsyncPersisted<String, int>, ManagedCache<String, int> {
  final String _persistKey;
  final Duration ttl;
  int refreshCalls = 0;
  Object? _error;

  _FailingCachedBox(
    super.input, {
    required String persistKey,
    required this.ttl,
  }) : _persistKey = persistKey;

  set error(Object? e) => _error = e;

  @override
  String persistKeyFor(String input) => _persistKey;

  @override
  Duration get cacheTtl => ttl;

  @override
  Future<int> compute(String input, int? previous) async {
    refreshCalls++;
    final e = _error;
    if (e != null) throw e;
    return previous ?? -1;
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

  // ---------------------------------------------------------------------------
  // Existing tests
  // ---------------------------------------------------------------------------

  group('ManagedCache', () {
    test('starts from cached value without loading when cache is fresh', () {
      final now = DateTime(2026, 4, 8, 12);
      final store = _MemoryStore()
        ..write('user:1', {
          'v': 10,
          'ts':
              now.subtract(const Duration(seconds: 30)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _CachedIntBox(
        '1',
        persistKey: 'user:1',
        ttl: const Duration(minutes: 1),
      );

      final seen = <AsyncOutput<int>>[];
      final cancel = box.listenAsync(seen.add);

      expect(seen, hasLength(1));
      expect(seen.single, isA<AsyncData<int>>());
      expect((seen.single as AsyncData<int>).value, 10);
      expect(box.refreshCalls, 0);

      cancel();
    });

    test('refreshes stale cache in background without loading by default',
        () async {
      final now = DateTime(2026, 4, 8, 12);
      final store = _MemoryStore()
        ..write('user:1', {
          'v': 10,
          'ts': now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _CachedIntBox(
        '1',
        persistKey: 'user:1',
        ttl: const Duration(minutes: 1),
      );

      final seen = <AsyncOutput<int>>[];
      final cancel = box.listenAsync(seen.add);

      expect(seen.first, isA<AsyncData<int>>());
      expect((seen.first as AsyncData<int>).value, 10);

      await Future<void>.delayed(Duration.zero);

      expect(box.refreshCalls, 1);
      expect(seen.whereType<AsyncLoading<int>>(), isEmpty);

      box.completerFor('1').complete(20);
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, isA<AsyncData<int>>());
      expect((seen.last as AsyncData<int>).value, 20);

      cancel();
    });

    test('can emit loading while refreshing stale cache', () async {
      final now = DateTime(2026, 4, 8, 12);
      final store = _MemoryStore()
        ..write('user:1', {
          'v': 10,
          'ts': now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _CachedIntBox(
        '1',
        persistKey: 'user:1',
        ttl: const Duration(minutes: 1),
        staleWhileRefresh: false,
      );

      final seen = <AsyncOutput<int>>[];
      final cancel = box.listenAsync(seen.add);

      expect(seen.first, isA<AsyncLoading<int>>());
      expect((seen.first as AsyncLoading<int>).previousData, 10);
      expect(box.refreshCalls, 1);

      box.completerFor('1').complete(20);
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, isA<AsyncData<int>>());
      expect((seen.last as AsyncData<int>).value, 20);

      cancel();
    });

    test('deduplicates stale refresh while one is already queued', () async {
      final now = DateTime(2026, 4, 8, 12);
      final store = _MemoryStore()
        ..write('user:1', {
          'v': 10,
          'ts': now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _CachedIntBox(
        '1',
        persistKey: 'user:1',
        ttl: const Duration(minutes: 1),
      );

      expect(box.output, isA<AsyncData<int>>());
      expect(box.output, isA<AsyncData<int>>());

      await Future<void>.delayed(Duration.zero);

      expect(box.refreshCalls, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Data update scenarios
  // ---------------------------------------------------------------------------

  group('ManagedCache data updates', () {
    // ---- manual refresh() ----

    test('refresh() on fresh cache calls compute and updates value', () async {
      final now = DateTime(2026, 4, 9, 10);
      final store = _MemoryStore()
        ..write('k', {
          'v': 1,
          'ts': now.subtract(const Duration(seconds: 5)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _ImmediateCachedBox(
        'x',
        persistKey: 'k',
        ttl: const Duration(minutes: 10), // cache is fresh
        nextValue: 99,
      );
      await _flush();

      expect(box.valueOrNull, 1);
      expect(box.refreshCalls, 0);

      await box.refresh();
      await _flush();

      expect(box.valueOrNull, 99);
      expect(box.refreshCalls, 1);
    });

    test('refresh() updates store with new value and timestamp', () async {
      var now = DateTime(2026, 4, 9, 10);
      final store = _MemoryStore()
        ..write('k', {
          'v': 1,
          'ts': now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _ImmediateCachedBox(
        'x',
        persistKey: 'k',
        ttl: const Duration(minutes: 10),
        nextValue: 42,
      );
      await _flush();

      now = DateTime(2026, 4, 9, 10, 1); // advance clock 1 min
      await box.refresh();
      await _flush();

      final raw = store.read('k') as Map;
      expect(raw['v'], 42);
      expect(raw['ts'], now.millisecondsSinceEpoch);
    });

    // ---- TTL expiry → refresh → store updated ----

    test('expired cache triggers refresh that updates store', () async {
      var now = DateTime(2026, 4, 9, 12);
      final staleTs =
          now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
      final store = _MemoryStore()
        ..write('k', {'v': 10, 'ts': staleTs});

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _ImmediateCachedBox(
        'x',
        persistKey: 'k',
        ttl: const Duration(minutes: 1),
        nextValue: 77,
      );

      // Access triggers _maybeRefreshOnAccess (deferred microtask)
      expect(box.output, isA<AsyncData<int>>());

      now = DateTime(2026, 4, 9, 12, 0, 1); // small advance for new ts
      await _flush();

      expect(box.valueOrNull, 77);
      expect(box.refreshCalls, 1);

      final raw = store.read('k') as Map;
      expect(raw['v'], 77);
    });

    // ---- invalidateCache() ----

    test('invalidateCache clears store then fills with fresh data', () async {
      final now = DateTime(2026, 4, 9, 12);
      final store = _MemoryStore()
        ..write('k', {
          'v': 5,
          'ts':
              now.subtract(const Duration(seconds: 10)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _CachedIntBox(
        'x',
        persistKey: 'k',
        ttl: const Duration(minutes: 10),
      );
      await _flush();

      expect(box.valueOrNull, 5);

      // Store is cleared synchronously by invalidateCache
      final refreshFuture = box.invalidateCache();
      expect(store.read('k'), isNull);

      box.completerFor('x').complete(55);
      await refreshFuture;
      await _flush();

      expect(box.valueOrNull, 55);
      final raw = store.read('k') as Map;
      expect(raw['v'], 55);
    });

    // ---- refresh error ----

    test('compute error during refresh preserves previous cached value',
        () async {
      final now = DateTime(2026, 4, 9, 12);
      final store = _MemoryStore()
        ..write('k', {
          'v': 100,
          'ts':
              now.subtract(const Duration(seconds: 10)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _FailingCachedBox(
        'x',
        persistKey: 'k',
        ttl: const Duration(minutes: 10),
      );
      await _flush();

      expect(box.valueOrNull, 100);

      box.error = Exception('network down');
      await box.refresh();
      await _flush();

      // Box emits AsyncError, but previous data is still accessible
      final out = box.output;
      expect(out, isA<AsyncError<int>>());
      expect((out as AsyncError<int>).previousData, 100);

      // Store was not overwritten — still has old value
      final raw = store.read('k') as Map;
      expect(raw['v'], 100);
    });

    test('successful refresh after error recovers normally', () async {
      final now = DateTime(2026, 4, 9, 12);
      final store = _MemoryStore()
        ..write('k', {
          'v': 100,
          'ts':
              now.subtract(const Duration(seconds: 10)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _FailingCachedBox(
        'x',
        persistKey: 'k',
        ttl: const Duration(minutes: 10),
      );
      await _flush();

      // First refresh fails
      box.error = Exception('temporary');
      await box.refresh();
      await _flush();
      expect(box.output, isA<AsyncError<int>>());

      // Second refresh succeeds
      box.error = null;
      await box.refresh();
      await _flush();

      expect(box.valueOrNull, 100);
      expect(box.refreshCalls, 2);
    });

    // ---- sequential refreshes ----

    test('two sequential refreshes both update data', () async {
      final now = DateTime(2026, 4, 9, 12);
      final store = _MemoryStore()
        ..write('k', {
          'v': 1,
          'ts':
              now.subtract(const Duration(seconds: 10)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _ImmediateCachedBox(
        'x',
        persistKey: 'k',
        ttl: const Duration(minutes: 10),
        nextValue: 10,
      );
      await _flush();

      await box.refresh();
      await _flush();
      expect(box.valueOrNull, 10);

      box.nextValue = 20;
      await box.refresh();
      await _flush();
      expect(box.valueOrNull, 20);

      expect(box.refreshCalls, 2);
      expect((store.read('k') as Map)['v'], 20);
    });

    // ---- refresh dedup ----

    test('concurrent refresh() returns same Future and calls compute once',
        () async {
      final now = DateTime(2026, 4, 9, 12);
      final store = _MemoryStore()
        ..write('k', {
          'v': 1,
          'ts':
              now.subtract(const Duration(seconds: 10)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _CachedIntBox(
        'x',
        persistKey: 'k',
        ttl: const Duration(minutes: 10),
      );
      await _flush();
      expect(box.refreshCalls, 0);

      final f1 = box.refresh();
      final f2 = box.refresh();

      expect(identical(f1, f2), isTrue);

      box.completerFor('x').complete(50);
      await f1;
      await _flush();

      expect(box.refreshCalls, 1);
    });

    test('after refresh completes, next refresh() creates new task', () async {
      final now = DateTime(2026, 4, 9, 12);
      final store = _MemoryStore()
        ..write('k', {
          'v': 1,
          'ts':
              now.subtract(const Duration(seconds: 10)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _ImmediateCachedBox(
        'x',
        persistKey: 'k',
        ttl: const Duration(minutes: 10),
        nextValue: 10,
      );
      await _flush();

      final f1 = box.refresh();
      await f1;
      await _flush();

      final f2 = box.refresh();
      expect(identical(f1, f2), isFalse);

      await f2;
      await _flush();
      expect(box.refreshCalls, 2);
    });

    // ---- TTL reset after refresh ----

    test('after refresh, cache is fresh and output does not trigger new refresh',
        () async {
      var now = DateTime(2026, 4, 9, 12);
      final store = _MemoryStore()
        ..write('k', {
          'v': 1,
          'ts': now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
        });

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _ImmediateCachedBox(
        'x',
        persistKey: 'k',
        ttl: const Duration(minutes: 1), // stale on construction
        nextValue: 50,
      );

      // First access triggers stale refresh
      box.output;
      await _flush();
      expect(box.refreshCalls, 1);
      expect(box.valueOrNull, 50);

      // Now advance clock to just under TTL — still fresh
      now = DateTime(2026, 4, 9, 12, 0, 30);

      box.nextValue = 999;
      box.output; // should NOT trigger refresh
      await _flush();

      expect(box.refreshCalls, 1); // no new refresh
      expect(box.valueOrNull, 50); // still old value
    });

    // ---- no cache (cold start) ----

    test('cold start without cache emits loading then data', () async {
      final now = DateTime(2026, 4, 9, 12);
      final store = _MemoryStore(); // empty — no cached value

      BlackboxPersistence.init(store);
      BlackboxPersistence.now = () => now;

      final box = _CachedIntBox(
        'x',
        persistKey: 'k',
        ttl: const Duration(minutes: 1),
      );

      final seen = <AsyncOutput<int>>[];
      final cancel = box.listenAsync(seen.add);

      // No previous → shouldEmitLoadingBeforeCompute returns true
      expect(seen.first, isA<AsyncLoading<int>>());

      box.completerFor('x').complete(33);
      await _flush();

      expect(seen.last, isA<AsyncData<int>>());
      expect((seen.last as AsyncData<int>).value, 33);

      // Store now has envelope
      final raw = store.read('k') as Map;
      expect(raw['v'], 33);
      expect(raw['ts'], now.millisecondsSinceEpoch);

      cancel();
    });
  });
}
