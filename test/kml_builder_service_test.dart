import 'package:flutter_test/flutter_test.dart';
import 'package:climate_storyteller/services/kml_builder_service.dart';
import 'package:climate_storyteller/models/app_models.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KmlBuilderService', () {
    test('builds KML file for Arctic 1900', () async {
      final region = kDefaultRegions.firstWhere((r) => r.id == 'arctic');

      final path = await KmlBuilderService.instance.buildKml(
        region: region,
        era: ClimateEra.preindustrial1900,
      );

      expect(path, isNotEmpty);
      expect(path, contains('arctic'));
      expect(path, contains('1900'));
      expect(path.endsWith('.kml'), true);
    });

    test('builds KML file for each of the 6 regions', () async {
      for (final region in kDefaultRegions) {
        final path = await KmlBuilderService.instance.buildKml(
          region: region,
          era: ClimateEra.present2026,
        );
        expect(path, isNotEmpty,
            reason: '${region.name} should produce a KML path');
        expect(path, contains(region.id));
      }
    });

    test('cached file is returned on second call (same era)', () async {
      final region = kDefaultRegions.first;

      final path1 = await KmlBuilderService.instance.buildKml(
        region: region, era: ClimateEra.present2026);
      final path2 = await KmlBuilderService.instance.buildKml(
        region: region, era: ClimateEra.present2026);

      // Same file path returned — cache hit
      expect(path1, path2);
    });

    test('listCachedKmls returns non-empty after builds', () async {
      final files = await KmlBuilderService.instance.listCachedKmls();
      expect(files, isNotEmpty);
      expect(files.every((f) => f.path.endsWith('.kml')), true);
    });

    test('clearCache removes all cached files', () async {
      await KmlBuilderService.instance.clearCache();
      final files = await KmlBuilderService.instance.listCachedKmls();
      expect(files, isEmpty);
    });
  });
}