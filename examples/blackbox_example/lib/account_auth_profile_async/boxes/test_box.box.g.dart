// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'test_box.dart';

// **************************************************************************
// BlackboxGenerator
// **************************************************************************

class TestBoxInput {
  final String input1;
  final int input2;
  final dynamic Function() input3;

  const TestBoxInput({
    required this.input1,
    required this.input2,
    required this.input3,
  });
}

class TestBox extends LazyBox<TestBoxInput, String?>
    with ObservableOutputSource<String?> {
  TestBox({
    required TestBoxInput input,
  }) : super(create: (_) => _$TestBox(input: input));

  @override
  AsyncOutput<String?> get output {
    reportRead();
    return super.output;
  }
}

class _$TestBox extends AsyncBoxWithInput<TestBoxInput, String?>
    with ObservableOutputSource<String?> {
  final _TestBox _impl;

  _$TestBox._({required TestBoxInput input, String? initialValue})
      : _impl = _TestBox(),
        super(input, initialValue: initialValue) {}

  factory _$TestBox({required TestBoxInput input}) {
    final String? initialValue = null;
    final box = _$TestBox._(input: input, initialValue: initialValue);
    return box;
  }

  @override
  Future<String?> compute(TestBoxInput input, String? previousOutputValue) {
    return _impl.compute(
        input.input1, input.input2, input.input3, previousOutputValue);
  }

  @override
  AsyncOutput<String?> get output {
    reportRead();
    return super.output;
  }
}
