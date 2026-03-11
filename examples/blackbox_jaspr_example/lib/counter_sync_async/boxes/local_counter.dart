import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';

part 'local_counter.box.g.dart';

@box
@persistent(keyBuilder: _LocalCounter._persistentKey, codec: IdentityCodec<int>)
class _LocalCounter {
  static String _persistentKey(int input) => '_LocalCounter';

  late int _step;
  int _value = 0;

  @boxInit
  void _init(int initialStepConfig, int? cachedValue) {
    _step = initialStepConfig;
    _value = cachedValue ?? initialStepConfig;
  }

  @boxCompute
  int _compute(int newStepConfig, int? previousOutput) {
    _step = newStepConfig;
    return _value;
  }

  @boxAction
  void inc() => _value += _step;

  @boxAction
  void dec() => _value -= _step;
}
