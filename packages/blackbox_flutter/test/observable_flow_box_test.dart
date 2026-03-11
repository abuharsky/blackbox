import 'package:blackbox/blackbox.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
  int _value;

  _CounterBox(this._value) : super(initialValue: _value);

  void setValue(int value) {
    action(() {
      _value = value;
    });
  }

  @override
  int compute(int? previous) => _value;
}

void main() {
  testWidgets('FlowBox rebuilds BoxObserver on flow updates', (tester) async {
    final source = _CounterBox(1);
    final flow = FlowBox.builder<_CounterState>()
        .on<int>(source, (value) => _CounterState(value))
        .build(initial: const _CounterState(0));

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BoxObserver(
          builder: (_) => Text('${flow.output.value.value}'),
        ),
      ),
    );

    expect(find.text('1'), findsOneWidget);

    source.setValue(2);

    await tester.pump();
    await tester.pump();

    expect(find.text('2'), findsOneWidget);

    flow.dispose();
  });

  test('FlowBox exposes tracked state directly through output', () async {
    final source = _CounterBox(3);
    final flow = FlowBox.builder<_CounterState>()
        .on<int>(source, (value) => _CounterState(value))
        .build(initial: const _CounterState(0));

    expect(flow.state, const _CounterState(3));
    expect(flow.output.value, const _CounterState(3));

    flow.dispose();
  });
}
