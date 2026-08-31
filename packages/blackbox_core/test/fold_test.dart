import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

final class StepBox extends NoInputBox<int> {
  late final _v = state(1);
  @override
  int compute() => _v.value;
  void set(int next) => _v.value = next;
}

final class SlowDoubleBox extends AsyncBox<int, int> {
  SlowDoubleBox.late() : super.late();
  @override
  Future<int> compute(int input) async => input * 2;
}

/// A fold over a phase: loading/error/data are data, not obstacles.
final class PhaseLabelBox extends Box<Output<int>, String> {
  PhaseLabelBox.late() : super.late(initialValue: 'idle');
  @override
  String compute(Output<int> phase) => switch (phase) {
        AsyncLoading<int>() => 'loading',
        AsyncData<int>(:final value) => 'data:$value',
        AsyncError<int>() => 'error',
        SyncData<int>(:final value) => 'sync:$value',
      };
}

void main() {
  group('outputOf — the fold primitive', () {
    test('delivers the phase: the fold runs during loading and on data',
        () async {
      final step = StepBox();
      final slow = SlowDoubleBox.late();
      final label = PhaseLabelBox.late();

      final g = Graph.builder()
          .add(step)
          .add(slow, input: (d) => d.onlyWhenReady(step))
          .add(label, input: (d) => d.outputOf(slow))
          .build();
      await g.settled();
      await Future<void>.delayed(Duration.zero);
      await g.settled();

      expect(label.value, 'data:2');

      step.set(5);
      await g.settled();
      await Future<void>.delayed(Duration.zero);
      await g.settled();
      expect(label.value, 'data:10');
      g.dispose();
    });

    test('outputs compare by content — dedup works on phases', () {
      expect(const AsyncData(5), equals(const AsyncData(5)));
      expect(const AsyncLoading<int>(), equals(const AsyncLoading<int>()));
      expect(const SyncData('a'), equals(const SyncData('a')));
      expect(const AsyncData(5), isNot(equals(const AsyncData(6))));
    });

    test('deprecated whenReady alias still forwards to onlyWhenReady',
        () async {
      final step = StepBox();
      final label = PhaseLabelBox.late();
      final g = Graph.builder()
          .add(step)
          // ignore: deprecated_member_use_from_same_package
          .add(label, input: (d) => SyncData(d.whenReady(step)))
          .build();
      await g.settled();
      expect(label.value, 'sync:1');
      g.dispose();
    });
  });
}
