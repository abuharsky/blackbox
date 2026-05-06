import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

void main() {
  group('ValueStateBox', () {
    test('exposes initial value as SyncData immediately', () {
      final box = value<int>(42);

      expect(box.output, isA<SyncData<int>>());
      expect(box.value, 42);
    });

    test('emits initial state to new listeners by default', () {
      final box = value<String>('hello');

      final seen = <String>[];
      box.listen((o) => seen.add((o as SyncData<String>).value));

      expect(seen, ['hello']);
    });

    test('skipFirst suppresses the initial replay', () {
      final box = value<int>(7);

      final seen = <int>[];
      box.listen((o) => seen.add((o as SyncData<int>).value), skipFirst: true);

      expect(seen, isEmpty);
    });

    test('updateInputForTest drives compute (identity) and notifies', () {
      final box = value<int>(0);

      final seen = <int>[];
      box.listen((o) => seen.add((o as SyncData<int>).value));

      updateInputForTest(box, 1);
      updateInputForTest(box, 2);

      expect(seen, [0, 1, 2]);
      expect(box.value, 2);
    });

    test('factory and class are equivalent', () {
      final a = value<int>(1);
      final b = ValueStateBox<int>(1);

      expect(a, isA<ValueStateBox<int>>());
      expect(b, isA<Box<int, int>>());
    });

    test('cancel removes listener', () {
      final box = value<int>(0);

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
}
