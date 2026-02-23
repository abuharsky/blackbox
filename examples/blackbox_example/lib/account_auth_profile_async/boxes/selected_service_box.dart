import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox/blackbox.dart';
import 'package:blackbox_example/account_auth_profile_async/json_codec.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

part 'selected_service_box.box.g.dart';

@box
@observable
@persistent(
  keyBuilder: _SelectedServiceBox._persistentKey,
  store: SharedPrefsStore,
  codec: ServiceJsonCodec,
)
class _SelectedServiceBox {
  /// Returns a single persistence key for selected service state.
  static String _persistentKey(_) => "_SelectedServiceBox";

  Service? _selected;

  @boxInit
  /// Restores the last selected service from persisted output.
  _init(List<Service>? services, Service? previous) {
    _selected = previous;
  }

  @boxCompute
  /// Exposes the currently selected service.
  Service? _compute(List<Service>? services, Service? previous) {
    // if (services == null ||
    //     services.isEmpty ||
    //     services.where((e) => e.id == _selected?.id).isEmpty) {
    //   _selected = null;
    // }
    return _selected;
  }

  @boxAction
  /// Updates the current service selection.
  void select(Service service) {
    _selected = service;
  }
}
