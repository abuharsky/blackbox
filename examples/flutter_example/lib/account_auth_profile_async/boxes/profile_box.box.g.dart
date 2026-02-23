// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'profile_box.dart';

// **************************************************************************
// BlackboxGenerator
// **************************************************************************

class ProfileBox extends AsyncBoxWithInput<AsyncOutput<Session?>, Profile?> {
  final _ProfileBox _impl;

  ProfileBox._({required AsyncOutput<Session?> input, Profile? initialValue})
      : _impl = _ProfileBox(),
        super(input, initialValue: initialValue) {}

  factory ProfileBox({required AsyncOutput<Session?> input}) {
    final Profile? initialValue = null;
    final box = ProfileBox._(input: input, initialValue: initialValue);
    return box;
  }

  @override
  @protected
  @visibleForOverriding
  Future<Profile?> compute(
      AsyncOutput<Session?> input, Profile? previousOutputValue) {
    return _impl._compute(input, previousOutputValue);
  }

  @override
  AsyncOutput<Profile?> get output {
    BoxObserver.trackBox(this);
    return super.output;
  }
}
