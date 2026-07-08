import 'package:flutter_test/flutter_test.dart';
import 'package:climate_storyteller/features/climate_data/climate_data_service.dart';
import 'package:climate_storyteller/features/lg_connection/lg_service.dart';

void main() {
  group('ClimateDataService Tests', () {
    late ClimateDataService service;
    late LgService lgService;

    setUp(() {
      lgService = LgService();
      service = ClimateDataService(lgService: lgService);
    });

    test('should fallback directly to historical baseline for year 1900', () async {
      final stats = await service.getStatsForYear(1900);
      expect(stats.year, 1900);
      expect(stats.tempAnomaly, 0.0);
      expect(stats.source, contains('historical baseline'));
    });

    test('should fallback directly to projection for year 2100', () async {
      final stats = await service.getStatsForYear(2100);
      expect(stats.year, 2100);
      expect(stats.tempAnomaly, 3.2);
      expect(stats.source, contains('SSP3-7.0 projection'));
    });

    test('should fallback to interpolated local data when remote call fails', () async {
      final stats = await service.getStatsForYear(2026);
      expect(stats.year, 2026);
      expect(stats.tempAnomaly, 1.3); // Interpolated temperature anomaly for 2026
      expect(stats.source, contains('NOAA live data + IPCC AR6'));
    });
  });
}
