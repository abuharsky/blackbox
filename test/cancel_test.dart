import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

void main() {
  group('Cancel / _cancelGuarded', () {
    test('cancel function is called at most once', () {
      var calls = 0;
      final c = cancelGuardedForTest(() => calls++);

      c();
      c();
      c();

      expect(calls, 1);
    });

    test('cancel can be a no-op and should not throw on repeated calls', () {
      final c = cancelGuardedForTest(() {});
      expect(() => c(), returnsNormally);
      expect(() => c(), returnsNormally);
    });
  });
}
