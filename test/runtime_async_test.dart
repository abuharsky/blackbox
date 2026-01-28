import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('_AsyncRuntime via AsyncBoxWithInput/AsyncBox', () {
    test('async input box starts in loading and then emits data', () async {
      final b = ControlledAsyncInputBox(1);

      final seen = <AsyncOutput<int>>[];
      final cancel = b.listen((o) => seen.add(o));

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
      final cancel = b.listen((o) => seen.add(o));

      // trigger first computation (input=1 already started)
      // switch to input=2 before completing 1
      updateInputForTest(b, 2);

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
      final cancel = b.listen((o) => seen.add(o));

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
      final cancel = b.listen((o) => seen.add(o));

      cancel();
      b.completerFor(1).complete(123);
      await Future<void>.delayed(Duration.zero);

      // still only initial loading emission(s)
      expect(seen.any((e) => e is AsyncData<int>), isFalse);
    });

    test('AsyncBox without input recomputes on signal/rotate', () async {
      final b = ControlledAsyncBox();

      final seen = <AsyncOutput<int>>[];
      final cancel = b.listen((o) => seen.add(o));

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
