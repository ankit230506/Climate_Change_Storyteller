import '../repositories/lg_repository.dart';

class RelaunchLgEarth {
  final LgRepository repository;
  RelaunchLgEarth(this.repository);

  Future<void> call() {
    return repository.relaunchGoogleEarth();
  }
}
