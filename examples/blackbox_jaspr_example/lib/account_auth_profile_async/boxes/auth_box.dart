import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:blackbox_jaspr_example/account_auth_profile_async/json_codec.dart';

import 'models.dart';

part 'auth_box.box.g.dart';

@box
@lazy
@observable
@persistent(
  keyBuilder: _AuthBox._persistentKey,
  store: LocalStorageStore,
  codec: SessionJsonCodec,
)
class _AuthBox {
  static String _persistentKey(Service service) => '_AuthBox_${service.id}';

  late Service _service;
  Session? _session;
  Completer<Session>? _completer;

  @boxInit
  void _init(Service service, Session? previousOutput) {
    _session = previousOutput;
    _service = service;
  }

  @boxCompute
  Future<Session?> _compute(Service service, Session? previous) async {
    if (_service != service) {
      _service = service;
      _session = null;
    }

    if (_completer != null) {
      _session = await _completer!.future;
      _completer = null;
    }

    return _session;
  }

  @boxAction
  Future<void> login() async {
    _completer = Completer<Session>();
    await Future<void>.delayed(const Duration(seconds: 1));
    _completer?.complete(Session(
      token: DateTime.now().millisecondsSinceEpoch.toString(),
      service: _service,
    ));
  }

  @boxAction
  void logout() {
    _session = null;
  }
}
