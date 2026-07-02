import 'dart:convert';
import 'package:http/http.dart' as http;

abstract class ClimateRemoteDataSource {
  Future<double> fetchTempAnomaly({String? noaaApiKey});
  Future<double> fetchSeaLevel();
  Future<double> fetchArcticIceExtent();
}

class ClimateRemoteDataSourceImpl implements ClimateRemoteDataSource {
  static const _noaaCdoBase  = 'https://www.ncei.noaa.gov/cdo-web/api/v2';
  static const _noaaTidesBase = 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter';
  static const _nsidcBase = 'https://noaadata.apps.nsidc.org/NOAA/G02135';

  final Map<String, _CachedValue> _cache = {};

  @override
  Future<double> fetchTempAnomaly({String? noaaApiKey}) async {
    const cacheKey = 'temp_anomaly';
    final cached = _getCache(cacheKey);
    if (cached != null) return cached;

    if (noaaApiKey == null || noaaApiKey.isEmpty) {
      throw Exception('NOAA API key is required');
    }

    final uri = Uri.parse(
      '$_noaaCdoBase/data'
      '?datasetid=GSOM'
      '&datatypeid=TAVG'
      '&stationid=GHCND:USW00094728'
      '&units=standard'
      '&limit=1'
      '&sortfield=date&sortorder=desc',
    );

    final res = await http.get(uri,
      headers: {'token': noaaApiKey},
    ).timeout(const Duration(seconds: 8));

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final value = (body['results']?[0]?['value'] as num?)?.toDouble();
      if (value != null) {
        _setCache(cacheKey, value);
        return value;
      }
    }
    throw Exception('Failed to load temperature anomaly from NOAA');
  }

  @override
  Future<double> fetchSeaLevel() async {
    const cacheKey = 'sea_level';
    final cached = _getCache(cacheKey);
    if (cached != null) return cached;

    final now = DateTime.now();
    final begin = '${now.year - 1}0101';
    final end = '${now.year}1231';

    final uri = Uri.parse(
      '$_noaaTidesBase'
      '?product=monthly_mean'
      '&station=8518750'
      '&datum=MSL'
      '&units=metric'
      '&time_zone=GMT'
      '&format=json'
      '&begin_date=$begin'
      '&end_date=$end',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 8));

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final data = body['data'] as List?;
      if (data != null && data.isNotEmpty) {
        final latest = (data.last['v'] as num?)?.toDouble();
        if (latest != null) {
          _setCache(cacheKey, latest);
          return latest;
        }
      }
    }
    throw Exception('Failed to load sea level from NOAA');
  }

  @override
  Future<double> fetchArcticIceExtent() async {
    const cacheKey = 'arctic_ice';
    final cached = _getCache(cacheKey);
    if (cached != null) return cached;

    final uri = Uri.parse('$_nsidcBase/north/monthly/data/N_MM_extent.csv');

    final res = await http.get(uri).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      final lines = res.body.trim().split('\n');
      final dataLines = lines.where((l) =>
        l.isNotEmpty && !l.startsWith('N') && !l.startsWith('y')
      ).toList();

      if (dataLines.isNotEmpty) {
        final lastLine = dataLines.last;
        final parts = lastLine.split(',');
        if (parts.length >= 5) {
          final extent = double.tryParse(parts[4].trim());
          if (extent != null) {
            _setCache(cacheKey, extent);
            return extent;
          }
        }
      }
    }
    throw Exception('Failed to load Arctic sea ice extent from NSIDC');
  }

  double? _getCache(String key) {
    final v = _cache[key];
    if (v == null) return null;
    if (DateTime.now().difference(v.timestamp).inHours > 6) {
      _cache.remove(key);
      return null;
    }
    return v.value;
  }

  void _setCache(String key, double value) {
    _cache[key] = _CachedValue(value, DateTime.now());
  }
}

class _CachedValue {
  final double value;
  final DateTime timestamp;
  _CachedValue(this.value, this.timestamp);
}
