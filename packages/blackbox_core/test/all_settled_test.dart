import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

/// Graph.allSettled — tests only: waits until no graph pumps and no async
/// box computes, across every live graph.

final class SourceBox extends NoInputBox<int> {
  late final _v = state(0);
  @override
  int compute() => _v.value;
  void set(int v) => _v.value = v;
}

final class PlusOne extends Box<int, int> {
  PlusOne.late() : super.late();
  @override
  int compute(int n) => n + 1;
}

/// Takes real time, like a fake API with latency.
final class SlowDouble extends AsyncBox<int, int> {
  SlowDouble.late() : super.late();
  @override
  Future<int> compute(int n) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return n * 2;
  }
}

/// A fake left open: its compute never completes.
final class NeverBox extends AsyncBox<int, int> {
  NeverBox.late() : super.late();
  @override
  Future<int> compute(int n) => Completer<int>().future;
}

final class SlowStopList extends CachedValueBox<int, int> {
  SlowStopList.late() : super.late(initialValue: -1);
  @override
  Cache<int, int> get cache => const Cache(ttl: Duration(minutes: 1));
  @override
  Future<int> fetch(int n) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return n * 10;
  }
}

void main() {
  test('waits through graphs with async boxes between them, round after '
      'round', () async {
    // source → [slow ×2] → [+1] → [slow ×2] → [+1], one graph per step:
    // each async result wakes the next graph, whose pump starts the next
    // async compute.
    final source = SourceBox();
    final slow1 = SlowDouble.late();
    final plus1 = PlusOne.late();
    final slow2 = SlowDouble.late();
    final plus2 = PlusOne.late();
    final graphs = [
      Graph.builder().add(source).build(),
      Graph.builder().add(slow1, input: (d) => d.onlyWhenReady(source)).build(),
      Graph.builder().add(plus1, input: (d) => d.onlyWhenReady(slow1)).build(),
      Graph.builder().add(slow2, input: (d) => d.onlyWhenReady(plus1)).build(),
      Graph.builder().add(plus2, input: (d) => d.onlyWhenReady(slow2)).build(),
    ];

    source.set(5);
    await Graph.allSettled();
    expect(plus2.valueOrNull, (5 * 2 + 1) * 2 + 1);

    for (final g in graphs) {
      g.dispose();
    }
  });

  test('waits for an async compute and the pumps its result causes',
      () async {
    final source = SourceBox();
    final slow = SlowDouble.late();
    final after = PlusOne.late();
    final graph = Graph.builder()
        .add(source)
        .add(slow, input: (d) => d.onlyWhenReady(source))
        .add(after, input: (d) => d.onlyWhenReady(slow))
        .build();

    source.set(5);
    await Graph.allSettled();
    expect(after.value, 11);
    graph.dispose();
  });

  test('waits for a CachedValueBox background fetch', () async {
    final source = SourceBox();
    final stops = SlowStopList.late();
    final graph = Graph.builder()
        .add(source)
        .add(stops, input: (d) => d.onlyWhenReady(source))
        .build();

    source.set(3);
    await Graph.allSettled();
    expect(stops.value, 30);
    graph.dispose();
  });

  test('a compute that never completes fails with the box named, not a '
      'hang', () async {
    final source = SourceBox();
    final never = NeverBox.late();
    final graph = Graph.builder()
        .add(source)
        .add(never, input: (d) => d.onlyWhenReady(source))
        .build();

    await expectLater(
      Graph.allSettled(timeout: const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>().having(
          (e) => e.message, 'message', contains('NeverBox'))),
    );

    // Disposing the box drops its pending work: the next wait is quiet.
    graph.dispose();
    await Graph.allSettled(timeout: const Duration(milliseconds: 50));
  });

  test('returns at once when nothing is going on', () async {
    await Graph.allSettled(timeout: const Duration(milliseconds: 50));
  });
}
