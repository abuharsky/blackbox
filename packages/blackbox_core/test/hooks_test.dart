import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

final class _CounterBox extends NoInputBox<int> {
  late final count = state(0);

  @override
  int compute() => count.value;
}

final class _Sink implements BoxHooksSink {
  final reads = <OutputSource<dynamic>>[];

  @override
  void onRead(OutputSource<dynamic> source) => reads.add(source);
}

void main() {
  late List<OutputSource<dynamic>> untracked;

  setUp(() {
    untracked = [];
    BoxHooks.onUntrackedRead = untracked.add;
  });
  tearDown(() => BoxHooks.onUntrackedRead = null);

  test('a read outside any sink reaches onUntrackedRead', () {
    final box = _CounterBox();
    expect(box.value, 0);
    expect(untracked, [box]);
  });

  test('a read inside a sink goes to the sink only', () {
    final box = _CounterBox();
    final sink = _Sink();
    BoxHooks.runWith(sink, () => box.value);
    expect(sink.reads, [box]);
    expect(untracked, isEmpty);
  });

  test('untracked: a deliberate snapshot — neither the sink nor the hook',
      () {
    final box = _CounterBox();
    final sink = _Sink();
    final value =
        BoxHooks.runWith(sink, () => BoxHooks.untracked(() => box.value));
    expect(value, 0);
    expect(sink.reads, isEmpty);
    expect(untracked, isEmpty);
  });

  test('a sink nested inside untracked tracks again', () {
    final box = _CounterBox();
    final sink = _Sink();
    BoxHooks.untracked(() => BoxHooks.runWith(sink, () => box.value));
    expect(sink.reads, [box]);
    expect(untracked, isEmpty);
  });

  test('no hook installed — reads are silent', () {
    BoxHooks.onUntrackedRead = null;
    expect(_CounterBox().value, 0);
  });
}
