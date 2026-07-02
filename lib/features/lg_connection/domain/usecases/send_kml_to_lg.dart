import '../repositories/lg_repository.dart';

class SendKmlToLg {
  final LgRepository repository;
  SendKmlToLg(this.repository);

  Future<void> call(String kmlFilename, {String? kmlContent}) {
    return repository.sendKml(kmlFilename, kmlContent: kmlContent);
  }
}
