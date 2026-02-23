import 'dart:async';

import 'package:test/test.dart';
import 'package:blackbox/blackbox.dart';

import 'test_helpers.dart';

Future<void> flushMicrotasks([int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Async sum box to avoid premature completion on constructor SyncOutput(0).
/// This makes "mixed sync+async deps" testable with current Pipeline.run().
final class AsyncSumBox extends AsyncBoxWithInput<({int a, int b}), int> {
  AsyncSumBox() : super((a: 0, b: 0));

  @override
  Future<int> compute(({int a, int b}) input, previous) async {
    // microtask boundary to be explicit
    await Future<void>.delayed(Duration.zero);
    return input.a + input.b;
  }
}

void main() {
  group('Pipeline (current semantics)', () {
    test('single sync box: returns value', () async {
      final box = SpySyncBox(42);

      final pipeline = PipelineBuilder().add(box).result(box).build();

      final result = await pipeline.run();
      expect(result, 42);
    });

    test('single async box: returns value when AsyncData arrives', () async {
      final box = ControlledAsyncBox();

      final pipeline = PipelineBuilder().add(box).result(box).build();

      scheduleMicrotask(() => box.completer.complete(10));

      final result = await pipeline.run();
      expect(result, 10);
    });

    test(
        'mixed sync+async dependencies: completes when async result box becomes ready',
        () async {
      final a = SpySyncBox(3);
      final b = ControlledAsyncBox();
      final sum = AsyncSumBox();

      final pipeline = PipelineBuilder()
          .add(a)
          .add(b)
          .addWithDependencies(
            sum,
            dependencies: (d) => (
              a: d.require<int>(a),
              b: d.require<int>(b),
            ),
          )
          .result(sum)
          .build();

      // Complete async upstream later
      scheduleMicrotask(() => b.completer.complete(4));

      final result = await pipeline.run();
      expect(result, 7);
    });

    test('propagates async error', () async {
      final box = ControlledAsyncBox();

      final pipeline = PipelineBuilder().add(box).result(box).build();

      scheduleMicrotask(() {
        box.completer.completeError(
          StateError('boom'),
          StackTrace.current,
        );
      });

      expect(
        () => pipeline.run(),
        throwsA(isA<StateError>()),
      );
    });

    test('run() can be called only once', () async {
      final box = SpySyncBox(1);

      final pipeline = PipelineBuilder().add(box).result(box).build();

      final r1 = await pipeline.run();
      expect(r1, 1);

      expect(
        () => pipeline.run(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
