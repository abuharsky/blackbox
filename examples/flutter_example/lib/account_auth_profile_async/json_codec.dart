import 'dart:convert';

import 'package:blackbox/blackbox.dart';

import 'boxes/models.dart';

class JsonCodec<T> implements PersistentCodec<T> {
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T) toJson;

  const JsonCodec(this.fromJson, this.toJson);

  @override
  Object? encode(T value) {
    return value == null ? null : jsonEncode(toJson(value));
  }

  @override
  T decode(Object? stored) {
    print(stored);
    return fromJson(jsonDecode(stored as String));
  }
}

class ServiceJsonCodec extends JsonCodec<Service> {
  const ServiceJsonCodec()
      : super(Service.fromJsonStatic, Service.toJsonStatic);
}

class SessionJsonCodec extends JsonCodec<Session> {
  const SessionJsonCodec()
      : super(Session.fromJsonStatic, Session.toJsonStatic);
}
