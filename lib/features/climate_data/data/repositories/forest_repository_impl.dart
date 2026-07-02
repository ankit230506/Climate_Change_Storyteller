import '../../domain/repositories/forest_repository.dart';
import '../datasources/forest_remote_data_source.dart';
import '../../../lg_connection/domain/repositories/lg_repository.dart';

class ForestRepositoryImpl implements ForestRepository {
  final ForestRemoteDataSource remoteDataSource;
  final LgRepository lgRepository;

  ForestRepositoryImpl({
    required this.remoteDataSource,
    required this.lgRepository,
  });

  @override
  String buildDeforestationKml({required String regionId, int year = 2023}) {
    return remoteDataSource.buildDeforestationKml(regionId: regionId, year: year);
  }

  @override
  String buildComparisonKml({required String regionId}) {
    return remoteDataSource.buildComparisonKml(regionId: regionId);
  }

  @override
  Future<void> sendToLG({required String regionId, int year = 2023}) async {
    final kml = buildDeforestationKml(regionId: regionId, year: year);
    final filename = 'forest_${regionId}_$year.kml';
    await lgRepository.sendKml(filename, kmlContent: kml);

    final bbox = remoteDataSource.getBBox(regionId);
    final latSpan = (bbox.north - bbox.south).abs();
    final lonSpan = (bbox.east - bbox.west).abs();
    final span = latSpan > lonSpan ? latSpan : lonSpan;
    final altitude = span * 110000 * 2.5;

    await lgRepository.flyTo(
      latitude: (bbox.north + bbox.south) / 2,
      longitude: (bbox.east + bbox.west) / 2,
      altitude: altitude,
    );
  }
}
