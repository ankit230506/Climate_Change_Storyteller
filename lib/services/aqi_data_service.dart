import 'dart:convert';
import 'package:http/http.dart' as http;

/// Fetches real-time and historical air quality data from OpenAQ.
/// NO API KEY NEEDED — completely free and open.
///
/// WHY HERE: AQI data is separate from climate data because it feeds
/// specifically the KML Map screen's heatmap layer, not the timeline.
/// OpenAQ: https://api.openaq.org/v2/
class AqiDataService {
  AqiDataService._();
  static final AqiDataService instance = AqiDataService._();

  static const _base = 'https://api.openaq.org/v2';

  // Cache — AQI data valid for 1 hour
  final Map<String, _AqiCache> _cache = {};

  // ── Supported cities with station IDs ────────────────────────────────────
  static const Map<String, String> cityStations = {
    'Delhi':       'IN',
    'Beijing':     'CN',
    'London':      'GB',
    'New York':    'US',
    'Jakarta':     'ID',
    'Amazon':      'BR',
  };

  // ════════════════════════════════════════════════════════════════════════
  // FETCH AQI FOR A CITY
  // ════════════════════════════════════════════════════════════════════════

  /// Returns latest AQI readings for a city.
  /// Called by: KmlMapScreen to build color-coded heatmap KML
  ///
  /// API: GET /measurements?city=Delhi&parameter=pm25&limit=10
  /// Returns list of AqiReading objects
  Future<List<AqiReading>> fetchCityAqi(String city) async {
    final cached = _getCache(city);
    if (cached != null) return cached;

    try {
      final country = cityStations[city] ?? 'IN';
      final uri = Uri.parse(
        '$_base/measurements'
        '?country=$country'
        '&limit=10'
        '&sort=desc'
        '&order_by=datetime'
        '&parameter[]=pm25'
        '&parameter[]=pm10'
        '&parameter[]=no2'
        '&parameter[]=o3',
      );

      final res = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body    = jsonDecode(res.body);
        final results = body['results'] as List? ?? [];
        final readings = results.map((r) => AqiReading.fromJson(r)).toList();
        _setCache(city, readings);
        return readings;
      }
    } catch (e) {
      print('[AqiDataService] OpenAQ fetch failed for $city: $e');
    }

    // Return estimated values from IPCC data if API fails
    return _estimatedReadings(city);
  }

  // ════════════════════════════════════════════════════════════════════════
  // FETCH AQI FOR ALL CITIES — for the full heatmap
  // ════════════════════════════════════════════════════════════════════════

  Future<Map<String, List<AqiReading>>> fetchAllCitiesAqi() async {
    final results = <String, List<AqiReading>>{};
    await Future.wait(
      cityStations.keys.map((city) async {
        results[city] = await fetchCityAqi(city);
      }),
    );
    return results;
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD AQI KML — color-coded polygons for LG heatmap
  // ════════════════════════════════════════════════════════════════════════

  /// Converts AQI readings into a KML string with colored polygons.
  /// Each city gets a polygon colored by AQI level.
  /// Called by: KmlMapScreen → sendKml() → LG rig
  String buildAqiKml(Map<String, List<AqiReading>> cityData, String era) {
    final placemarks = cityData.entries.map((entry) {
      final city     = entry.key;
      final readings = entry.value;
      final pm25     = readings
          .where((r) => r.parameter == 'pm25')
          .map((r) => r.value)
          .fold(0.0, (a, b) => a + b);
      final avgPm25  = readings.isEmpty ? 0.0
          : pm25 / readings.where((r) => r.parameter == 'pm25').length;

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
          <color>${color}aa</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>ff${color.substring(2)}</color>
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

  // ════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════════════

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

  List<AqiReading> _estimatedReadings(String city) {
    // Fallback estimated values per city (from WHO/IQAir 2024 data)
    final estimates = {
      'Delhi':    {'pm25': 92.0, 'pm10': 185.0},
      'Beijing':  {'pm25': 38.0, 'pm10': 75.0},
      'London':   {'pm25': 11.0, 'pm10': 18.0},
      'New York': {'pm25': 8.0,  'pm10': 14.0},
      'Jakarta':  {'pm25': 40.0, 'pm10': 82.0},
      'Amazon':   {'pm25': 6.0,  'pm10': 10.0},
    };
    final vals = estimates[city] ?? {'pm25': 15.0, 'pm10': 30.0};
    return [
      AqiReading(parameter: 'pm25', value: vals['pm25']!, unit: 'µg/m³', city: city),
      AqiReading(parameter: 'pm10', value: vals['pm10']!, unit: 'µg/m³', city: city),
    ];
  }

  List<AqiReading>? _getCache(String city) {
    final v = _cache[city];
    if (v == null) return null;
    if (DateTime.now().difference(v.timestamp).inHours > 1) {
      _cache.remove(city);
      return null;
    }
    return v.readings;
  }

  void _setCache(String city, List<AqiReading> readings) {
    _cache[city] = _AqiCache(readings, DateTime.now());
  }
}

// ── Data models ───────────────────────────────────────────────────────────────

class AqiReading {
  final String parameter; // pm25, pm10, no2, o3
  final double value;
  final String unit;
  final String city;

  const AqiReading({
    required this.parameter,
    required this.value,
    required this.unit,
    required this.city,
  });

  factory AqiReading.fromJson(Map<String, dynamic> j) => AqiReading(
    parameter: j['parameter'] ?? '',
    value:     (j['value'] as num?)?.toDouble() ?? 0,
    unit:      j['unit'] ?? 'µg/m³',
    city:      j['city'] ?? '',
  );
}

enum AqiLevel {
  good, moderate, unhealthySensitive, unhealthy, veryUnhealthy, hazardous;

  String get label => switch (this) {
    AqiLevel.good               => 'Good',
    AqiLevel.moderate           => 'Moderate',
    AqiLevel.unhealthySensitive => 'Unhealthy (Sensitive)',
    AqiLevel.unhealthy          => 'Unhealthy',
    AqiLevel.veryUnhealthy      => 'Very Unhealthy',
    AqiLevel.hazardous          => 'Hazardous',
  };
}

class _AqiCache {
  final List<AqiReading> readings;
  final DateTime         timestamp;
  _AqiCache(this.readings, this.timestamp);
}