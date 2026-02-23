// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'selected_service_box.dart';

// **************************************************************************
// BlackboxGenerator
// **************************************************************************

class SelectedServiceBox extends BoxWithInput<List<Service>?, Service?> {
  final Persistent<Service?> _persistent;
  final _SelectedServiceBox _impl;
  bool _initialized = false;

  SelectedServiceBox._(
      {required List<Service>? input,
      required Persistent<Service?> persistent,
      Service? initialValue})
      : _impl = _SelectedServiceBox(),
        _persistent = persistent,
        super(input, initialValue: initialValue) {
    _persistent.attach(this);
  }

  factory SelectedServiceBox({required List<Service>? input}) {
    final persistent = Persistent<Service?>(
      key: _SelectedServiceBox._persistentKey(input),
      store: SharedPrefsStore(),
      codec: ServiceJsonCodec(),
    );
    final initialValue = persistent.load();
    final box = SelectedServiceBox._(
        input: input, persistent: persistent, initialValue: initialValue);
    return box;
  }

  @override
  @protected
  @visibleForOverriding
  Service? compute(List<Service>? input, Service? previousOutputValue) {
    if (!_initialized) {
      _initialized = true;
      _impl._init(input, previousOutputValue);
    }

    return _impl._compute(input, previousOutputValue);
  }

  void select(Service service) => action(() => _impl.select(service));

  @override
  SyncOutput<Service?> get output {
    BoxObserver.trackBox(this);
    return super.output;
  }
}
