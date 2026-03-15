import 'package:blackbox/blackbox.dart';

import 'api.dart';
import 'models.dart';

class ProfileBox extends AsyncBox<Session?, Profile?> {
  final Api _api;

  ProfileBox(this._api, {required Session? input}) : super(input);

  @override
  Future<Profile?> compute(Session? input, Profile? previous) async {
    if (input == null) return null;
    return _api.fetchProfile(input);
  }
}
