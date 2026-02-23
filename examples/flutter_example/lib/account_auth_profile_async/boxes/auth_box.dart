import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_example/account_auth_profile_async/json_codec.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

part 'auth_box.box.g.dart';

@box
@lazy
@observable
@persistent(
  keyBuilder: _AuthBox._persistentKey,
  store: SharedPrefsStore,
  codec: SessionJsonCodec,
)
class _AuthBox {
  /// Builds a stable persistence key for each service-specific auth session.
  static String _persistentKey(Service service) => "_AuthBox_${service.id}";

  late Service _service;
  Session? _session;

  Completer? _completer;

  @boxInit
  /// Initializes internal state from input and previously persisted output.
  void _init(Service service, Session? previousOutput) {
    _session = previousOutput;
    _service = service;
  }

  @boxCompute
  /// Resolves current session for [service], handling pending login completion.
  Future<Session?> _compute(Service service, Session? previous) async {
    // если не залогинен — валидный data(null)
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
  /// Starts a simulated login flow and stores the resulting session.
  Future<void> login() async {
    _completer = Completer();
    await Future.delayed(const Duration(seconds: 2));

    _completer?.complete(Session(
      token: DateTime.now().millisecondsSinceEpoch.toString(),
      service: _service,
    ));
  }

  @boxAction
  /// Clears the currently authenticated session.
  void logout() {
    _session = null;
  }
}
