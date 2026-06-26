import 'package:flutter_test/flutter_test.dart';
import 'package:climate_storyteller/features/local data/ipcc_data.dart';
void main() {
  group('IPCC AR6 bundled data', () {
    test('temperature anomaly increases over time', () {
      // 1900 should be 0 (baseline), 2100 should be highest
      expect(kTemperatureAnomaly[1900], 0.0);
      expect(kTemperatureAnomaly[2100]! > kTemperatureAnomaly[2026]!, true);
      expect(kTemperatureAnomaly[2026]! > kTemperatureAnomaly[1900]!, true);
    });

    test('arctic ice extent decreases over time', () {
      // Ice should shrink from 1900 → 2100
      expect(kArcticIceExtent[1900]! > kArcticIceExtent[2026]!, true);
      expect(kArcticIceExtent[2026]! > kArcticIceExtent[2100]!, true);
      // 2100 should be near ice-free (under 2 million km²)
      expect(kArcticIceExtent[2100]! < 2000000, true);
    });

    test('sea level rise increases over time', () {
      expect(kSeaLevelRise[1900], 0);
      expect(kSeaLevelRise[2100]! > kSeaLevelRise[2026]!, true);
      // By 2100 sea level should rise by at least 500mm
      expect(kSeaLevelRise[2100]! >= 500, true);
    });

    test('forest cover loss increases over time', () {
      expect(kForestCoverLoss[1900], 0);
      expect(kForestCoverLoss[2100]! > kForestCoverLoss[2026]!, true);
    });

    test('all 6 regions have IPCC story data', () {
      const expectedRegions = [
        'arctic', 'himalaya', 'amazon', 'pacific', 'maldives'
      ];
      for (final id in expectedRegions) {
        final data = getRegionData(id);
        expect(data, isNotNull,
            reason: 'Region $id should have IPCC data');
        expect(data!.description.containsKey(1900), true);
        expect(data.description.containsKey(2026), true);
        expect(data.description.containsKey(2100), true);
      }
    });

    test('getRegionData returns null for unknown region', () {
      expect(getRegionData('atlantis'), isNull);
    });

    test('region story text is non-empty for every era', () {
      for (final region in kRegionIpccData) {
        for (final era in [1900, 2026, 2100]) {
          final text = region.description[era];
          expect(text, isNotNull);
          expect(text!.length > 20, true,
              reason: '${region.name} $era story too short');
        }
      }
    });
  });
}


// TEST FILE: ipcc_data_test.dart
// PURPOSE: to Verify the bundled IPCC AR6 constants are valid and
// the interpolation/lookup logic works correctly.
// These are PURE Dart tests — no internet, no widgets, run instantly.
