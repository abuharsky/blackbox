import 'package:blackbox/blackbox.dart';

import 'api.dart';
import 'models.dart';

class AuthBox extends AsyncBox<Service, Session?> {
  final Api _api;

  // Session memory lives in a slot per service: switching the service
  // re-slots the cell (that service's saved session, or null) — one
  // service's session can never leak into another's.
  late final _session = state<Session?>(
    null,
    persistFor: (service) => '_AuthBox_${service.id}',
  );

  AuthBox(this._api, {required Service input}) : super(input);

  @override
  Future<Session?> compute(Service service, Session? previous) async {
    // Belt-and-braces: never show a session that belongs to another
    // service, even if a slot ever contained one.
    final session = _session.value;
    if (session != null && session.service.id != service.id) return null;
    return session;
  }

  Future<void> login() async => _session.value = await _api.login(input);

  void logout() => _session.value = null;
}
