import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

/// A box output equal to the current one is not published — the same
/// rule as state cells and multibox cells.

final class SourceBox extends NoInputBox<int> {
  late final _v = state(0);
  @override
  int compute() => _v.value;
  void set(int v) => _v.value = v;
}

final class ParityBox extends Box<int, bool> {
  ParityBox.late() : super.late();
  @override
  bool compute(int n) => n.isEven;
}

final class CountingBox<T> extends Box<T, T> {
  CountingBox.late() : super.late();
  int computeCalls = 0;
  @override
  T compute(T input) {
    computeCalls++;
    return input;
  }
}

/// Returns a fresh list each compute — like an equalizer curve.
final class CurveBox extends Box<int, List<double>> {
  CurveBox.late() : super.late();
  @override
  List<double> compute(int bands) => List.filled(bands, 0.5);

  @override
  bool sameOutput(List<double> previous, List<double> next) =>
      previous.length == next.length &&
      Iterable.generate(previous.length)
          .every((i) => previous[i] == next[i]);
}

/// Input is a fresh list on every pump; output is an int (has ==).
final class LengthBox extends Box<List<int>, int> {
  LengthBox.late() : super.late();
  int computeCalls = 0;
  @override
  int compute(List<int> input) {
    computeCalls++;
    return input.length;
  }
}

final class SongBox extends NoInputBox<String> {
  late final _v = state('A');
  @override
  String compute() => _v.value;
  void set(String v) => _v.value = v;
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

final class SameRatesBox extends NoInputCachedBox<int> {
  int fetches = 0;
  @override
  Cache<void, int> get cache => const Cache(ttl: Duration(minutes: 1));
  @override
  Future<int> fetch() async {
    fetches++;
    return 100;
  }
}

void main() {
  test('an equal output is not published: downstream does not re-run',
      () async {
    final source = SourceBox();
    final parity = ParityBox.late();
    final downstream = CountingBox<bool>.late();
    final graph = Graph.builder()
        .add(source)
        .add(parity, input: (d) => d.onlyWhenReady(source))
        .add(downstream, input: (d) => d.onlyWhenReady(parity))
        .build();
    await graph.settled();
    final calls = downstream.computeCalls;
    var heard = 0;
    parity.listen((_) => heard++, skipFirst: true);

    source.set(2); // even → even: parity recomputes, output unchanged
    source.set(4);
    await graph.settled();

    expect(heard, 0);
    expect(downstream.computeCalls, calls);

    source.set(5); // a real change still flows
    await graph.settled();
    expect(heard, 1);
    expect(downstream.value, isFalse);
    graph.dispose();
  });

  test('sameOutput: one override for a type without content ==', () async {
    final bands = SourceBox()..set(3);
    final curve = CurveBox.late();
    final sent = <List<double>>[];
    final graph = Graph.builder()
        .add(bands)
        .add(curve, input: (d) => d.onlyWhenReady(bands))
        .addEffect<List<double>>((d) => d.onlyWhenReady(curve),
            run: (current, _) => sent.add(current))
        .build();
    await graph.settled();
    expect(sent, hasLength(1));

    // Recompute with the same input contents: a fresh, equal list.
    updateInputForTest(curve, 3);
    await graph.settled();
    expect(sent, hasLength(1), reason: 'the device got the curve once');
    graph.dispose();
  });

  test('a fresh list on the wire costs a recompute, not the graph', () async {
    final errors = <Object>[];
    late SourceBox source;
    late LengthBox box;
    late Graph<void> graph;
    await runZonedGuarded(() async {
      source = SourceBox();
      box = LengthBox.late();
      graph = Graph.builder()
          .add(source)
          .add(box, input: (d) => [d.onlyWhenReady(source)])
          .build();
      await graph.settled();
      source.set(7);
      await graph.settled();
    }, (e, _) => errors.add(e));

    expect(errors, isEmpty, reason: 'no storm');
    expect(box.value, 1);
    expect(box.computeCalls, lessThan(5));
    graph.dispose();
  });

  // Regression (field): a cache switching slots swaps the box state
  // silently; dedup must compare with what listeners saw, not with that.
  test('cache slot switch A → B → A: the reader ends on A', () async {
    var now = DateTime(2026, 1, 1, 12);
    BlackboxPersistence.reset();
    BlackboxPersistence.init(MemStore());
    BlackboxPersistence.now = () => now;
    addTearDown(BlackboxPersistence.reset);

    final song = SongBox();
    final cover = CoverBox.late();
    final shown = <String>[];
    final graph = Graph.builder()
        .add(song)
        .add(cover, input: (d) => d.onlyWhenReady(song))
        .addEffect<String>((d) => d.onlyWhenReady(cover),
            run: (c, _) => shown.add(c))
        .build();

    for (final s in ['A', 'B', 'A']) {
      song.set(s);
      await pumpEventQueue();
    }
    expect(cover.output, const AsyncData('cover-A'));
    expect(shown.last, 'cover-A', reason: 'the lock screen shows A again');
    graph.dispose();
  });

  test('late cached box restored from disk: an early listener gets it',
      () async {
    final store = MemStore()
      ..values['menu:x'] = {
        'v': 'disk-x',
        'ts': DateTime(2026, 1, 1, 12).millisecondsSinceEpoch,
      };
    BlackboxPersistence.reset();
    BlackboxPersistence.init(store);
    BlackboxPersistence.now = () => DateTime(2026, 1, 1, 12, 1);
    addTearDown(BlackboxPersistence.reset);

    final menu = MenuLateBox.late();
    final seen = <Output<String>>[];
    menu.listen(seen.add); // subscribed before the first input: loading
    updateAsyncInputForTest(menu, 'x');
    await pumpEventQueue();
    expect(seen.last, const AsyncData('disk-x'));
  });

  test('cache: a refresh that fetched the same value is not republished, '
      'but still renews the TTL', () async {
    var now = DateTime(2026, 1, 1, 12);
    BlackboxPersistence.reset();
    BlackboxPersistence.init(MemStore());
    BlackboxPersistence.now = () => now;
    addTearDown(BlackboxPersistence.reset);

    final rates = SameRatesBox();
    final seen = <Output<int>>[];
    rates.listen(seen.add);
    await pumpEventQueue();
    expect(rates.output, const AsyncData(100));
    final published = seen.length;
    expect(rates.fetches, 1);

    now = now.add(const Duration(minutes: 2)); // expired
    rates.output; // access → background refresh
    await pumpEventQueue();
    expect(rates.fetches, 2);
    expect(seen.length, published, reason: 'same value: nothing published');

    now = now.add(const Duration(seconds: 30)); // fresh again since fetch 2
    rates.output;
    await pumpEventQueue();
    expect(rates.fetches, 2, reason: 'TTL was renewed by the second fetch');
  });
}

final class CoverBox extends CachedBox<String, String> {
  CoverBox.late() : super.late();
  @override
  Cache<String, String> get cache => Cache(
        ttl: const Duration(minutes: 5),
        persistFor: (song) => 'cover:$song',
      );
  @override
  Future<String> fetch(String song) async => 'cover-$song';
}

final class MenuLateBox extends CachedBox<String, String> {
  MenuLateBox.late() : super.late();
  @override
  Cache<String, String> get cache =>
      Cache(ttl: const Duration(minutes: 5), persistFor: (id) => 'menu:$id');
  @override
  Future<String> fetch(String id) async => 'fresh-$id';
}

