import '../../domain/entities/climate_stats.dart';
import '../../domain/repositories/climate_repository.dart';
import '../datasources/climate_local_data_source.dart';
import '../datasources/climate_remote_data_source.dart';

class ClimateRepositoryImpl implements ClimateRepository {
  final ClimateRemoteDataSource remoteDataSource;
  final ClimateLocalDataSource localDataSource;

  ClimateRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<ClimateStats> getStatsForYear(int year, {String? noaaKey}) async {
    if (year <= 1900) {
      return ClimateStats(
        year: 1900,
        tempAnomaly: localDataSource.getInterpolatedTemperature(1900),
        seaLevelMm: localDataSource.getInterpolatedSeaLevel(1900),
        iceExtentMkm2: localDataSource.getInterpolatedIceExtent(1900),
        forestLossPct: localDataSource.getInterpolatedForestLoss(1900),
        source: 'IPCC AR6 historical baseline',
      );
    }

    if (year >= 2100) {
      return ClimateStats(
        year: 2100,
        tempAnomaly: localDataSource.getInterpolatedTemperature(2100),
        seaLevelMm: localDataSource.getInterpolatedSeaLevel(2100),
        iceExtentMkm2: localDataSource.getInterpolatedIceExtent(2100),
        forestLossPct: localDataSource.getInterpolatedForestLoss(2100),
        source: 'IPCC AR6 SSP3-7.0 projection',
      );
    }

    // Try live API calls for the present
    double tempAnomaly;
    double seaLevelMm;
    double iceExtentMkm2;

    try {
      tempAnomaly = await remoteDataSource.fetchTempAnomaly(noaaApiKey: noaaKey);
    } catch (_) {
      tempAnomaly = localDataSource.getInterpolatedTemperature(year);
    }

    try {
      final msl = await remoteDataSource.fetchSeaLevel();
      // Convert to mm above 1900 baseline using IPCC reference
      final baseline1900 = localDataSource.getInterpolatedSeaLevel(1900);
      seaLevelMm = baseline1900 + msl;
    } catch (_) {
      seaLevelMm = localDataSource.getInterpolatedSeaLevel(year);
    }

    try {
      iceExtentMkm2 = await remoteDataSource.fetchArcticIceExtent();
    } catch (_) {
      iceExtentMkm2 = localDataSource.getInterpolatedIceExtent(year);
    }

    final forestLossPct = localDataSource.getInterpolatedForestLoss(year);

    return ClimateStats(
      year: year,
      tempAnomaly: tempAnomaly,
      seaLevelMm: seaLevelMm,
      iceExtentMkm2: iceExtentMkm2,
      forestLossPct: forestLossPct,
      source: 'NOAA live data + IPCC AR6',
    );
  }

  @override
  Future<double> getTempAnomaly({String? noaaApiKey}) async {
    try {
      return await remoteDataSource.fetchTempAnomaly(noaaApiKey: noaaApiKey);
    } catch (_) {
      return localDataSource.getInterpolatedTemperature(DateTime.now().year);
    }
  }

  @override
  Future<double> getSeaLevel() async {
    try {
      final msl = await remoteDataSource.fetchSeaLevel();
      final baseline1900 = localDataSource.getInterpolatedSeaLevel(1900);
      return baseline1900 + msl;
    } catch (_) {
      return localDataSource.getInterpolatedSeaLevel(DateTime.now().year);
    }
  }

  @override
  Future<double> getArcticIceExtent() async {
    try {
      return await remoteDataSource.fetchArcticIceExtent();
    } catch (_) {
      return localDataSource.getInterpolatedIceExtent(DateTime.now().year);
    }
  }
}
