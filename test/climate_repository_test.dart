import 'package:flutter_test/flutter_test.dart';
import 'package:climate_storyteller/features/climate_data/data/repositories/climate_repository_impl.dart';
import 'package:climate_storyteller/features/climate_data/data/datasources/climate_local_data_source.dart';
import 'package:climate_storyteller/features/climate_data/data/datasources/climate_remote_data_source.dart';

class FakeClimateRemoteDataSource extends ClimateRemoteDataSource {
  @override
  Future<double> fetchTempAnomaly({String? noaaApiKey}) async => 1.25;

  @override
  Future<double> fetchSeaLevel() async => 102.4;

  @override
  Future<double> fetchArcticIceExtent() async => 4.67;
}

void main() {
  group('ClimateRepositoryImpl Tests', () {
    late ClimateRepositoryImpl repository;
    late ClimateLocalDataSourceImpl localDataSource;
    late FakeClimateRemoteDataSource remoteDataSource;

    setUp(() {
      localDataSource = ClimateLocalDataSourceImpl();
      remoteDataSource = FakeClimateRemoteDataSource();
      repository = ClimateRepositoryImpl(
        localDataSource: localDataSource,
        remoteDataSource: remoteDataSource,
      );
    });

    test('should fetch live stats for 2026', () async {
      final stats = await repository.getStatsForYear(2026);
      expect(stats.tempAnomaly, 1.25);
      expect(stats.source, contains('NOAA'));
    });

    test('should fallback to local data for historical year 1900', () async {
      final stats = await repository.getStatsForYear(1900);
      expect(stats.tempAnomaly, 0.0);
      expect(stats.source, contains('IPCC'));
    });
  });
}
