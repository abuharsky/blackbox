import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

part 'services_loader_box.box.g.dart';

@box
@observable
class _ServicesLoaderBox {
  List<Service>? _services;
  bool _odd = false;

  @boxCompute
  /// Simulates a remote services fetch with alternating result content.
  Future<List<Service>?> _compute(List<Service>? previous) async {
    await Future.delayed(const Duration(seconds: 2));

    _odd = !_odd;

    _services = [
      Service(id: 'google', name: 'Google'),
      Service(id: 'facebook', name: 'Facebook'),
      if (_odd) Service(id: 'instagram', name: 'Instagram'),
    ];

    return _services;
  }

  @boxAction
  /// Triggers a reload state before the next compute pass.
  void reload() {
    _services = [];
  }
}
