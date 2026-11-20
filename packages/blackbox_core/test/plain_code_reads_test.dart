import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

final class SeedBox extends NoInputBox<int> {
  late final _v = state(1);
  @override
  int compute() => _v.value;
  void set(int v) => _v.value = v;
}

final class LateDouble extends Box<int, int> {
  LateDouble.late({super.initialValue}) : super.late();
  @override
  int compute(int n) => n * 2;
}

final class LateNullable extends Box<int, int?> {
  LateNullable.late() : super.late();
  @override
  int? compute(int n) => n;
}

final class Fetch extends AsyncBox<int, int> {
  Fetch.late() : super.late();
  final Completer<int> gate = Completer();
  @override
  Future<int> compute(int n) => gate.future;
}

void main() {
  group('firstReady', () {
    test('ready now → completes with the current value', () async {
      expect(await SeedBox().firstReady, 1);
    });

    test('not ready yet → completes with the first value, once', () async {
      final seed = SeedBox();
      final doubled = LateDouble.late();
      final graph = Graph.builder()
          .add(seed)
          .add(doubled, input: (d) => d.onlyWhenReady(seed))
          .build();
      expect(doubled.valueOrNull, isNull);
      expect(await doubled.firstReady, 2);
      seed.set(5);
      await graph.settled();
      expect(doubled.valueOrNull, 10);
      graph.dispose();
    });

    test('async: loading is skipped, data completes it', () async {
      final seed = SeedBox();
      final fetch = Fetch.late();
      final graph = Graph.builder()
          .add(seed)
          .add(fetch, input: (d) => d.onlyWhenReady(seed))
          .build();
      var done = false;
      final future = fetch.firstReady.then((v) {
        done = true;
        return v;
      });
      await graph.settled();
      expect(done, isFalse);
      fetch.gate.complete(42);
      expect(await future, 42);
      graph.dispose();
    });
  });

  group('Pipeline result must not be ready before the run', () {
    test('initialValue on the result → build throws', () {
      final seed = SeedBox();
      final result = LateDouble.late(initialValue: 0);
      expect(
        () => Pipeline.builder<void, int>()
            .add(seed)
            .add(result, input: (d) => d.onlyWhenReady(seed))
            .build(result: result),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('already ready'))),
      );
    });

    test('nullable .late() result → build throws', () {
      final seed = SeedBox();
      final result = LateNullable.late();
      expect(
        () => Pipeline.builder<void, int?>()
            .add(seed)
            .add(result, input: (d) => d.onlyWhenReady(seed))
            .build(result: result),
        throwsStateError,
      );
    });
  });
}
