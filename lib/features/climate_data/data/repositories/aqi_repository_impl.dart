import '../../domain/entities/aqi_reading.dart';
import '../../domain/repositories/aqi_repository.dart';
import '../datasources/aqi_remote_data_source.dart';

class AqiRepositoryImpl implements AqiRepository {
  final AqiRemoteDataSource remoteDataSource;

  AqiRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<AqiReading>> getCityAqi(String city) async {
    return await remoteDataSource.fetchCityAqi(city);
  }

  @override
  Future<Map<String, List<AqiReading>>> getAllCitiesAqi() async {
    final Map<String, List<AqiReading>> res = {};
    final data = await remoteDataSource.fetchAllCitiesAqi();
    data.forEach((k, v) {
      res[k] = v;
    });
    return res;
  }

  @override
  String buildAqiKml(Map<String, List<AqiReading>> cityData, String era) {
    final placemarks = cityData.entries.map((entry) {
      final city     = entry.key;
      final readings = entry.value;
      final pm25     = readings
          .where((r) => r.parameter == 'pm25')
          .map((r) => r.value)
          .fold(0.0, (a, b) => a + b);
      final pm25Count = readings.where((r) => r.parameter == 'pm25').length;
      final avgPm25  = pm25Count == 0 ? 0.0 : pm25 / pm25Count;

      final aqiLevel = _pm25ToAqi(avgPm25);
      final color    = _aqiColor(aqiLevel);
      final coords   = _cityCoords[city]!;

      return '''
    <Placemark>
      <name>$city — AQI ${aqiLevel.label}</name>
      <description><![CDATA[
        <b>$city Air Quality ($era)</b><br/>
        AQI Level: ${aqiLevel.label}<br/>
        PM2.5: ${avgPm25.toStringAsFixed(1)} µg/m³<br/>
        Source: OpenAQ
      ]]></description>
      <Style>
        <PolyStyle>
          <color>${color}</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>${color}</color>
          <width>1.5</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              ${coords['lon']! - 1.5},${coords['lat']! - 1.5},0
              ${coords['lon']! + 1.5},${coords['lat']! - 1.5},0
              ${coords['lon']! + 1.5},${coords['lat']! + 1.5},0
              ${coords['lon']! - 1.5},${coords['lat']! + 1.5},0
              ${coords['lon']! - 1.5},${coords['lat']! - 1.5},0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
    }).join('\n');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>AQI Heatmap — $era</name>
    <description>Air Quality Index heatmap. Source: OpenAQ</description>
$placemarks
  </Document>
</kml>''';
  }

  static const Map<String, Map<String, double>> _cityCoords = {
    'Delhi':    {'lat': 28.6, 'lon': 77.2},
    'Beijing':  {'lat': 39.9, 'lon': 116.4},
    'London':   {'lat': 51.5, 'lon': -0.1},
    'New York': {'lat': 40.7, 'lon': -74.0},
    'Jakarta':  {'lat': -6.2, 'lon': 106.8},
    'Amazon':   {'lat': -3.5, 'lon': -60.0},
  };

  AqiLevel _pm25ToAqi(double pm25) {
    if (pm25 <= 12)  return AqiLevel.good;
    if (pm25 <= 35)  return AqiLevel.moderate;
    if (pm25 <= 55)  return AqiLevel.unhealthySensitive;
    if (pm25 <= 150) return AqiLevel.unhealthy;
    if (pm25 <= 250) return AqiLevel.veryUnhealthy;
    return AqiLevel.hazardous;
  }

  String _aqiColor(AqiLevel level) => switch (level) {
    AqiLevel.good               => 'ff00e400', // green
    AqiLevel.moderate           => 'ff00e4ff', // yellow
    AqiLevel.unhealthySensitive => 'ff0094ff', // orange
    AqiLevel.unhealthy          => 'ff0000ff', // red
    AqiLevel.veryUnhealthy      => 'ff800080', // purple
    AqiLevel.hazardous          => 'ff400040', // maroon
  };
}
