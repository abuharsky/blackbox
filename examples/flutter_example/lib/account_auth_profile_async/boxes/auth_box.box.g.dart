// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'auth_box.dart';

// **************************************************************************
// BlackboxGenerator
// **************************************************************************

class AuthBox extends LazyBox<Service, Session?> {
  AuthBox({
    required Service input,
  }) : super(create: (_) => _$AuthBox(input: input));

  Future<void> login() {
    return (requireInner() as _$AuthBox).login();
  }

  void logout() {
    (requireInner() as _$AuthBox).logout();
  }
}

class _$AuthBox extends AsyncBoxWithInput<Service, Session?> {
  final Persistent<Session?> _persistent;
  final _AuthBox _impl;
  bool _initialized = false;

  _$AuthBox._(
      {required Service input,
      required Persistent<Session?> persistent,
      Session? initialValue})
      : _impl = _AuthBox(),
        _persistent = persistent,
        super(input, initialValue: initialValue) {
    _persistent.attach(this);
  }

  factory _$AuthBox({required Service input}) {
    final persistent = Persistent<Session?>(
      key: _AuthBox._persistentKey(input),
      store: SharedPrefsStore(),
      codec: SessionJsonCodec(),
    );
    final initialValue = persistent.load();
    final box = _$AuthBox._(
        input: input, persistent: persistent, initialValue: initialValue);
    return box;
  }

  @override
  @protected
  @visibleForOverriding
  Future<Session?> compute(Service input, Session? previousOutputValue) {
    if (!_initialized) {
      _initialized = true;
      _impl._init(input, previousOutputValue);
    }

    return _impl._compute(input, previousOutputValue);
  }

  Future<void> login() async => action(() async => _impl.login());

  void logout() => action(() => _impl.logout());

  @override
  AsyncOutput<Session?> get output {
    BoxObserver.trackBox(this);
    return super.output;
  }
}
