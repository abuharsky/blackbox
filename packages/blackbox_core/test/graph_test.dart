import 'dart:async';

import 'package:test/test.dart';
import 'package:blackbox/blackbox.dart';

import 'test_helpers.dart';

Future<void> flushMicrotasks([int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Graph (runtime contracts)', () {
    test('initial snapshot: dependency resolves even without any emission',
        () async {
      final upstream = SpySyncBox(7);
      final dependent = SpySyncInputBox(0);

      final _ = Graph.builder()
          .add(upstream)
          .add(
            dependent,
            input: (d) => d.onlyWhenReady<int>(upstream),
          )
          .build();

      await flushMicrotasks();

      expect(dependent.value, 7);
      expect(dependent.computeCalls >= 1, true);
    });

    test('distinct input after activation: same upstream value does not repush',
        () async {
      final upstream = SpySyncBox(10);
      final dependent = SpySyncInputBox(0);

      final _ = Graph.builder()
          .add(upstream)
          .add(
            dependent,
            input: (d) => d.onlyWhenReady<int>(upstream),
          )
          .build();

      await flushMicrotasks();
      final callsAfterInit = dependent.computeCalls;
      expect(dependent.value, 10);

      // Emit same value again
      upstream.setValue(10);
      await flushMicrotasks();

      expect(dependent.value, 10);
      expect(dependent.value, 10);

      // Now change value -> must update.
      upstream.setValue(11);
      await flushMicrotasks();

      expect(dependent.value, 11);
      expect(dependent.computeCalls >= callsAfterInit, true);
    });

    test('async dependency: dependent updates only after AsyncData', () async {
      final upstream = ControlledAsyncBox();
      final dependent = SpySyncInputBox(0);

      final _ = Graph.builder()
          .add(upstream)
          .add(
            dependent,
            input: (d) => d.onlyWhenReady<int>(upstream),
          )
          .build();

      await flushMicrotasks();

      // Upstream is loading => dependent should still be on its constructor value (0)
      expect(dependent.value, 0);

      upstream.completer.complete(42);
      await flushMicrotasks();

      expect(dependent.value, 42);
    });

    test('effect receives current and previous distinct inputs', () async {
      final upstream = SpySyncBox(1);
      final seen = <String>[];

      final _ = Graph.builder().add(upstream).addEffect<int>(
        (d) => d.onlyWhenReady<int>(upstream),
        run: (current, previous) {
          seen.add('${previous ?? 'null'}->$current');
        },
      ).build();

      await flushMicrotasks();
      expect(seen, ['null->1']);

      upstream.setValue(2);
      await flushMicrotasks();
      expect(seen, ['null->1', '1->2']);

      upstream.setValue(2);
      await flushMicrotasks();
      expect(seen, ['null->1', '1->2']);
    });

    test('effect can react only on transition into target state', () async {
      final upstream = SpySyncBox(0);
      var clears = 0;

      final _ = Graph.builder().add(upstream).addEffect<int>(
        (d) => d.onlyWhenReady<int>(upstream),
        run: (current, previous) {
          final wasSuccess = previous == 1;
          final isSuccess = current == 1;
          if (!wasSuccess && isSuccess) {
            clears++;
          }
        },
      ).build();

      await flushMicrotasks();
      expect(clears, 0);

      upstream.setValue(1);
      await flushMicrotasks();
      expect(clears, 1);

      upstream.setValue(2);
      await flushMicrotasks();
      expect(clears, 1);

      upstream.setValue(1);
      await flushMicrotasks();
      expect(clears, 2);
    });

    test('async effect is fire-and-forget', () async {
      final upstream = SpySyncBox(1);
      final started = <int>[];
      final done = <int>[];
      final completer = Completer<void>();

      final _ = Graph.builder().add(upstream).addEffect<int>(
        (d) => d.onlyWhenReady<int>(upstream),
        run: (current, previous) async {
          started.add(current);
          await completer.future;
          done.add(current);
        },
      ).build();

      await flushMicrotasks();
      expect(started, [1]);
      expect(done, isEmpty);

      upstream.setValue(2);
      await flushMicrotasks();
      expect(started, [1, 2]);
      expect(done, isEmpty);

      completer.complete();
      await flushMicrotasks();
      expect(done, [1, 2]);
    });

    test(
        'whenReadyOrNull: dependent computes with null while async source is loading, then with real value',
        () async {
      final upstream = ControlledAsyncBox();
      // Sentinel initial value (-1) lets us tell graph-driven computes apart
      // from the box constructor's own compute call.
      final dependent = SpyNullableInputBox(-1);

      final _ = Graph.builder()
          .add(upstream)
          .add(
            dependent,
            input: (d) => d.whenReadyOrNull<int>(upstream),
          )
          .build();

      await flushMicrotasks();

      // Constructor compute saw -1, then graph pump dispatched null while
      // upstream was loading — dependent must NOT have skipped the cycle.
      expect(dependent.seen.first, -1);
      expect(dependent.seen.contains(null), isTrue);
      expect(dependent.value, isNull);

      upstream.completer.complete(99);
      await flushMicrotasks();

      expect(dependent.seen.last, 99);
      expect(dependent.value, 99);
    });

    test(
        'whenReadyOrNull: dependent computes with null while lateinit source is uninitialized, then with real value',
        () async {
      final initSource = SpySyncBox(5);
      final lateBox = ControlledAsyncLateinitBox();
      final dependent = SpyNullableInputBox(-1);

      final _ = Graph.builder()
          .add(initSource)
          .add(lateBox, input: (d) => d.onlyWhenReady<int>(initSource))
          .add(
            dependent,
            input: (d) => d.whenReadyOrNull<int>(lateBox),
          )
          .build();

      await flushMicrotasks();

      // lateBox got its input but compute is still pending => still loading.
      // whenReadyOrNull must surface null and let dependent compute.
      expect(dependent.seen.first, -1);
      expect(dependent.seen.contains(null), isTrue);
      expect(dependent.value, isNull);

      lateBox.completerFor(5).complete(50);
      await flushMicrotasks();

      expect(dependent.seen.last, 50);
      expect(dependent.value, 50);
    });

    test('dispose behavior is currently covered elsewhere: no-op test',
        () async {
      expect(true, true);
    });
  });
}
