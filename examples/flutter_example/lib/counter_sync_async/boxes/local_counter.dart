import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/foundation.dart';

part 'local_counter.box.g.dart';

@box
@observable
@persistent(
  keyBuilder: _LocalCounter._persistentKey,
  codec: IdentityCodec<int>,
  store: SharedPrefsStore,
)
class _LocalCounter {
  /// Returns a stable key for persisted local counter value.
  static String _persistentKey(int input) => "_LocalCounter";

  late int _step;
  int _value = 0;

  @boxInit
  /// Initializes counter state from input step and cached value.
  _init(int initialStepConfig, int? cachedValue) {
    _step = initialStepConfig;
    _value = cachedValue ?? initialStepConfig;
  }

  @boxCompute
  /// Updates the step configuration and returns current counter value.
  int _compute(int newStepConfig, int? previousOutput) {
    _step = newStepConfig;
    return _value;
  }

  @boxAction
  /// Increments the counter by the current step.
  void inc() => _value += _step;

  @boxAction
  /// Decrements the counter by the current step.
  void dec() => _value -= _step;
}
