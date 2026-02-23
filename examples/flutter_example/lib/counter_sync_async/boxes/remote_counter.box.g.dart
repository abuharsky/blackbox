// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'remote_counter.dart';

// **************************************************************************
// BlackboxGenerator
// **************************************************************************

class RemoteCounter extends AsyncBoxWithInput<int, int> {
  final _RemoteCounter _impl;
  bool _initialized = false;

  RemoteCounter._({required int input, int? initialValue})
      : _impl = _RemoteCounter(),
        super(input, initialValue: initialValue) {}

  factory RemoteCounter({required int input}) {
    final int? initialValue = null;
    final box = RemoteCounter._(input: input, initialValue: initialValue);
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

    return _impl._compute(input, previousOutputValue);
  }

  @override
  AsyncOutput<int> get output {
    BoxObserver.trackBox(this);
    return super.output;
  }
}
