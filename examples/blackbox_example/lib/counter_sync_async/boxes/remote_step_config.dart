import 'dart:math';

import 'package:blackbox/blackbox.dart';

class RemoteStepConfig extends AsyncBox<int, int> {
  late int _stepConfig;

  RemoteStepConfig({required int input}) : super(input);

  @override
  void prepare(int input, int? previous) {
    _stepConfig = input;
  }

  @override
  Future<int> compute(int input, int? previous) async {
    await Future.delayed(Duration(seconds: Random().nextInt(3) + 1));
    _stepConfig = input;
    return _stepConfig;
  }
}
