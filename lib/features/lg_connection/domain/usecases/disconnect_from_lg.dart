import '../repositories/lg_repository.dart';

class DisconnectFromLg {
  final LgRepository repository;
  DisconnectFromLg(this.repository);

  Future<void> call() {
    return repository.disconnect();
  }
}
