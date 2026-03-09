import 'package:meta/meta.dart';

@immutable
class Service {
  const Service({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  @override
  String toString() => name;

  static Service fromJsonStatic(Map<String, dynamic> json) {
    return Service(name: json['name'] as String, id: json['id'] as String);
  }

  static Map<String, dynamic> toJsonStatic(Service instance) {
    return {'name': instance.name, 'id': instance.id};
  }
}

@immutable
class Session {
  const Session({
    required this.token,
    required this.service,
  });

  final String token;
  final Service service;

  @override
  String toString() => 'Session(${service.name})';

  static Session fromJsonStatic(Map<String, dynamic> json) {
    return Session(
      token: json['token'] as String,
      service: Service.fromJsonStatic(json['service'] as Map<String, dynamic>),
    );
  }

  static Map<String, dynamic> toJsonStatic(Session instance) {
    return {
      'token': instance.token,
      'service': Service.toJsonStatic(instance.service),
    };
  }
}

@immutable
class Profile {
  const Profile({
    required this.service,
    required this.displayName,
    required this.userId,
  });

  final Service service;
  final String displayName;
  final String userId;

  @override
  String toString() => '$displayName ($userId)';
}
