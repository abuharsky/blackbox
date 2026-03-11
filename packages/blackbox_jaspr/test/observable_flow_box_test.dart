import 'package:blackbox/blackbox.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';

final class _CounterState extends FlowState {
  final int value;

  const _CounterState(this.value);

  @override
  bool operator ==(Object other) =>
      other is _CounterState && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class _CounterBox extends Box<int> {
  _CounterBox(this._value) : super(initialValue: _value);

  int _value;

  void setValue(int value) {
    action(() {
      _value = value;
    });
  }

  @override
  int compute(int? previous) => _value;
}

void main() {
  test('FlowBox exposes tracked state directly through output', () {
    final source = _CounterBox(3);
    final flow = FlowBox.builder<_CounterState>()
        .on<int>(source, (value) => _CounterState(value))
        .build(initial: const _CounterState(0));

    expect(flow.state, const _CounterState(3));
    expect(flow.output.value, const _CounterState(3));

    flow.dispose();
  });

  testComponents('FlowBox rebuilds BoxObserver on flow updates', (
    tester,
  ) async {
    final source = _CounterBox(1);
    final flow = FlowBox.builder<_CounterState>()
        .on<int>(source, (value) => _CounterState(value))
        .build(initial: const _CounterState(0));

    tester.pumpComponent(
      BoxObserver(builder: (_) => Component.text('${flow.output.value.value}')),
    );

    expect(find.text('1'), findsOneComponent);

    source.setValue(2);

    await tester.pump();
    await tester.pump();

    expect(find.text('2'), findsOneComponent);

    flow.dispose();
  });
}
