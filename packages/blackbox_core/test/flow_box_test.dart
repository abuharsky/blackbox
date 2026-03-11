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
  int get hashCode => Object.hash(T, value);
}

void main() {
  group('FlowBox', () {
    test('onLoading and onError accept only async output sources by type', () {
      final sync = SpySyncBox(1);
      final async = ControlledAsyncBox();

      expect(sync is AsyncOutputSource<int>, isFalse);
      expect(async is AsyncOutputSource<int>, isTrue);
    });

    test('sync source overrides initial immediately', () {
      final src = SpySyncBox(1);

      final flow = FlowBox.builder<TestFlowState<String>>()
          .on<int>(src, (v) => TestFlowState('v=$v'))
          .build(initial: const TestFlowState('init'));

      final seen = <TestFlowState<String>>[];
      final cancel = flow.listen((out) => seen.add(out.value));

      expect(seen, [const TestFlowState('v=1')]);

      cancel();
      flow.dispose();
    });

    test('sync output changes update flow state', () {
      final src = SpySyncBox(1);

      final flow = FlowBox.builder<TestFlowState<String>>()
          .on<int>(src, (v) => TestFlowState('v=$v'))
          .build(initial: const TestFlowState('init'));

      final seen = <TestFlowState<String>>[];
      final cancel = flow.listen((out) => seen.add(out.value));

      src.setValue(2);
      src.setValue(3);

      expect(
          seen,
          [
            const TestFlowState('v=1'),
            const TestFlowState('v=2'),
            const TestFlowState('v=3'),
          ],
          reason:
              'FlowBox listens to source and emits mapped values; includes first sync value');

      cancel();
      flow.dispose();
    });

    test('mapper can return null to ignore updates', () {
      final src = SpySyncBox(1);

      final flow = FlowBox.builder<TestFlowState<int>>()
          .on<int>(src, (v) => v.isEven ? TestFlowState(v) : null)
          .build(initial: const TestFlowState(0));

      final seen = <TestFlowState<int>>[];
      final cancel = flow.listen((out) => seen.add(out.value));

      // initial sync output is 1 => ignored
      expect(seen, [const TestFlowState(0)]);

      src.setValue(2);
      src.setValue(3);
      src.setValue(4);

      expect(seen, [
        const TestFlowState(0),
        const TestFlowState(2),
        const TestFlowState(4),
      ]);

      cancel();
      flow.dispose();
    });

    test('async loading does not update flow; async data does', () async {
      final src = ControlledAsyncInputBox(1);

      final flow = FlowBox.builder<TestFlowState<String>>()
          .on<int>(src, (v) => TestFlowState('v=$v'))
          .build(initial: const TestFlowState('init'));

      final seen = <TestFlowState<String>>[];
      final cancel = flow.listen((out) => seen.add(out.value));

      // No async data yet.
      expect(seen, [const TestFlowState('init')]);

      src.completerFor(1).complete(10);
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, const TestFlowState('v=10'));

      cancel();
      flow.dispose();
    });

    test(
        'on, onLoading, and onError can react to loading, data, and error states',
        () async {
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
      final cancel = flow.listen((out) => seen.add(out.value));

      expect(seen, [const TestFlowState('loading')]);

      src.completer.complete(10);
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, const TestFlowState('data=10'));

      src.rotate();
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, const TestFlowState('loading'));

      src.completer.completeError(StateError('boom'), StackTrace.current);
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, const TestFlowState('error:StateError'));

      cancel();
      flow.dispose();
    });

    test('flow supports re-entrant updates in listener (queue behavior)', () {
      final src = SpySyncBox(1);

      final flow = FlowBox.builder<TestFlowState<int>>()
          .on<int>(src, (v) => TestFlowState(v))
          .build(initial: const TestFlowState(0));

      var bumped = false;
      final seen = <TestFlowState<int>>[];
      final cancel = flow.listen((out) {
        final state = out.value;
        seen.add(state);
        if (state == const TestFlowState(1) && !bumped) {
          bumped = true;
          src.setValue(2);
        }
      });

      expect(seen.contains(const TestFlowState(1)), isTrue);
      expect(seen.contains(const TestFlowState(2)), isTrue);

      cancel();
      flow.dispose();
    });

    test('cancel stops further flow emissions', () {
      final src = SpySyncBox(1);

      final flow = FlowBox.builder<TestFlowState<String>>()
          .on<int>(src, (v) => TestFlowState('v=$v'))
          .build(initial: const TestFlowState('init'));

      final seen = <TestFlowState<String>>[];
      final cancel = flow.listen((out) => seen.add(out.value));

      cancel();
      src.setValue(2);

      expect(seen.contains(const TestFlowState('v=2')), isFalse);

      flow.dispose();
    });
  });
}
