// The README example. Run: dart run example/main.dart

// ignore_for_file: avoid_print

import 'package:blackbox/blackbox.dart';

/// Remembers the step. A button writes it.
final class StepBox extends NoInputBox<int> {
  late final _step = state(1);
  @override
  int compute() => _step.value;
  void set(int step) => _step.value = step;
}

/// Remembers the count; its input is the step, wired by the graph.
final class CounterBox extends Box<int, int> {
  CounterBox.late() : super.late(initialValue: 0);
  late final _count = state(0);
  @override
  int compute(int step) => _count.value;
  void increment() => _count.value += input; // a button reads the input
}

Future<void> main() async {
  final step = StepBox();
  final counter = CounterBox.late();

  final graph = Graph.builder()
      .add(step)
      .add(counter, input: (d) => d.onlyWhenReady(step))
      .addEffect<int>((d) => d.onlyWhenReady(counter),
          name: 'log', run: (now, was) => print('count: $was → $now'))
      .build();
  await graph.settled(); // count: null → 0

  counter.increment(); // count: 0 → 1
  step.set(5);
  await graph.settled();
  counter.increment(); // count: 1 → 6
  await graph.settled();

  graph.dispose();
}
