import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('_SyncRuntime via BoxWithInput/Box', () {
    test('sync box output is immediately available without listen', () {
      final b = SpySyncBox(1);

      expect(b.output, isA<SyncOutput<int>>());
      expect(b.output.value, 1);
    });

    test('sync box output updates after signal without listen', () {
      final b = SpySyncBox(1);

      expect(b.output.value, 1);

      b.setValue(2);

      expect(b.output.value, 2);
    });

    test('sync input box emits initial output to listener', () {
      final b = SpySyncInputBox(1);

      expect(b.output, isA<SyncOutput<int>>());
      expect(b.output.value, 1);

      final seen = <Output<int>>[];
      final cancel = b.listen(seen.add);

      expect(seen.length, 1);
      expect(seen.first, isA<SyncOutput<int>>());
      expect((seen.first as SyncOutput<int>).value, 1);

      expect(b.computeCalls, greaterThanOrEqualTo(1)); // ключевой инвариант

      cancel();
    });

    test('setInput triggers recompute and listener is called', () {
      final b = SpySyncInputBox(1);

      final seen = <int>[];
      final cancel = b.listen((o) => seen.add(o.value));

      // initial
      expect(seen, [1]);

      // change input
      updateInputForTest(b, 2);
      expect(seen, [1, 2]);

      // same input should be skipped at graph node level, but not here:
      // runtime recomputes; since SyncOutput has identity equality, it will emit.
      updateInputForTest(b, 2);
      expect(seen, [1, 2, 2]);

      cancel();
    });

    test('signal recomputes after body', () {
      final b = SpySyncBox(10);

      final seen = <int>[];
      final cancel = b.listen((o) => seen.add(o.value));

      expect(seen, [10]);
      b.setValue(11); // uses signal internally
      expect(seen, [10, 11]);

      cancel();
    });

    test('cancel returned from listen stops further emissions', () {
      final b = SpySyncInputBox(1);

      final seen = <int>[];
      final cancel = b.listen((o) => seen.add(o.value));

      expect(seen, [1]);

      cancel();
      updateInputForTest(b, 2);
      expect(seen, [1]);
    });
  });
}
