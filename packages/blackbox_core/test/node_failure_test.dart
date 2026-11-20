import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

/// A node that throws fails alone: the error is reported to the zone as a
/// [GraphNodeError] naming the node, the node keeps its previous output
/// until its next input, and every other node and effect in the pump runs
/// as usual.

final class SourceBox extends NoInputBox<int> {
  late final _v = state(0);
  @override
  int compute() => _v.value;
  void set(int v) => _v.value = v;
}

final class FlakyBox extends Box<int, int> {
  FlakyBox.late() : super.late();
  bool failing = false;
  @override
  int compute(int n) {
    if (failing) throw StateError('boom');
    return n * 10;
  }
}

final class EchoBox extends Box<int, int> {
  EchoBox.late() : super.late();
  @override
  int compute(int n) => n;
}

/// Grows on every recompute — wired to itself it can never settle.
final class GrowBox extends Box<int, int> {
  GrowBox({required int input}) : super(input);
  @override
  int compute(int n) => n + 1;
}

Future<List<Object>> guarded(Future<void> Function() body) async {
  final errors = <Object>[];
  await runZonedGuarded(body, (e, _) => errors.add(e));
  return errors;
}

void main() {
  test('compute throws: the rest of the pump still runs, the error names '
      'the node', () async {
    final source = SourceBox();
    final flaky = FlakyBox.late();
    final after = EchoBox.late();
    final other = SourceBox();
    late Graph<void> graph;

    final errors = await guarded(() async {
      graph = Graph.builder()
          .add(source)
          .add(other)
          .add(flaky, input: (d) => d.onlyWhenReady(source))
          .add(after, input: (d) => d.onlyWhenReady(source))
          .build();
      await graph.settled();

      flaky.failing = true;
      source.set(1);
      await graph.settled();
      expect(flaky.value, 0, reason: 'keeps its previous output');
      expect(after.value, 1, reason: 'a node declared after it still ran');

      // Same input, another pump: not retried — it would fail again, and
      // the error was already reported once.
      other.set(1);
      await graph.settled();

      // A new input: the node runs again and recovers.
      flaky.failing = false;
      source.set(2);
      await graph.settled();
      expect(flaky.value, 20);
    });

    expect(errors, hasLength(1), reason: 'reported once, not per pump');
    final error = errors.single as GraphNodeError;
    expect(error.node, 'FlakyBox');
    expect(error.stage, 'compute');
    expect(error.error, isA<StateError>());
    graph.dispose();
  });

  test('a wire throws: stage is input', () async {
    final source = SourceBox();
    final echo = EchoBox.late();
    late Graph<void> graph;
    final errors = await guarded(() async {
      graph = Graph.builder()
          .add(source)
          .add(echo, input: (d) {
            final v = d.onlyWhenReady(source);
            if (v == 1) throw ArgumentError('bad wire');
            return v;
          })
          .build();
      await graph.settled();
      source.set(1);
      await graph.settled();
    });
    expect((errors.single as GraphNodeError).stage, 'input');
    expect(echo.value, 0);
    graph.dispose();
  });

  test('an effect throws: later effects still run; the same input is not '
      'repeated', () async {
    final source = SourceBox();
    final other = SourceBox();
    var firstRuns = 0;
    final second = <int>[];
    late Graph<void> graph;

    final errors = await guarded(() async {
      graph = Graph.builder()
          .add(source)
          .add(other)
          .addEffect<int>((d) => d.onlyWhenReady(source), name: 'device',
              run: (v, _) {
            firstRuns++;
            if (v == 1) throw StateError('device offline');
          })
          .addEffect<int>((d) => d.onlyWhenReady(source),
              run: (v, _) => second.add(v))
          .build();
      await graph.settled();
      source.set(1);
      await graph.settled();
      other.set(1); // another pump, same input for the effect
      await graph.settled();
    });

    expect(second, [0, 1]);
    expect(firstRuns, 2, reason: 'it touched the world once per input');
    final error = errors.single as GraphNodeError;
    expect(error.node, 'effect device');
    expect(error.stage, 'run');
    graph.dispose();
  });

  test('a listener throws: other listeners still hear, the writer does not '
      'throw', () async {
    final source = SourceBox();
    final heard = <int>[];
    final errors = await guarded(() async {
      source.listen((_) => throw StateError('bad listener'), skipFirst: true);
      source.listen((o) => heard.add((o as SyncData<int>).value),
          skipFirst: true);
      source.set(3); // does not throw here
    });
    expect(heard, [3]);
    expect(errors.single, isA<StateError>());
  });

  test('trace marks the failed node', () async {
    final source = SourceBox();
    final flaky = FlakyBox.late()..failing = true;
    final traces = <PumpTrace>[];
    late Graph<void> graph;
    await guarded(() async {
      graph = Graph.builder()
          .add(source)
          .add(flaky, input: (d) => d.onlyWhenReady(source))
          .build(onTrace: traces.add);
      await graph.settled();
    });
    final event = traces.first.events.singleWhere((e) => e.name == 'FlakyBox');
    expect(event.result, BoxTraceResult.failed);
    expect(event.error, contains('boom'));
    expect(traces.first.failed, 1);
    graph.dispose();
  });

  test('the storm detector names the nodes that never settle', () async {
    final errors = <Object>[];
    runZonedGuarded(() {
      final a = GrowBox(input: 0);
      final b = GrowBox(input: 0);
      Graph.builder()
          .add(a, input: (d) => d.onlyWhenReady(b))
          .add(b, input: (d) => d.onlyWhenReady(a))
          .build();
    }, (e, _) => errors.add(e));
    for (var i = 0; i < 800 && errors.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(errors.single.toString(),
        contains('Still changing on every cycle: GrowBox'));
  });
}
