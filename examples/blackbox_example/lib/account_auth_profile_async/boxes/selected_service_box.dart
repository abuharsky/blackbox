import 'package:blackbox/blackbox.dart';

import 'models.dart';

class SelectedServiceBox extends Box<List<Service>, Service?> {
  Service? _selected;

  SelectedServiceBox({required List<Service> input})
      : super(input, persistKey: '_SelectedServiceBox');

  @override
  void prepare(List<Service> input, Service? previous) {
    _selected = previous;
  }

  @override
  Service? compute(List<Service> input, Service? previous) {
    // Clear selection if the service is no longer in the list.
    if (_selected != null && !input.any((s) => s.id == _selected!.id)) {
      _selected = null;
    }
    return _selected;
  }

  void select(Service service) => action(() => _selected = service);
}
