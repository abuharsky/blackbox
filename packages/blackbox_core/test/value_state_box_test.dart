// ignore_for_file: deprecated_member_use_from_same_package
import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('ValueStateBox', () {
    test('exposes initial value as SyncData immediately', () {
      final box = valueBox<int>(42);

      expect(box.output, isA<SyncData<int>>());
      expect(box.value, 42);
    });

    test('emits initial state to new listeners by default', () {
      final box = valueBox<String>('hello');

      final seen = <String>[];
      box.listen((o) => seen.add((o as SyncData<String>).value));

      expect(seen, ['hello']);
    });

    test('skipFirst suppresses the initial replay', () {
      final box = valueBox<int>(7);

      final seen = <int>[];
      box.listen((o) => seen.add((o as SyncData<int>).value), skipFirst: true);

      expect(seen, isEmpty);
    });

    test('updateInputForTest drives compute (identity) and notifies', () {
      final box = valueBox<int>(0);

      final seen = <int>[];
      box.listen((o) => seen.add((o as SyncData<int>).value));

      updateInputForTest(box, 1);
      updateInputForTest(box, 2);

      expect(seen, [0, 1, 2]);
      expect(box.value, 2);
    });

    test('factory and class are equivalent', () {
      final a = valueBox<int>(1);
      final b = ValueStateBox<int>(1);

      expect(a, isA<ValueStateBox<int>>());
      expect(b, isA<Box<int, int>>());
    });

    test('cancel removes listener', () {
      final box = valueBox<int>(0);

      final seen = <int>[];
      final cancel = box.listen(
        (o) => seen.add((o as SyncData<int>).value),
        skipFirst: true,
      );

      updateInputForTest(box, 1);
      expect(seen, [1]);

      cancel();
      updateInputForTest(box, 2);
      expect(seen, [1]);
    });
  });

  group('ValueStateBox distinct', () {
    test('equal values do not re-notify by default', () {
      final box = valueBox<String>('idle');

      final seen = <String>[];
      box.listen((o) => seen.add((o as SyncData<String>).value),
          skipFirst: true);

      // Native streams routinely re-emit identical values.
      updateInputForTest(box, 'idle');
      updateInputForTest(box, 'idle');
      updateInputForTest(box, 'playing');
      updateInputForTest(box, 'playing');
      updateInputForTest(box, 'paused');

      expect(seen, ['playing', 'paused']);
    });

    test('distinct: false re-notifies on every push', () {
      final box = valueBox<String>('idle', distinct: false);

      final seen = <String>[];
      box.listen((o) => seen.add((o as SyncData<String>).value),
          skipFirst: true);

      updateInputForTest(box, 'idle');
      updateInputForTest(box, 'idle');

      expect(seen, ['idle', 'idle']);
    });

    test('distinct suppresses graph pump churn from duplicate emissions',
        () async {
      final source = valueBox<String>('a');
      final consumer = SpySyncInputBox(-1);

      Graph.builder()
          .add(source)
          .add(consumer, input: (d) => d.whenReady<String>(source).length)
          .build();

      await Future<void>.delayed(Duration.zero);
      final callsAfterStart = consumer.computeCalls;

      // Duplicate pushes are absorbed by the distinct cell: no emission,
      // no pump, no downstream recompute.
      updateInputForTest(source, 'a');
      updateInputForTest(source, 'a');
      await Future<void>.delayed(Duration.zero);

      expect(consumer.computeCalls, callsAfterStart);
    });
  });
}
