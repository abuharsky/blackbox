import 'package:blackbox/blackbox.dart';

import 'models.dart';

class SelectedServiceBox extends Box<List<Service>, Service?> {
  late final _selected =
      state<Service?>(null, persist: '_SelectedServiceBox');

  SelectedServiceBox({required List<Service> input}) : super(input);

  @override
  Service? compute(List<Service> services) {
    // Reconciliation is the formula's job: remember the pick, but only
    // show it while it exists in the current list.
    final selected = _selected.value;
    if (selected == null) return null;
    return services.any((s) => s.id == selected.id) ? selected : null;
  }

  void select(Service service) => _selected.value = service;
}
