import 'dart:math';

import 'package:blackbox/blackbox.dart';

class RemoteStepConfig extends AsyncBox<int, int> {
  late int _stepConfig;

  RemoteStepConfig({required int input}) : super(input);

  @override
  void onFirstCompute(int input, int? previous) {
    _stepConfig = input;
  }

  @override
  Future<int> compute(int input, int? previous) async {
    await Future.delayed(
      Duration(milliseconds: (Random().nextInt(3) + 1) * 350),
    );
    _stepConfig = input;
    return _stepConfig;
  }
}
