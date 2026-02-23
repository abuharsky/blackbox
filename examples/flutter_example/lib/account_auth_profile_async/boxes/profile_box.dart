import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox/blackbox.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

part 'profile_box.box.g.dart';

@box
@observable
class _ProfileBox {
  Profile? _profile;

  @boxCompute
  /// Loads profile data from the resolved auth session.
  ///
  /// Returns `null` for loading/error or when there is no active session.
  Future<Profile?> _compute(
      AsyncOutput<Session?> session, Profile? previous) async {
    return session.when(data: (session) async {
      if (session == null) {
        _profile = null;
        return null;
      }

      await Future.delayed(const Duration(seconds: 2));

      _profile = Profile(
        service: session.service,
        displayName: 'Test Name',
        userId: session.token,
      );

      return _profile;
    }, loading: () {
      return null;
    }, error: (_, __) {
      return null;
    });
  }
}
