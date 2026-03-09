import 'dart:math';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';

part 'remote_step_config.box.g.dart';

@box
@observable
class _RemoteStepConfig {
  late int _stepConfig;

  @boxInit
  void init(int input, int? previousOutput) {
    _stepConfig = input;
  }

  @boxCompute
  Future<int> compute(int newStepConfig, int? previous) async {
    await Future.delayed(Duration(milliseconds: (Random().nextInt(3) + 1) * 350));
    _stepConfig = newStepConfig;
    return _stepConfig;
  }
}
