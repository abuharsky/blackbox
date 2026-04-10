import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Output readiness + value extension', () {
    test('isReady is true for SyncData and AsyncData', () {
      expect(isReadyForTest(const SyncData<int>(1)), isTrue);
      expect(isReadyForTest(const AsyncData<int>(1)), isTrue);
    });

    test('isReady is false for AsyncLoading and AsyncError', () {
      expect(isReadyForTest(const AsyncLoading<int>()), isFalse);
      expect(isReadyForTest(AsyncError<int>('x', StackTrace.current)), isFalse);
    });

    test('value returns underlying value for ready outputs', () {
      expect(const SyncData<int>(7).value, 7);
      expect(const AsyncData<int>(9).value, 9);
    });
  });

  group('OutputSource.valueOrNull', () {
    test('returns sync value for ready sync source', () {
      final OutputSource<int> source = SpySyncBox(7);

      expect(source.valueOrNull, 7);
    });

    test('returns null while async source is loading', () {
      final OutputSource<int> source = ControlledAsyncInputBox(1);

      expect(source.valueOrNull, isNull);
    });

    test('returns async value after async source resolves', () async {
      final source = ControlledAsyncInputBox(1);
      final OutputSource<int> outputSource = source;

      source.completerFor(1).complete(42);
      await Future<void>.delayed(Duration.zero);

      expect(outputSource.valueOrNull, 42);
    });

    test('returns null when reading output throws StateError', () {
      final OutputSource<int> source = _ThrowingOutputSource<int>();

      expect(source.valueOrNull, isNull);
    });
  });

  group('OutputSource.requireValue', () {
    test('returns sync value for ready sync source', () {
      final OutputSource<int> source = SpySyncBox(11);

      expect(source.requireValue, 11);
    });

    test('returns async value after async source resolves', () async {
      final source = ControlledAsyncInputBox(1);
      final OutputSource<int> outputSource = source;

      source.completerFor(1).complete(99);
      await Future<void>.delayed(Duration.zero);

      expect(outputSource.requireValue, 99);
    });

    test('throws with output state when async source is not ready', () {
      final OutputSource<int> source = ControlledAsyncInputBox(1);

      expect(
        () => source.requireValue,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('AsyncLoading<int>'),
          ),
        ),
      );
    });
  });
}

final class _ThrowingOutputSource<T> implements OutputSource<T> {
  @override
  Output<T> get output => throw StateError('not ready');

  @override
  Cancel listen(void Function(Output<T>) listener, {bool skipFirst = false}) => () {};
}
