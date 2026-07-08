import 'package:flutter_test/flutter_test.dart';
import 'package:climate_storyteller/features/climate_data/ipcc_data.dart';

void main() {
  group('IPCC Interpolation Tests', () {
    test('should return correct interpolated temperature for 1900', () {
      final val = getInterpolatedTemperature(1900);
      expect(val, 0.0);
    });

    test('should return correct interpolated temperature for 2100', () {
      final val = getInterpolatedTemperature(2100);
      expect(val, 3.2);
    });
  });
}
