import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

final class _Counter extends NoInputBox<int> {
  late final _count = state(0);

  @override
  int compute() => _count.value;

  void inc() => _count.value++;
}

/// Loading until [open] — an async source with no output yet.
final class _Gate extends NoInputAsyncBox<String> {
  final _opened = Completer<String>();

  @override
  Future<String> compute() => _opened.future;

  void open(String v) => _opened.complete(v);
}

final class _Player extends MultiBox<int> {
  late final status = child('idle');

  @override
  void compute(int input) => dispatch(status, 'bound:$input');
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('effect trace', () {
    test('ran / unchanged / first run, by name, with input and previous',
        () async {
      final counter = _Counter();
      final traces = <PumpTrace>[];
      final graph = Graph.builder<void>()
          .add(counter)
          .addEffect<int>(
            (d) => d.onlyWhenReady(counter),
            name: 'meter',
            run: (cur, prev) {},
          )
          .build(onTrace: traces.add);
      await graph.pumpedOnce();

      final first = traces.single.effects.single;
      expect(first.name, 'meter');
      expect(first.result, EffectTraceResult.ran);
      expect(first.input, '0');
      expect(first.previous, isNull); // first run

      counter.inc();
      await _settle();
      final second = traces.last.effects.single;
      expect(second.result, EffectTraceResult.ran);
      expect(second.input, '1');
      expect(second.previous, '0');
      expect(traces.last.ran, 1);

      // A pump the effect's input does not care about: unchanged.
      final other = _Counter();
      graph.dispose();
      final traces2 = <PumpTrace>[];
      final graph2 = Graph.builder<void>()
          .add(counter)
          .add(other)
          .addEffect<int>(
            (d) => d.onlyWhenReady(counter),
            name: 'meter',
            run: (cur, prev) {},
          )
          .build(onTrace: traces2.add);
      await graph2.pumpedOnce();
      other.inc();
      await _settle();
      expect(traces2.last.effects.single.result, EffectTraceResult.unchanged);
      expect(traces2.last.ran, 0);
      graph2.dispose();
    });

    test('waiting while a required source has no output', () async {
      final gate = _Gate();
      final traces = <PumpTrace>[];
      final graph = Graph.builder<void>()
          .add(gate)
          .addEffect<String>(
            (d) => d.onlyWhenReady(gate),
            name: 'sink',
            run: (cur, prev) {},
          )
          .build(onTrace: traces.add);
      await graph.pumpedOnce();
      expect(traces.last.effects.single.result, EffectTraceResult.waiting);

      gate.open('go');
      await _settle();
      expect(traces.last.effects.single.result, EffectTraceResult.ran);
      expect(traces.last.effects.single.input, 'go');
      graph.dispose();
    });

    test('unnamed effects are numbered in registration order', () async {
      final counter = _Counter();
      final traces = <PumpTrace>[];
      final graph = Graph.builder<void>()
          .add(counter)
          .addEffect<int>((d) => d.onlyWhenReady(counter), run: (c, p) {})
          .addEffect<int>(
            (d) => d.onlyWhenReady(counter),
            name: 'named',
            run: (c, p) {},
          )
          .addEffect<int>((d) => d.onlyWhenReady(counter), run: (c, p) {})
          .build(onTrace: traces.add);
      await graph.pumpedOnce();
      expect(
        traces.single.effects.map((e) => e.name),
        ['effect_1', 'named', 'effect_3'],
      );
      graph.dispose();
    });

    test('the map labels an effect by its name', () async {
      final counter = _Counter();
      final graph = Graph.builder<void>()
          .add(counter)
          .addEffect<int>(
            (d) => d.onlyWhenReady(counter),
            name: 'spectrum',
            run: (c, p) {},
          )
          .build();
      await graph.pumpedOnce();
      expect(graph.toMermaid(), contains('effect_1{{spectrum}}'));
      graph.dispose();
    });

    test('an oscillating effect is visible as alternating inputs', () async {
      // The shape of a ring that closes through a device: the effect's
      // own command changes the value that feeds it. In the structure it
      // is one wire; in the trace it is the same effect running with A,
      // B, A, B — which is what the trace exists to show.
      final counter = _Counter();
      final traces = <PumpTrace>[];
      final graph = Graph.builder<void>()
          .add(counter)
          .addEffect<bool>(
            (d) => d.onlyWhenReady(counter).isEven,
            name: 'analyzer',
            run: (cur, prev) {},
          )
          .build(onTrace: traces.add);
      await graph.pumpedOnce();
      for (var i = 0; i < 3; i++) {
        counter.inc();
        await _settle();
      }
      final inputs = traces
          .map((t) => t.effects.single)
          .where((e) => e.result == EffectTraceResult.ran)
          .map((e) => e.input)
          .toList();
      expect(inputs, ['true', 'false', 'true', 'false']);
      graph.dispose();
    });
  });

  group('multibox trace', () {
    test('computed with its input; unchanged when the input repeats',
        () async {
      final counter = _Counter();
      final player = _Player();
      final traces = <PumpTrace>[];
      final graph = Graph.builder<void>()
          .add(counter)
          .addMultiBox(player, input: (d) => d.onlyWhenReady(counter) ~/ 2)
          .build(onTrace: traces.add);
      await graph.pumpedOnce();

      final born = traces.single.events.firstWhere((e) => e.name == '_Player');
      expect(born.result, BoxTraceResult.computed);
      expect(born.input, '0');
      expect(born.value, isNull); // a multibox has no single output

      counter.inc(); // 1 ~/ 2 == 0 — the multibox input did not change
      await _settle();
      expect(
        traces.last.events.firstWhere((e) => e.name == '_Player').result,
        BoxTraceResult.skipped,
      );

      counter.inc(); // 2 ~/ 2 == 1
      await _settle();
      final again = traces.last.events.firstWhere((e) => e.name == '_Player');
      expect(again.result, BoxTraceResult.computed);
      expect(again.input, '1');
      expect(player.status.value, 'bound:1');
      graph.dispose();
    });
  });
}
