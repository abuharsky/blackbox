import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/foundation.dart';

part 'step_config.box.g.dart';

@box
@observable
class _StepConfig {
  int _step = 1;

  @boxCompute
  /// Returns the current step configuration value.
  int _compute(previous) {
    return _step;
  }

  @boxAction
  /// Increases the step configuration by one.
  void inc() => _step++;

  @boxAction
  /// Decreases the step configuration by one.
  void dec() => _step--;
}
