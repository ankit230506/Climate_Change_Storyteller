import 'package:flutter_test/flutter_test.dart';
import 'package:climate_storyteller/services/climate_data_service.dart';

void main() {
  final service = ClimateDataService.instance;

  group('ClimateDataService — historical (1900)', () {
    test('returns IPCC baseline values instantly', () async {
      final stats = await service.getStatsForYear(1900);

      expect(stats.year, 1900);
      expect(stats.tempAnomaly, 0.0);
      expect(stats.seaLevelMm, 0.0);
      expect(stats.source, contains('IPCC'));
      expect(stats.source, contains('historical'));
    });

    test('label getters format correctly', () async {
      final stats = await service.getStatsForYear(1900);
      expect(stats.tempLabel, '+0.0°C');
      expect(stats.seaLabel, '0 mm');
    });
  });

  group('ClimateDataService — projected (2100)', () {
    test('returns IPCC SSP3 projection values', () async {
      final stats = await service.getStatsForYear(2100);

      expect(stats.year, 2100);
      expect(stats.tempAnomaly, 3.2);
      expect(stats.seaLevelMm, 900);
      expect(stats.source, contains('SSP3'));
    });

    test('2100 ice extent is near zero (ice-free scenario)', () async {
      final stats = await service.getStatsForYear(2100);
      expect(stats.iceExtentMkm2 < 2.0, true);
    });
  });

  group('ClimateDataService — present (2026)', () {
    test('returns valid stats with fallback', () async {
      // This test allows network failure — falls back to IPCC
      final stats = await service.getStatsForYear(2026);

      expect(stats.year, 2026);
      // Temp anomaly should be between 1900 and 2100 values
      expect(stats.tempAnomaly > 0, true);
      expect(stats.tempAnomaly < 3.2, true);
      // Source should mention either live data or IPCC fallback
      expect(stats.source.isNotEmpty, true);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  group('ClimateStats model', () {
    test('formats all labels correctly', () {
      const stats = ClimateStats(
        year: 2026,
        tempAnomaly: 1.3,
        seaLevelMm: 330,
        iceExtentMkm2: 7.0,
        forestLossPct: 25.0,
        source: 'Test data',
      );

      expect(stats.tempLabel, '+1.3°C');
      expect(stats.seaLabel, '330 mm');
      expect(stats.iceLabel, '7.0 M km²');
      expect(stats.forestLabel, '25.0% lost');
    });
  });
}

//TEST FILE: climate_data_service_test.dart
// PURPOSE: to Verify ClimateDataService returns correct stats for
/// each era WITHOUT making real network calls for 1900/2100
// (those use IPCC bundled data — instant, deterministic).
// NOTE: The 2026 "live" path makes real HTTP calls to NOAA/NSIDC.
/// We mark that test with a longer timeout and allow it to fall
// back gracefully if network is unavailable (CI environments
/// often have no internet access).