import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

// ─────────────────────────────────────────────────────────────────────
// Fixtures

/// Upstream driver the graph feeds late boxes from.
final class StepBox extends NoInputBox<int> {
  late final _v = state(1);
  @override
  int compute() => _v.value;
  void set(int next) => _v.value = next;
}

/// Sync late box with a non-nullable output and an initialValue.
final class DoubleBox extends Box<int, int> {
  DoubleBox.late() : super.late(initialValue: 0);
  @override
  int compute(int input) => input * 2;
}

/// Sync late box with a non-nullable output and NO initialValue —
/// silent until the first input.
final class SilentDoubleBox extends Box<int, int> {
  SilentDoubleBox.late() : super.late();
  @override
  int compute(int input) => input * 2;
}

/// Sync late box with a nullable output — ready with null immediately.
final class MaybeLabelBox extends Box<int, String?> {
  MaybeLabelBox.late() : super.late();
  @override
  String? compute(int input) => 'v$input';
}

/// Sync late box with memory: checks cells + buttons after first input.
final class LateCounterBox extends Box<int, int> {
  LateCounterBox.late() : super.late(initialValue: 0);
  late final _count = state(0);
  @override
  int compute(int step) => _count.value;
  void inc() => _count.value += input;
}

/// Async late box via the folded-in AsyncBox.late.
final class AsyncDoubleBox extends AsyncBox<int, int> {
  AsyncDoubleBox.late({super.initialValue}) : super.late();
  @override
  Future<int> compute(int input) async => input * 2;
}

