// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'step_config.dart';

// **************************************************************************
// BlackboxGenerator
// **************************************************************************

class StepConfig extends Box<int> {
  final _StepConfig _impl;

  StepConfig._({int? initialValue})
      : _impl = _StepConfig(),
        super(initialValue: initialValue) {}

  factory StepConfig() {
    final int? initialValue = null;
    final box = StepConfig._(initialValue: initialValue);
    return box;
  }

  @override
  @protected
  @visibleForOverriding
  int compute(int? previousOutputValue) {
    return _impl._compute(previousOutputValue);
  }

  void inc() => action(() => _impl.inc());

  void dec() => action(() => _impl.dec());

  @override
  SyncOutput<int> get output {
    BoxObserver.trackBox(this);
    return super.output;
  }
}
