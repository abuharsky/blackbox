import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

final class StepBox extends NoInputBox<int> {
  late final _step = state(1);
  @override
  int compute(int? previous) => _step.value;
  void set(int v) => _step.value = v;
}

final class DoubledBox extends Box<int, int> {
  DoubledBox({required int input}) : super(input);
  @override
  int compute(int n, int? previous) => n * 2;
}

/// Grows on every recompute — wired to itself it can never settle.
final class EchoBox extends Box<int, int> {
  EchoBox({required int input}) : super(input);
  @override
  int compute(int n, int? previous) => n + 1;
}

final class TinyPlayerBox extends MultiBox<int> {
  late final status = child('idle');
  @override
  void compute(int input, int? previous) => dispatch(status, 'ch$input');
}

void main() {
  group('graph.settled()', () {
    test('replaces flushMicrotasks: propagation is done when it resolves',
        () async {
      final step = StepBox();
      final doubled = DoubledBox(input: 0);

      final graph = Graph.builder()
          .add(step)
          .add(doubled, input: (d) => d.whenReady<int>(step))
          .build();

      await graph.settled();
      expect(doubled.value, 2);

      step.set(5);
      await graph.settled();
      expect(doubled.value, 10);

      graph.dispose();
    });
  });

  group('pump storm detector', () {
    test('a dependency cycle fails loudly instead of hanging', () async {
      final errors = <Object>[];

      runZonedGuarded(() {
        final a = EchoBox(input: 0);
        final b = EchoBox(input: 0);

        Graph.builder()
            .add(a, input: (d) => d.whenReady<int>(b))
            .add(b, input: (d) => d.whenReady<int>(a))
            .build();
      }, (e, st) => errors.add(e));

      // Let the storm run into the limit.
      for (var i = 0; i < 800; i++) {
        await Future<void>.delayed(Duration.zero);
        if (errors.isNotEmpty) break;
      }

      expect(
        errors.map((e) => e.toString()),
        anyElement(contains('did not settle')),
      );
    });
  });

  group('graph.toMermaid()', () {
    test('renders nodes, multibox ownership, and effect edges', () async {
      final step = StepBox();
      final doubled = DoubledBox(input: 0);
      final player = TinyPlayerBox();
      final consumer = SpySyncInputBox(-1);

      final graph = Graph.builder()
          .add(step)
          .add(doubled, input: (d) => d.whenReady<int>(step))
          .addMultiBox(player, input: (d) => d.whenReady<int>(doubled))
          .add(consumer,
              input: (d) => d.whenReady<String>(player.status).length)
          .addEffect<int>(
            (d) => d.whenReady<int>(doubled),
            run: (_, __) {},
          )
          .build();

      await graph.settled();
      final mermaid = graph.toMermaid();

      expect(mermaid, startsWith('flowchart TD'));
      expect(mermaid, contains('StepBox --> DoubledBox'));
      expect(mermaid, contains('DoubledBox --> TinyPlayerBox'));
      expect(mermaid, contains('TinyPlayerBox -.-> ChildCell_String_'));
      expect(mermaid, contains('ChildCell_String_ --> SpySyncInputBox'));
      expect(mermaid, contains('DoubledBox --> effect_1{{effect}}'));

      graph.dispose();
    });
  });
}
