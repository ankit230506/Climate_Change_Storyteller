abstract class ForestRepository {
  String buildDeforestationKml({required String regionId, int year = 2023});
  String buildComparisonKml({required String regionId});
  Future<void> sendToLG({required String regionId, int year = 2023});
}
