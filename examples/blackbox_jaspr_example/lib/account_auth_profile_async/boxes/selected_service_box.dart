import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_jaspr_example/account_auth_profile_async/json_codec.dart';

import 'models.dart';

part 'selected_service_box.box.g.dart';

@box
@persistent(
  keyBuilder: _SelectedServiceBox._persistentKey,
  codec: ServiceJsonCodec,
)
class _SelectedServiceBox {
  static String _persistentKey(List<Service>? services) =>
      '_SelectedServiceBox';

  Service? _selected;

  @boxInit
  void _init(List<Service>? services, Service? previous) {
    _selected = previous;
  }

  @boxCompute
  Service? _compute(List<Service>? services, Service? previous) {
    return _selected;
  }

  @boxAction
  void select(Service service) {
    _selected = service;
  }
}
