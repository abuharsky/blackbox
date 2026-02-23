// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'remote_step_config.dart';

// **************************************************************************
// BlackboxGenerator
// **************************************************************************

class RemoteStepConfig extends AsyncBoxWithInput<int, int> {
  final _RemoteStepConfig _impl;
  bool _initialized = false;

  RemoteStepConfig._({required int input, int? initialValue})
      : _impl = _RemoteStepConfig(),
        super(input, initialValue: initialValue) {}

  factory RemoteStepConfig({required int input}) {
    final int? initialValue = null;
    final box = RemoteStepConfig._(input: input, initialValue: initialValue);
    return box;
  }

  @override
  @protected
  @visibleForOverriding
  Future<int> compute(int input, int? previousOutputValue) {
    if (!_initialized) {
      _initialized = true;
      _impl.init(input, previousOutputValue);
    }

    return _impl.compute(input, previousOutputValue);
  }

  @override
  AsyncOutput<int> get output {
    BoxObserver.trackBox(this);
    return super.output;
  }
}
