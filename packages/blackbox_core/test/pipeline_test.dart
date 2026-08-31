import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

final class SeedBox extends NoInputBox<int> {
  late final _v = state(1);
  @override
  int compute() => _v.value;
}

final class DoubleBox extends AsyncBox<int, int> {
  DoubleBox.late() : super.late();
  @override
  Future<int> compute(int input) async => input * 2;
}

/// Fails [failuresBeforeSuccess] times, then succeeds — for retry tests.
final class FlakyBox extends AsyncBox<int, int> {
  FlakyBox.late({required this.failuresBeforeSuccess}) : super.late();
  int failuresBeforeSuccess;
  int attempts = 0;

  @override
  Future<int> compute(int input) async {
    attempts++;
    if (attempts <= failuresBeforeSuccess) throw StateError('flaky #$attempts');
    return input * 10;
  }
}

final class AlwaysFailBox extends AsyncBox<int, int> {
  AlwaysFailBox.late() : super.late();
  @override
  Future<int> compute(int input) async => throw StateError('down');
}

/// Fold that tolerates a missing optional upstream.
final class SumBox extends AsyncBox<({int a, int? b}), int> {
  SumBox.late() : super.late();
  @override
  Future<int> compute(({int a, int? b}) i) async => i.a + (i.b ?? 0);
}

final class NeverBox extends AsyncBox<int, int> {
  NeverBox.late() : super.late();
  @override
  Future<int> compute(int input) => Completer<int>().future;
}

void main() {
  group('Pipeline — the graph as a function', () {
    test('completes with the result step; graph is disposed after',
        () async {
      final seed = SeedBox();
      final doubled = DoubleBox.late();
      var released = false;

      final pipeline = Pipeline.builder<void, int>()
          .add(seed)
          .add(doubled, input: (d) => d.onlyWhenReady(seed))
          .build(result: doubled)
        ..own(() => released = true);

      expect(await pipeline.start(), 2);
      expect(released, isTrue, reason: 'one-shot: disposed on completion');
    });

    test('fails fast on a required step error — no hang', () async {
      final seed = SeedBox();
      final broken = AlwaysFailBox.late();
      final tail = DoubleBox.late();

      final pipeline = Pipeline.builder<void, int>()
          .add(seed)
          .add(broken, input: (d) => d.onlyWhenReady(seed))
          .add(tail, input: (d) => d.onlyWhenReady(broken))
          .build(result: tail);

      await expectLater(pipeline.start(), throwsStateError);
    });

    test('retry re-drives a flaky step until it succeeds', () async {
      final seed = SeedBox();
      final flaky = FlakyBox.late(failuresBeforeSuccess: 2);

      final pipeline = Pipeline.builder<void, int>()
          .add(seed)
          .add(flaky, input: (d) => d.onlyWhenReady(seed), retry: 2)
          .build(result: flaky);

      expect(await pipeline.start(), 10);
      expect(flaky.attempts, 3);
    });

    test('retries exhausted → the error stands', () async {
      final seed = SeedBox();
      final flaky = FlakyBox.late(failuresBeforeSuccess: 5);

      final pipeline = Pipeline.builder<void, int>()
          .add(seed)
          .add(flaky, input: (d) => d.onlyWhenReady(seed), retry: 2)
          .build(result: flaky);

      await expectLater(pipeline.start(), throwsStateError);
      expect(flaky.attempts, 3);
    });

    test('optional step failure: run survives, the wire delivers null',
        () async {
      final seed = SeedBox();
      final broken = AlwaysFailBox.late();
      final sum = SumBox.late();

      final pipeline = Pipeline.builder<void, int>()
          .add(seed)
          .add(broken, input: (d) => d.onlyWhenReady(seed), optional: true)
          .add(sum, input: (d) => (
                a: d.onlyWhenReady(seed),
                b: d.whenReadyOrNull(broken),   // упал → null, едем дальше
              ))
          .build(result: sum);

      expect(await pipeline.start(), 1);
    });

    test('timeout set at build cuts a hang', () async {
      final seed = SeedBox();
      final never = NeverBox.late();

      final pipeline = Pipeline.builder<void, int>()
          .add(seed)
          .add(never, input: (d) => d.onlyWhenReady(seed))
          .build(result: never, timeout: const Duration(milliseconds: 50));

      await expectLater(pipeline.start(), throwsA(isA<TimeoutException>()));
    });

    test('second start returns the same future', () async {
      final seed = SeedBox();
      final doubled = DoubleBox.late();
      final pipeline = Pipeline.builder<void, int>()
          .add(seed)
          .add(doubled, input: (d) => d.onlyWhenReady(seed))
          .build(result: doubled);

      final first = pipeline.start();
      final second = pipeline.start();
      expect(identical(first, second), isTrue);
      expect(await first, 2);
    });

    test('result must be a declared step — loud at build', () {
      final seed = SeedBox();
      final stray = DoubleBox.late();
      expect(
        () => Pipeline.builder<void, int>()
            .add(seed)
            .build(result: stray),
        throwsStateError,
      );
    });

    test('a pipeline is a graph: the map still draws', () async {
      final seed = SeedBox();
      final doubled = DoubleBox.late();
      final pipeline = Pipeline.builder<void, int>()
          .add(seed)
          .add(doubled, input: (d) => d.onlyWhenReady(seed))
          .build(result: doubled);

      await pipeline.start();
      expect(pipeline.toMermaid(), contains('SeedBox --> DoubleBox'));
    });
  });
}
