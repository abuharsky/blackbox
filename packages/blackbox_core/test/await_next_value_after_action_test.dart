import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('awaitNextValueAfterAction', () {
    test('waits for the next matching sync value from the same box', () async {
      final box = SpySyncBox(1);

      final value = await awaitNextValueAfterAction<int>(
        box: box,
        action: () => box.setValue(2),
        expected: 2,
      );

      expect(value, 2);
      expect(box.value, 2);
    });

    test('supports action closures with parameters', () async {
      final box = SpySyncBox(1);

      final value = await awaitNextValueAfterAction<int>(
        box: box,
        action: () => box.setValue(3),
        expected: 3,
      );

      expect(value, 3);
    });

    test('waits for the downstream box after upstream action', () async {
      final upstream = SpySyncBox(1);
      final dependent = SpySyncInputBox(0);

      final graph = Graph.builder()
          .add(upstream)
          .add(
            dependent,
            input: (d) => d.whenReady<int>(upstream),
          )
          .build();

      await graph.pumpedOnce();

      final value = await awaitNextValueAfterAction<int>(
        box: dependent,
        action: () => upstream.setValue(5),
        expected: 5,
      );

      expect(value, 5);
      expect(dependent.value, 5);
    });

    test('waits for async data after action', () async {
      final box = ControlledAsyncBox();

      box.completer.complete(1);
      await Future<void>.delayed(Duration.zero);

      final future = awaitNextValueAfterAction<int>(
        box: box,
        action: () {
          box.rotate();
          scheduleMicrotask(() => box.completer.complete(2));
        },
        expected: 2,
      );

      expect(await future, 2);
    });

    test('fails fast when the box emits AsyncError after action', () async {
      final box = ControlledAsyncBox();
      final error = StateError('boom');

      final future = awaitNextValueAfterAction<int>(
        box: box,
        action: () {
          box.rotate();
          scheduleMicrotask(
            () => box.completer.completeError(error, StackTrace.current),
          );
        },
        expected: 2,
        timeout: const Duration(milliseconds: 200),
      );

      await expectLater(future, throwsA(same(error)));
    });

    test('fails when action throws', () async {
      final box = SpySyncBox(1);
      final error = StateError('action failed');

      final future = awaitNextValueAfterAction<int>(
        box: box,
        action: () => throw error,
        expected: 2,
        timeout: const Duration(milliseconds: 200),
      );

      await expectLater(future, throwsA(same(error)));
    });
  });
}
