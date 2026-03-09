import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';

part 'step_config.box.g.dart';

@box
@observable
class _StepConfig {
  int _step = 1;

  @boxCompute
  int _compute(int? previous) {
    return _step;
  }

  @boxAction
  void inc() => _step++;

  @boxAction
  void dec() => _step--;
}
