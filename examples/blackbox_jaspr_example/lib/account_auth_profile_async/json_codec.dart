import 'dart:convert';

import 'package:blackbox/blackbox.dart';

import 'boxes/models.dart';

class JsonCodec<T> implements PersistentCodec<T> {
  const JsonCodec(this.fromJson, this.toJson);

  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T value) toJson;

  @override
  Object? encode(T value) {
    return jsonEncode(toJson(value));
  }

  @override
  T decode(Object? stored) {
    return fromJson(jsonDecode(stored as String) as Map<String, dynamic>);
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
