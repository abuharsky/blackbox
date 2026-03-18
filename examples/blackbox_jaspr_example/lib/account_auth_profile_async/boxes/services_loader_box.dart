import 'package:blackbox/blackbox.dart';

import 'api.dart';
import 'models.dart';

class ServicesLoaderBox extends NoInputAsyncBox<List<Service>> {
  final Api _api;

  ServicesLoaderBox(this._api);

  @override
  Future<List<Service>> computeValue(List<Service>? previous) =>
      _api.fetchServices();

  void refresh() => action(() {});
}
