import 'models.dart';

/// Fake API client. In a real app this would be an HTTP client.
class Api {
  Future<List<Service>> fetchServices() async {
    await Future.delayed(const Duration(seconds: 1));
    return const [
      Service(id: 'google', name: 'Google'),
      Service(id: 'github', name: 'GitHub'),
      Service(id: 'apple', name: 'Apple'),
    ];
  }

  Future<Session> login(Service service) async {
    await Future.delayed(const Duration(seconds: 1));
    return Session(
      token: DateTime.now().millisecondsSinceEpoch.toString(),
      service: service,
    );
  }

  Future<Profile> fetchProfile(Session session) async {
    await Future.delayed(const Duration(seconds: 1));
    return Profile(
      service: session.service,
      displayName: 'John Doe',
      userId: session.token,
    );
  }
}
