// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'local_counter.dart';

// **************************************************************************
// BlackboxGenerator
// **************************************************************************

class LocalCounter extends BoxWithInput<int, int> {
  final Persistent<int?> _persistent;
  final _LocalCounter _impl;
  bool _initialized = false;

  LocalCounter._(
      {required int input,
      required Persistent<int> persistent,
      int? initialValue})
      : _impl = _LocalCounter(),
        _persistent = persistent,
        super(input, initialValue: initialValue) {
    _persistent.attach(this);
  }

  factory LocalCounter({required int input}) {
    final persistent = Persistent<int>(
      key: _LocalCounter._persistentKey(input),
      store: SharedPrefsStore(),
      codec: IdentityCodec(),
    );
    final initialValue = persistent.load();
    final box = LocalCounter._(
        input: input, persistent: persistent, initialValue: initialValue);
    return box;
  }

  @override
  @protected
  @visibleForOverriding
  int compute(int input, int? previousOutputValue) {
    if (!_initialized) {
      _initialized = true;
      _impl._init(input, previousOutputValue);
    }

    return _impl._compute(input, previousOutputValue);
  }

  void inc() => action(() => _impl.inc());

  void dec() => action(() => _impl.dec());

  @override
  SyncOutput<int> get output {
    BoxObserver.trackBox(this);
    return super.output;
  }
}
