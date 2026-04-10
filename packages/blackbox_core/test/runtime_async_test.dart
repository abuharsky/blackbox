import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('_AsyncRuntime via AsyncBox/NoInputAsyncBox', () {
    test('async input box starts in loading and then emits data', () async {
      final b = ControlledAsyncInputBox(1);

      final seen = <AsyncOutput<int>>[];
      final cancel = b.listen((o) => seen.add(o as AsyncOutput<int>));

      // immediate initial state is loading (runtime sets it before completion)
      expect(seen.isNotEmpty, isTrue);
      expect(seen.last, isA<AsyncLoading<int>>());

      b.completerFor(1).complete(42);
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, isA<AsyncData<int>>());
      expect((seen.last as AsyncData<int>).value, 42);

      cancel();
    });

    test('async versioning ignores stale results', () async {
      final b = ControlledAsyncInputBox(1);

      final seen = <AsyncOutput<int>>[];
      final cancel = b.listen((o) => seen.add(o as AsyncOutput<int>));

      // trigger first computation (input=1 already started)
      // switch to input=2 before completing 1
      updateAsyncInputForTest(b, 2);

      // complete old (1) after switching
      b.completerFor(1).complete(10);
      // complete new (2)
      b.completerFor(2).complete(20);

      await Future<void>.delayed(Duration.zero);

      // last must be 20, not 10
      expect(seen.last, isA<AsyncData<int>>());
      expect((seen.last as AsyncData<int>).value, 20);

      cancel();
    });

    test('async emits error state on failure', () async {
      final b = ControlledAsyncInputBox(1);

      final seen = <AsyncOutput<int>>[];
      final cancel = b.listen((o) => seen.add(o as AsyncOutput<int>));

      final err = StateError('fail');
      b.completerFor(1).completeError(err, StackTrace.current);
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, isA<AsyncError<int>>());
      final last = seen.last as AsyncError<int>;
      expect(last.error, err);

      cancel();
    });

    test('cancel stops further async emissions', () async {
      final b = ControlledAsyncInputBox(1);

      final seen = <AsyncOutput<int>>[];
      final cancel = b.listen((o) => seen.add(o as AsyncOutput<int>));

      cancel();
      b.completerFor(1).complete(123);
      await Future<void>.delayed(Duration.zero);

      // still only initial loading emission(s)
      expect(seen.any((e) => e is AsyncData<int>), isFalse);
    });

    test('async lateinit starts in AsyncLoading before initialization', () {
      final b = ControlledAsyncLateinitBox();

      // output returns AsyncLoading before runtime exists
      expect(b.output, isA<AsyncLoading<int>>());
      expect(b.valueOrNull, isNull);
    });

    test('async lateinit listen delivers AsyncLoading then real states', () async {
      final b = ControlledAsyncLateinitBox();

      final seen = <AsyncOutput<int>>[];
      b.listen((o) => seen.add(o as AsyncOutput<int>));

      // Before init: listener gets AsyncLoading immediately
      expect(seen.length, 1);
      expect(seen.last, isA<AsyncLoading<int>>());

      // Initialize via graph input
      updateAsyncInputForTest(b, 5);

      // After init: listener is flushed to runtime, gets Loading from recompute
      expect(seen.last, isA<AsyncLoading<int>>());

      // Complete the computation
      b.completerFor(5).complete(50);
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, isA<AsyncData<int>>());
      expect((seen.last as AsyncData<int>).value, 50);
    });

    test('async lateinit pending listener cancel works', () async {
      final b = ControlledAsyncLateinitBox();

      final seen = <AsyncOutput<int>>[];
      final cancel = b.listen((o) => seen.add(o as AsyncOutput<int>));

      expect(seen.length, 1); // AsyncLoading

      cancel();

      // Initialize — cancelled listener should not receive anything
      updateAsyncInputForTest(b, 1);
      b.completerFor(1).complete(10);
      await Future<void>.delayed(Duration.zero);

      expect(seen.length, 1); // still just the initial AsyncLoading
    });

    test('AsyncBox without input recomputes on signal/rotate', () async {
      final b = ControlledAsyncBox();

      final seen = <AsyncOutput<int>>[];
      final cancel = b.listen((o) => seen.add(o as AsyncOutput<int>));

      // should be loading initially
      expect(seen.last, isA<AsyncLoading<int>>());

      b.completer.complete(1);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, isA<AsyncData<int>>());
      expect((seen.last as AsyncData<int>).value, 1);

      b.rotate(); // signal => loading again
      expect(seen.last, isA<AsyncLoading<int>>());

      b.completer.complete(2);
      await Future<void>.delayed(Duration.zero);
      expect((seen.last as AsyncData<int>).value, 2);

      cancel();
    });
  });
}
