import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_storyteller/features/explore/custom_region_service.dart';
import 'package:climate_storyteller/features/explore/climate_region.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CustomRegionService.instance.clearAll();
  });

  group('CustomRegionService Tests', () {
    test('addRegion adds custom region and clearAll removes all custom regions', () async {
      final service = CustomRegionService.instance;
      expect(service.customRegions, isEmpty);

      final r1 = ClimateRegion(
        id: 'custom_test_1',
        name: 'Test Location 1',
        category: 'heat',
        latitude: 12.34,
        longitude: 56.78,
        altitude: 350000,
        riskLevel: 'High',
        kmlFiles: ClimateRegion.generateKmlFiles('custom_test_1', 'heat'),
        bboxNorth: 13,
        bboxSouth: 11,
        bboxEast: 57,
        bboxWest: 55,
        imageUrl: '',
        description: 'Test custom region 1',
        isCustom: true,
      );

      final r2 = ClimateRegion(
        id: 'custom_test_2',
        name: 'Test Location 2',
        category: 'forest',
        latitude: -10.0,
        longitude: 20.0,
        altitude: 350000,
        riskLevel: 'Critical',
        kmlFiles: ClimateRegion.generateKmlFiles('custom_test_2', 'forest'),
        bboxNorth: -9,
        bboxSouth: -11,
        bboxEast: 21,
        bboxWest: 19,
        imageUrl: '',
        description: 'Test custom region 2',
        isCustom: true,
      );

      await service.addRegion(r1);
      await service.addRegion(r2);

      expect(service.customRegions.length, equals(2));
      expect(service.allRegions.length, equals(kDefaultRegions.length + 2));
      await service.removeRegion(r1.id);
      expect(service.customRegions.length, equals(1));
      expect(service.customRegions.first.id, equals(r2.id));
      await service.clearAll();
      expect(service.customRegions, isEmpty);
      expect(service.allRegions.length, equals(kDefaultRegions.length));
    });
  });
}
