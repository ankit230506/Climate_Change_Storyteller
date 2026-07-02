import '../entities/climate_stats.dart';
import '../repositories/climate_repository.dart';

class GetClimateStats {
  final ClimateRepository repository;
  GetClimateStats(this.repository);

  Future<ClimateStats> call(int year, {String? noaaKey}) {
    return repository.getStatsForYear(year, noaaKey: noaaKey);
  }
}
