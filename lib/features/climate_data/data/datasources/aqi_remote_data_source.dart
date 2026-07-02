import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/aqi_reading_model.dart';

abstract class AqiRemoteDataSource {
  Future<List<AqiReadingModel>> fetchCityAqi(String city);
  Future<Map<String, List<AqiReadingModel>>> fetchAllCitiesAqi();
}

class AqiRemoteDataSourceImpl implements AqiRemoteDataSource {
  static const _base = 'https://api.openaq.org/v2';

  final Map<String, _AqiCache> _cache = {};

  static const Map<String, String> cityStations = {
    'Delhi':       'IN',
    'Beijing':     'CN',
    'London':      'GB',
    'New York':    'US',
    'Jakarta':     'ID',
    'Amazon':      'BR',
  };

  @override
  Future<List<AqiReadingModel>> fetchCityAqi(String city) async {
    final cached = _getCache(city);
    if (cached != null) return cached;

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

    final res = await http.get(uri, headers: {
      'Accept': 'application/json'
    }).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final results = body['results'] as List? ?? [];
      final readings = results.map((r) => AqiReadingModel.fromJson(r)).toList();
      _setCache(city, readings);
      return readings;
    }
    throw Exception('Failed to load AQI measurements for $city');
  }

  @override
  Future<Map<String, List<AqiReadingModel>>> fetchAllCitiesAqi() async {
    final results = <String, List<AqiReadingModel>>{};
    await Future.wait(
      cityStations.keys.map((city) async {
        try {
          results[city] = await fetchCityAqi(city);
        } catch (_) {
          results[city] = _estimatedReadings(city);
        }
      }),
    );
    return results;
  }

  List<AqiReadingModel> _estimatedReadings(String city) {
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
      AqiReadingModel(parameter: 'pm25', value: vals['pm25']!, unit: 'µg/m³', city: city),
      AqiReadingModel(parameter: 'pm10', value: vals['pm10']!, unit: 'µg/m³', city: city),
    ];
  }

  List<AqiReadingModel>? _getCache(String city) {
    final v = _cache[city];
    if (v == null) return null;
    if (DateTime.now().difference(v.timestamp).inHours > 1) {
      _cache.remove(city);
      return null;
    }
    return v.readings;
  }

  void _setCache(String city, List<AqiReadingModel> readings) {
    _cache[city] = _AqiCache(readings, DateTime.now());
  }
}

class _AqiCache {
  final List<AqiReadingModel> readings;
  final DateTime timestamp;
  _AqiCache(this.readings, this.timestamp);
}
