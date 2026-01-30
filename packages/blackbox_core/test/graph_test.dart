// test/graph_test.dart
import 'dart:async';

import 'package:test/test.dart';

import 'package:blackbox/blackbox.dart';

/// --- Helpers ----------------------------------------------------------------

/// Collects emitted states; provides awaitNext() for async-friendly asserts.
final class StateLog<T> {
  final _values = <T>[];
  final _controller = StreamController<T>.broadcast();

  void add(T v) {
    _values.add(v);
    _controller.add(v);
  }

  List<T> get values => List.unmodifiable(_values);

  Future<T> awaitNext({Duration timeout = const Duration(seconds: 1)}) async {
    return _controller.stream.first.timeout(timeout);
  }

  Future<void> close() => _controller.close();
}

/// Box with NO input (sync): holds internal step value.
final class StepConfigBox extends Box<int> {
  int _step = 1;

  StepConfigBox();

  @override
  int compute() => _step;

  void setStep(int step) {
    signal(() {
      _step = step;
    });
  }
}

/// Box WITH input (sync): output depends on input.step and internal count.
typedef CounterInput = ({int step});

final class CounterBox extends BoxWithInput<CounterInput, int> {
  int _count = 0;

  CounterBox() : super((step: 1));

  void inc() {
    signal(() {
      _count += 1;
    });
  }

  @override
  int compute(CounterInput input) => _count * input.step;
}

/// Simple spy box without input: counts how many times compute() was called.
final class SpySyncBox extends Box<int> {
  int computeCount = 0;
  int value = 0;

  SpySyncBox();

  @override
  int compute() {
    computeCount += 1;
    return value;
  }

  void setValue(int v) {
    signal(() {
      value = v;
    });
  }
}

/// Simple spy box with input: counts computes and returns input.step.
typedef StepInput = ({int step});

final class SpySyncBoxWithInput extends BoxWithInput<StepInput, int> {
  int computeCount = 0;

  SpySyncBoxWithInput() : super((step: 1));

  @override
  int compute(StepInput input) {
    computeCount += 1;
    return input.step;
  }
}

/// --- Tests ------------------------------------------------------------------

void main() {
  group('Graph (builder)', () {
    test('box without dependencies: computes on build + on signal', () async {
      final spy = SpySyncBox();

      final log = StateLog<int>();
      final graph = Graph.builder().add(spy).build();

      final cancel = spy.listen((o) {
        // Sync output contract: value is always available.
        log.add(o.value);
      });

      // Build should have caused the first compute.
      expect(spy.computeCount, 2);
      expect(log.values.last, 0);

      spy.setValue(7);

      // Wait until output is observed.
      final v = await log.awaitNext();
      expect(v, 7);
      expect(spy.computeCount, 3);

      cancel();
      await log.close();
    });

    test('dependency mapping: dependent recomputes when upstream changes',
        () async {
      final stepConfig = StepConfigBox();
      final counter = CounterBox();

      final log = StateLog<int>();

      final graph = Graph.builder()
          // no dependencies
          .add(stepConfig)
          // counter depends on stepConfig output -> mapped into input record
          .addWithDependencies(
            counter,
            dependencies: (d) => (step: d.of<int>(stepConfig)),
          )
          .build();

      final cancel = counter.listen((o) => log.add(o.value));

      // Initial:
      // stepConfig = 1, counter count = 0 => 0 * 1 = 0
      expect(log.values.last, 0);

      counter.inc(); // count=1, step=1 => 1
      expect(await log.awaitNext(), 1);

      stepConfig.setStep(3); // step=3, count=1 => 3
      expect(await log.awaitNext(), 3);

      counter.inc(); // count=2, step=3 => 6
      expect(await log.awaitNext(), 6);

      cancel();
      await log.close();
    });

    test('spy with input: recomputes exactly when dependency changes',
        () async {
      final stepConfig = StepConfigBox();
      final spy = SpySyncBoxWithInput();

      final log = StateLog<int>();

      final graph = Graph.builder()
          .add(stepConfig)
          .addWithDependencies(
            spy,
            dependencies: (d) => (step: d.of<int>(stepConfig)),
          )
          .build();

      final cancel = spy.listen((o) => log.add(o.value));

      // Initial compute once.
      expect(spy.computeCount, 1);
      expect(log.values.last, 1);

      // Signal that doesn't change step -> still recompute upstream -> output changes only if value changes.
      stepConfig.setStep(1);
      // Depending on your Graph semantics:
      // - if it propagates on every upstream emission (even same value), this will recompute.
      // - if it dedupes equal values, it won't.
      //
      // MVP: assume NO dedupe (simpler) => recompute occurs.
      expect(await log.awaitNext(), 1);
      expect(spy.computeCount, 2);

      stepConfig.setStep(2);
      expect(await log.awaitNext(), 2);
      expect(spy.computeCount, 3);

      cancel();
      await log.close();
    });
  });
}
