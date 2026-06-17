import 'package:flutter_test/flutter_test.dart';
import 'package:climate_storyteller/services/aqi_data_service.dart';

void main() {
  final service = AqiDataService.instance;

  group('AQI level classification (PM2.5 → AqiLevel)', () {
    test('returns fallback estimates when API unavailable', () async {
      // fetchCityAqi falls back to estimated readings if network fails
      final readings = await service.fetchCityAqi('Delhi');
      expect(readings, isNotEmpty);
      expect(readings.any((r) => r.parameter == 'pm25'), true);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  group('AqiReading model', () {
    test('fromJson parses correctly', () {
      final reading = AqiReading.fromJson({
        'parameter': 'pm25',
        'value': 42.5,
        'unit': 'µg/m³',
        'city': 'Delhi',
      });

      expect(reading.parameter, 'pm25');
      expect(reading.value, 42.5);
      expect(reading.city, 'Delhi');
    });

    test('fromJson handles missing fields gracefully', () {
      final reading = AqiReading.fromJson({});
      expect(reading.parameter, '');
      expect(reading.value, 0);
    });
  });

  group('buildAqiKml', () {
    test('generates valid KML with placemarks for each city', () {
      final cityData = {
        'Delhi': [
          const AqiReading(parameter: 'pm25', value: 92, unit: 'µg/m³', city: 'Delhi'),
        ],
        'London': [
          const AqiReading(parameter: 'pm25', value: 11, unit: 'µg/m³', city: 'London'),
        ],
      };

      final kml = service.buildAqiKml(cityData, '2026');

      // Basic KML structure checks
      expect(kml, contains('<?xml version="1.0"'));
      expect(kml, contains('<kml'));
      expect(kml, contains('<Document>'));
      expect(kml, contains('</kml>'));

      // Both cities should have placemarks
      expect(kml, contains('Delhi'));
      expect(kml, contains('London'));

      // Should contain polygon coordinates
      expect(kml, contains('<Polygon>'));
      expect(kml, contains('<coordinates>'));
    });

    test('high PM2.5 produces hazardous color, low produces good color', () {
      final cityData = {
        'Delhi': [
          const AqiReading(parameter: 'pm25', value: 300, unit: 'µg/m³', city: 'Delhi'),
        ],
        'London': [
          const AqiReading(parameter: 'pm25', value: 5, unit: 'µg/m³', city: 'London'),
        ],
      };

      final kml = service.buildAqiKml(cityData, '2026');

      // Delhi (PM2.5=300) should be Hazardous
      expect(kml, contains('Hazardous'));
      // London (PM2.5=5) should be Good
      expect(kml, contains('Good'));
    });
  });
}