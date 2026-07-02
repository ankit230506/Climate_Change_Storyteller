import '../entities/climate_stats.dart';

abstract class ClimateRepository {
  Future<ClimateStats> getStatsForYear(int year, {String? noaaKey});
  Future<double> getTempAnomaly({String? noaaApiKey});
  Future<double> getSeaLevel();
  Future<double> getArcticIceExtent();
}
