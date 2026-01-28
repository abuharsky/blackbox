import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

void main() {
  group('Output readiness + value extension', () {
    test('isReady is true for SyncOutput and AsyncData', () {
      expect(isReadyForTest(const SyncOutput<int>(1)), isTrue);
      expect(isReadyForTest(const AsyncData<int>(1)), isTrue);
    });

    test('isReady is false for AsyncLoading and AsyncError', () {
      expect(isReadyForTest(const AsyncLoading<int>()), isFalse);
      expect(isReadyForTest(AsyncError<int>('x', StackTrace.current)), isFalse);
    });

    test('value returns underlying value for ready outputs', () {
      expect(const SyncOutput<int>(7).value, 7);
      expect(const AsyncData<int>(9).value, 9);
    });
  });
}
