// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'services_loader_box.dart';

// **************************************************************************
// BlackboxGenerator
// **************************************************************************

class ServicesLoaderBox extends AsyncBox<List<Service>?> {
  final _ServicesLoaderBox _impl;

  ServicesLoaderBox._({List<Service>? initialValue})
      : _impl = _ServicesLoaderBox(),
        super(initialValue: initialValue) {}

  factory ServicesLoaderBox() {
    final List<Service>? initialValue = null;
    final box = ServicesLoaderBox._(initialValue: initialValue);
    return box;
  }

  @override
  @protected
  @visibleForOverriding
  Future<List<Service>?> compute(List<Service>? previousOutputValue) {
    return _impl._compute(previousOutputValue);
  }

  void reload() => action(() => _impl.reload());

  @override
  AsyncOutput<List<Service>?> get output {
    BoxObserver.trackBox(this);
    return super.output;
  }
}
