import '../repositories/forest_repository.dart';

class GetForestData {
  final ForestRepository repository;
  GetForestData(this.repository);

  String buildDeforestationKml({required String regionId, int year = 2023}) {
    return repository.buildDeforestationKml(regionId: regionId, year: year);
  }

  String buildComparisonKml({required String regionId}) {
    return repository.buildComparisonKml(regionId: regionId);
  }

  Future<void> sendToLG({required String regionId, int year = 2023}) {
    return repository.sendToLG(regionId: regionId, year: year);
  }
}
