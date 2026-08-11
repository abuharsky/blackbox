import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

Future<void> flushMicrotasks([int times = 6]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Memory driving an async compute: the search-box pattern.
final class SearchBox extends NoInputAsyncBox<String> {
  int computeCalls = 0;
  late final query = state('');

  @override
  Future<String> compute() async {
    computeCalls++;
    return 'results: ${query.value}';
  }

  void type(String q) => query.value = q;

  void retypeBatched(String a, String b) => action(() {
        query.value = a;
        query.value = b;
      });
}

/// Persisted async cell.
final class DraftBox extends NoInputAsyncBox<String> {
  late final draft = state('', persist: 'draft');

  @override
  Future<String> compute() async => 'draft: ${draft.value}';

  void set(String v) => draft.value = v;
}

/// Slot-per-input cell on an async box.
final class UserDraftBox extends AsyncBox<String, String> {
  late final draft = state('', persistFor: (user) => 'draft:$user');

  UserDraftBox({required String input}) : super(input);

  @override
  Future<String> compute(String user) async =>
      '$user: ${draft.value}';

  void set(String v) => draft.value = v;
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

String render(AsyncOutput<String> o) => switch (o) {
      AsyncLoading<String>(:final previousData) => 'loading($previousData)',
      AsyncData<String>(:final value) => 'data($value)',
      AsyncError<String>() => 'error',
    };

void main() {
  group('Async cells (no persistence)', () {
    test('cell write re-runs compute: loading with previous, then data',
        () async {
      final box = SearchBox();
      await flushMicrotasks();
      expect(box.computeCalls, 1);

      final seen = <String>[];
      box.listen((o) => seen.add(render(o as AsyncOutput<String>)),
          skipFirst: true);

      box.type('cof');
      await flushMicrotasks();

      expect(seen, ['loading(results: )', 'data(results: cof)']);
      expect(box.computeCalls, 2);
    });

    test('writing an equal value is a no-op', () async {
      final box = SearchBox();
      await flushMicrotasks();
      final callsBefore = box.computeCalls;

      box.type(''); // already ''
      await flushMicrotasks();

      expect(box.computeCalls, callsBefore);
    });

    test('action batches writes: one recompute at the end', () async {
      final box = SearchBox();
      await flushMicrotasks();
      final callsBefore = box.computeCalls;

      box.retypeBatched('c', 'co');
      await flushMicrotasks();

      expect(box.computeCalls, callsBefore + 1);
      expect((box.output as AsyncData<String>).value, 'results: co');
    });
  });

  group('Async cells with persistence', () {
    late MemStore store;

    setUp(() {
      BlackboxPersistence.reset();
      store = MemStore();
      BlackboxPersistence.init(store);
    });

    tearDown(BlackboxPersistence.reset);

    test('persist: cell saves on write and restores on creation', () async {
      final box = DraftBox();
      await flushMicrotasks();

      box.set('hello');
      await flushMicrotasks();
      expect((store.values['draft'] as Map<Object?, Object?>)['v'], 'hello');

      final restarted = DraftBox();
      expect(restarted.draft.value, 'hello');
      await flushMicrotasks();
      expect((restarted.output as AsyncData<String>).value, 'draft: hello');
    });

    test('persistFor: input change re-slots the cell without leaks',
        () async {
      final box = UserDraftBox(input: 'alice');
      await flushMicrotasks();

      box.set('alice-text');
      await flushMicrotasks();
      expect((box.output as AsyncData<String>).value, 'alice: alice-text');

      updateAsyncInputForTest(box, 'bob');
      await flushMicrotasks();
      expect(box.draft.value, '', reason: 'fresh slot for bob');
      expect((box.output as AsyncData<String>).value, 'bob: ');

      box.set('bob-text');
      await flushMicrotasks();
      expect((store.values['draft:alice'] as Map<Object?, Object?>)['v'],
          'alice-text');
      expect((store.values['draft:bob'] as Map<Object?, Object?>)['v'],
          'bob-text');

      updateAsyncInputForTest(box, 'alice');
      await flushMicrotasks();
      expect(box.draft.value, 'alice-text', reason: 'restored from her slot');
      expect((box.output as AsyncData<String>).value, 'alice: alice-text');
    });
  });

  group('Async cells lifecycle', () {
    test('writes after graph dispose neither compute nor notify', () async {
      final box = SearchBox();
      final g = Graph.builder().add(box).build();
      await flushMicrotasks();

      final callsBefore = box.computeCalls;
      var emissions = 0;
      box.listen((_) => emissions++, skipFirst: true);

      g.dispose();
      box.type('late');
      await flushMicrotasks();

      expect(box.computeCalls, callsBefore);
      expect(emissions, 0);
    });
  });
}
