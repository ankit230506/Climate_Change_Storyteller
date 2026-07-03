import '../repositories/lg_repository.dart';

class ConnectToLg {
  final LgRepository repository;
  ConnectToLg(this.repository);

  Future<bool> call({
    required String ipAddress,
    int port = 22,
    String username = 'lg',
    String password = 'lg',
    int screenCount = 5,
  }) {
    return repository.connect(
      ipAddress: ipAddress,
      port: port,
      username: username,
      password: password,
      screenCount: screenCount,
    );
  }
}
