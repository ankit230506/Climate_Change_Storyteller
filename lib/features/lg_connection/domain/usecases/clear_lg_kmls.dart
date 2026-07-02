import '../repositories/lg_repository.dart';

class ClearLgKmls {
  final LgRepository repository;
  ClearLgKmls(this.repository);

  Future<void> call() {
    return repository.clearKml();
  }
}
