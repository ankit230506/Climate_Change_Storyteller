import 'package:flutter_test/flutter_test.dart';
import 'package:climate_storyteller/features/climate_data/data/datasources/climate_local_data_source.dart';

void main() {
  group('ClimateLocalDataSourceImpl Tests', () {
    late ClimateLocalDataSourceImpl dataSource;

    setUp(() {
      dataSource = ClimateLocalDataSourceImpl();
    });

    test('should return correct interpolated temperature for 1900', () {
      final val = dataSource.getInterpolatedTemperature(1900);
      expect(val, 0.0);
    });

    test('should return correct interpolated temperature for 2100', () {
      final val = dataSource.getInterpolatedTemperature(2100);
      expect(val, 3.2);
    });
  });
}
