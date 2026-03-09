import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';

import 'models.dart';

part 'services_loader_box.box.g.dart';

@box
@observable
class _ServicesLoaderBox {
  List<Service>? _services;
  bool _odd = false;

  @boxCompute
  Future<List<Service>?> _compute(List<Service>? previous) async {
    await Future.delayed(const Duration(milliseconds: 900));

    _odd = !_odd;
    _services = [
      const Service(id: 'google', name: 'Google'),
      const Service(id: 'facebook', name: 'Facebook'),
      if (_odd) const Service(id: 'instagram', name: 'Instagram'),
    ];

    return _services;
  }

  @boxAction
  void reload() {
    _services = [];
  }
}
