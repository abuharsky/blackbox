import 'package:blackbox/blackbox.dart';

import 'api.dart';
import 'models.dart';

class AuthBox extends AsyncBox<Service, Session?>
    with AsyncPersisted<Service, Session?> {
  final Api _api;
  late Service _service;
  Session? _session;

  AuthBox(this._api, {required Service input}) : super(input);

  @override
  String persistKeyFor(Service input) => '_AuthBox_${input.id}';

  @override
  void onFirstCompute(Service input, Session? previous) {
    _service = input;
    _session = previous;
  }

  @override
  Future<Session?> compute(Service input, Session? previous) async {
    _service = input;
    if (_session != null && _session!.service.id != input.id) {
      _session = null;
    }
    return _session;
  }

  Future<void> login() => action(() async {
        _session = await _api.login(_service);
      });

  void logout() => action(() => _session = null);
}
