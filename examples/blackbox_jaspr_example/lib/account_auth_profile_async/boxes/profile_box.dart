import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';

import 'models.dart';

part 'profile_box.box.g.dart';

@box
@observable
class _ProfileBox {
  Profile? _profile;

  @boxCompute
  Future<Profile?> _compute(
    AsyncOutput<Session?> session,
    Profile? previous,
  ) async {
    return session.when(
      data: (session) async {
        if (session == null) {
          _profile = null;
          return null;
        }

        await Future<void>.delayed(const Duration(milliseconds: 850));
        _profile = Profile(
          service: session.service,
          displayName: 'Demo User',
          userId: session.token,
        );
        return _profile;
      },
      loading: () => null,
      error: (_, __) => null,
    );
  }
}
