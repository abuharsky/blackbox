import 'dart:math';
import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

part 'remote_step_config.box.g.dart';

@box
@observable
class _RemoteStepConfig {
  late int _stepConfig;

  @boxInit
  /// Initializes remote step configuration.
  init(int input, int? previoutOutput) {
    _stepConfig = input;
  }

  @boxCompute
  /// Simulates a remote step update and returns current step value.
  Future<int> compute(int newStepConfig, previous) async {
    await Future.delayed(Duration(seconds: Random().nextInt(3) + 1));
    _stepConfig = newStepConfig;
    return _stepConfig;
  }
}
