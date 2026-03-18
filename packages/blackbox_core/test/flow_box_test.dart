import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

final class TestFlowState<T> extends FlowState {
  final T value;

  const TestFlowState(this.value);

  @override
  bool operator ==(Object other) =>
      other is TestFlowState<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

void main() {
  group('FlowBox', () {
    test('source type markers are correct', () {
      final sync = SpySyncBox(0);
      final async = ControlledAsyncBox();

      expect(sync is OutputSource<int>, isTrue);
      expect(async is OutputSource<int>, isTrue);
    });

    test('initial value is emitted through listen', () {
      final src = SpySyncBox(1);
      final flow = FlowBox.builder<TestFlowState<String>>()
          .on<int>(src, (v) => TestFlowState('v=$v'))
          .build(initial: const TestFlowState('init'));

      final seen = <TestFlowState<String>>[];
      flow.listenSync((o) => seen.add(o.value));
      expect(seen, [const TestFlowState('v=1')]);
    });

    test('listens to source and emits mapped values', () {
      final src = SpySyncBox(1);

      final flow = FlowBox.builder<TestFlowState<String>>()
          .on<int>(src, (v) => TestFlowState('v=$v'))
          .build(initial: const TestFlowState('init'));

      final seen = <TestFlowState<String>>[];
      flow.listenSync((o) => seen.add(o.value));

      src.setValue(2);
      src.setValue(3);

      expect(
          seen,
          containsAllInOrder([
            const TestFlowState('v=1'),
            const TestFlowState('v=2'),
            const TestFlowState('v=3'),
          ]),
          reason:
              'FlowBox listens to source and emits mapped values; includes first sync value');
    });

    test('null mapping result is ignored (no state change)', () {
      final src = SpySyncBox(0);

      final flow = FlowBox.builder<TestFlowState<int>>()
          .on<int>(src, (v) => v.isEven ? TestFlowState(v) : null)
          .build(initial: const TestFlowState(0));

      final seen = <TestFlowState<int>>[];
      flow.listenSync((o) => seen.add(o.value));

      expect(seen, [const TestFlowState(0)]);

      src.setValue(1); // odd -> null -> skip
      src.setValue(2);
      src.setValue(3); // odd -> null -> skip
      src.setValue(4);

      expect(seen, [
        const TestFlowState(0),
        const TestFlowState(2),
        const TestFlowState(4),
      ]);
    });

    test('dispose stops emissions', () {
      final src = SpySyncBox(1);

      final flow = FlowBox.builder<TestFlowState<String>>()
          .on<int>(src, (v) => TestFlowState('v=$v'))
          .build(initial: const TestFlowState('init'));

      final seen = <TestFlowState<String>>[];
      flow.listenSync((o) => seen.add(o.value));

      expect(seen, [const TestFlowState('v=1')]);

      src.setValue(10);
      expect(seen.last, const TestFlowState('v=10'));

      flow.dispose();
      src.setValue(20);
      expect(seen.last, const TestFlowState('v=10'));
    });

    test('async source with loading/data/error mapping', () async {
      final src = ControlledAsyncBox();

      final flow = FlowBox.builder<TestFlowState<String>>()
          .onLoading<int>(src, () => const TestFlowState('loading'))
          .on<int>(src, (value) => TestFlowState('data=$value'))
          .onError<int>(
            src,
            (error, stackTrace) => TestFlowState('error:${error.runtimeType}'),
          )
          .build(initial: const TestFlowState('init'));

      final seen = <TestFlowState<String>>[];
      flow.listenSync((o) => seen.add(o.value));
      expect(seen, [const TestFlowState('loading')]);

      src.completer.complete(10);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, const TestFlowState('data=10'));

      src.rotate();
      expect(seen.last, const TestFlowState('loading'));

      src.completer.completeError(StateError('fail'), StackTrace.current);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, const TestFlowState('error:StateError'));
    });

    test('re-entrant emit during listener callback is queued', () {
      final src = SpySyncBox(0);

      final flow = FlowBox.builder<TestFlowState<int>>()
          .on<int>(src, (v) => TestFlowState(v))
          .build(initial: const TestFlowState(0));

      var bumped = false;
      final seen = <TestFlowState<int>>[];
      flow.listenSync((state) {
        seen.add(state.value);
        if (state.value == const TestFlowState(1) && !bumped) {
          bumped = true;
          src.setValue(2);
        }
      });
      src.setValue(1);
      expect(seen.contains(const TestFlowState(1)), isTrue);
      expect(seen.contains(const TestFlowState(2)), isTrue);
    });

    test('after dispose, source changes do not affect flow state', () {
      final src = SpySyncBox(1);

      final flow = FlowBox.builder<TestFlowState<String>>()
          .on<int>(src, (v) => TestFlowState('v=$v'))
          .build(initial: const TestFlowState('init'));

      final seen = <TestFlowState<String>>[];
      flow.listenSync((o) => seen.add(o.value));

      flow.dispose();

      src.setValue(2);
      expect(seen.contains(const TestFlowState('v=2')), isFalse);
    });
  });
}
