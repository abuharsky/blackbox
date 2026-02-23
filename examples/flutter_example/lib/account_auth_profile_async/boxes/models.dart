import 'package:flutter/foundation.dart';

@immutable
class Service {
  final String id;
  final String name;

  const Service({required this.id, required this.name});

  @override
  String toString() => name;

  static Service fromJsonStatic(Map<String, dynamic> json) {
    return Service(name: json["name"], id: json["id"]);
  }

  static Map<String, dynamic> toJsonStatic(Service instance) {
    return {"name": instance.name, "id": instance.id};
  }
}

@immutable
class Session {
  final String token;
  final Service service;

  const Session({required this.token, required this.service});

  @override
  String toString() => 'Session(${service.name})';

  static Session fromJsonStatic(Map<String, dynamic> json) => Session(
        token: json["token"],
        service: Service.fromJsonStatic(json["service"]),
      );

  static Map<String, dynamic> toJsonStatic(Session instance) => {
        "token": instance.token,
        "service": Service.toJsonStatic(instance.service)
      };
}

@immutable
class Profile {
  final Service service;
  final String displayName;
  final String userId;

  const Profile(
      {required this.service, required this.displayName, required this.userId});

  @override
  String toString() => '$displayName ($userId)';
}
