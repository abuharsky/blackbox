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
    with CachedAsyncSupport<String, int> {
  final Map<String, Completer<int>> _completers = <String, Completer<int>>{};
  final Duration? ttl;
  final bool staleWhileRefresh;
  int refreshCalls = 0;

  _CachedIntBox(
    super.input, {
    required String persistKey,
    this.ttl,
    this.staleWhileRefresh = true,
  }) : super(persistKey: persistKey);

  @override
  Duration? get cacheTtl => ttl;

  @override
  bool get keepStaleWhileRefresh => staleWhileRefresh;

  Completer<int> completerFor(String input) =>
      _completers.putIfAbsent(input, () => Completer<int>());

  @override
  Future<int> refreshValue(String input, int? cached) {
    refreshCalls++;
    return completerFor(input).future;
  }
}

void main() {
  tearDown(() {
    BlackboxPersistence.reset();
  });

  group('CachedAsyncSupport', () {
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
}