void main() {
  group('Box.late (sync)', () {
    test('with initialValue: ready before the first input', () {
      final box = DoubleBox.late();
      expect(box.value, 0);
      expect(box.output, isA<SyncData<int>>());
    });

    test('without initialValue: no output until the first input', () {
      final box = SilentDoubleBox.late();
      expect(() => box.value, throwsStateError);
      expect(() => box.output, throwsStateError);
      expect(box.valueOrNull, isNull);
    });

    test('nullable output: ready with null before the first input', () {
      final box = MaybeLabelBox.late();
      expect(box.value, isNull);
    });

    test('graph delivers the first input, box computes', () async {
      final step = StepBox();
      final box = DoubleBox.late();
      final g = Graph.builder()
          .add(step)
          .add(box, input: (d) => d.onlyWhenReady(step))
          .build();
      await g.settled();

      expect(box.value, 2);

      step.set(5);
      await g.settled();
      expect(box.value, 10);
      g.dispose();
    });

    test('dependents of a silent late box wait, then flow', () async {
      final step = StepBox();
      final silent = SilentDoubleBox.late();
      final downstream = DoubleBox.late();
      final g = Graph.builder()
          .add(step)
          .add(silent, input: (d) => d.onlyWhenReady(step))
          .add(downstream, input: (d) => d.onlyWhenReady(silent))
          .build();
      await g.settled();

      expect(silent.value, 2);
      expect(downstream.value, 4);
      g.dispose();
    });

    test('listener subscribed before the first input gets the first emission',
        () async {
      final step = StepBox();
      final box = SilentDoubleBox.late();
      final seen = <int>[];
      box.listen((o) => seen.add((o as SyncData<int>).value));

      final g = Graph.builder()
          .add(step)
          .add(box, input: (d) => d.onlyWhenReady(step))
          .build();
      await g.settled();

      expect(seen, [2]);
      g.dispose();
    });

    test('action before the first input throws a clear StateError', () {
      final box = LateCounterBox.late();
      expect(() => box.inc(), throwsA(isA<Error>()));
    });

    test('buttons and cells work after the first input', () async {
      final step = StepBox();
      final box = LateCounterBox.late();
      final g = Graph.builder()
          .add(step)
          .add(box, input: (d) => d.onlyWhenReady(step))
          .build();
      await g.settled();

      box.inc();
      expect(box.value, 1);

      step.set(5);
      await g.settled();
      box.inc();
      expect(box.value, 6);
      g.dispose();
    });
  });

  group('AsyncBox.late', () {
    test('loading before the first input; data after', () async {
      final step = StepBox();
      final box = AsyncDoubleBox.late();
      expect(box.output, isA<AsyncLoading<int>>());

      final g = Graph.builder()
          .add(step)
          .add(box, input: (d) => d.onlyWhenReady(step))
          .build();
      await g.settled();
      await Future<void>.delayed(Duration.zero);
      await g.settled();

      expect(box.output, isA<AsyncData<int>>());
      expect(box.requireValue, 2);
      g.dispose();
    });

    test('initialValue shows as AsyncData before the first input', () {
      final box = AsyncDoubleBox.late(initialValue: 42);
      expect(box.requireValue, 42);
    });

    test('action before the first input throws', () {
      final box = AsyncDoubleBox.late();
      expect(() => box.refresh(), throwsStateError);
    });
  });

  group('graph.boxes', () {
    test('declared boxes in declaration order, ready for a provider', () {
      final step = StepBox();
      final box = DoubleBox.late();
      final g = Graph.builder()
          .add(step)
          .add(box, input: (d) => d.onlyWhenReady(step))
          .build(start: false);

      expect(g.boxes, [step, box]);
      expect(g.boxes, everyElement(isA<ProvidableBox>()));
      g.dispose();
    });

    test('multibox appears as the composite; lazy children are not listed',
        () async {
      final step = StepBox();
      final mb = _EchoMultiBox();
      final tail = DoubleBox.late();
      final g = Graph.builder()
          .add(step)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady(step))
          .add(tail, input: (d) => d.onlyWhenReady(mb.echo))
          .build();
      await g.settled();

      expect(g.boxes, [step, mb, tail]);
      expect(tail.value, 2);
      g.dispose();
    });
  });

  group('graph.box<T>()', () {
    test('finds the single declared box of the type', () {
      final step = StepBox();
      final box = DoubleBox.late();
      final g = Graph.builder()
          .add(step)
          .add(box, input: (d) => d.onlyWhenReady(step))
          .build(start: false);

      expect(g.box<StepBox>(), same(step));
      expect(g.box<DoubleBox>(), same(box));
      g.dispose();
    });

    test('throws loudly when the type is not declared', () {
      final g = Graph.builder().add(StepBox()).build(start: false);
      expect(() => g.box<DoubleBox>(), throwsStateError);
      g.dispose();
    });

    test('throws loudly on twins — type lookup cannot tell them apart', () {
      final g =
          Graph.builder().add(StepBox()).add(StepBox()).build(start: false);
      expect(() => g.box<StepBox>(), throwsStateError);
      g.dispose();
    });
  });

  group('MultiBox.input', () {
    test('throws before the first input, current after', () async {
      final step = StepBox();
      final mb = _EchoMultiBox();
      expect(() => mb.input, throwsStateError);

      final g = Graph.builder()
          .add(step)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady(step))
          .build();
      await g.settled();
      expect(mb.input, 1);

      step.set(7);
      await g.settled();
      expect(mb.input, 7);
      g.dispose();
    });

    test('inside compute the getter already holds the new input', () async {
      final step = StepBox();
      final mb = _InputEchoMultiBox();
      final g = Graph.builder()
          .add(step)
          .addMultiBox(mb, input: (d) => d.onlyWhenReady(step))
          .build();
      await g.settled();

      expect(mb.seenViaGetter, [1]);

      step.set(3);
      await g.settled();
      expect(mb.seenViaGetter, [1, 3]);
      g.dispose();
    });
  });
}

/// Records what the `input` getter returns during compute — proves the
/// getter is current inside compute, not one cycle behind.
final class _InputEchoMultiBox extends MultiBox<int> {
  final seenViaGetter = <int>[];

  @override
  void compute(int _) => seenViaGetter.add(input);
}

final class _EchoMultiBox extends MultiBox<int> {
  late final echo = child(0);
  @override
  void compute(int input) => dispatch(echo, input);
}
