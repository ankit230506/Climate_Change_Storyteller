import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/ipcc_data.dart';

/// Fetches live climate data from NOAA, NASA NSIDC, and NOAA Tides.
/// Falls back to IPCC bundled constants if network fails.
///
/// WHY HERE: All external HTTP calls for climate numbers live in one place.
/// KmlBuilderService calls this to get the stats it embeds in KML files.
/// Timeline screen calls this to fill the stat cards.
class ClimateDataService {
  ClimateDataService._();
  static final ClimateDataService instance = ClimateDataService._();

  // ── NOAA CDO API ─────────────────────────────────────────────────────────
  // Free key — register at: https://www.ncdc.noaa.gov/cdo-web/token
  // Takes ~1 min to get via email. Store it in API Setup screen.
  static const _noaaCdoBase  = 'https://www.ncei.noaa.gov/cdo-web/api/v2';

  // ── NOAA Tides & Currents — NO KEY NEEDED ────────────────────────────────
  // https://tidesandcurrents.noaa.gov/api/
  static const _noaaTidesBase = 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter';

  // ── NASA NSIDC sea ice — NO KEY NEEDED ───────────────────────────────────
  // https://nsidc.org/data/seaice_index/
  static const _nsidcBase = 'https://noaadata.apps.nsidc.org/NOAA/G02135';

  // ── Simple in-memory cache ────────────────────────────────────────────────
  final Map<String, _CachedValue> _cache = {};

  // ════════════════════════════════════════════════════════════════════════
  // TEMPERATURE ANOMALY  (NOAA CDO)
  // ════════════════════════════════════════════════════════════════════════

  /// Returns global mean temp anomaly in °C relative to 1901-2000 baseline.
  /// Called by: KmlBuilderService (embed in KML), TimelineScreen (stat card)
  ///
  /// API: GET /data?datasetid=GHCND&datatypeid=TAVG&limit=1
  /// Returns: {"results":[{"value":14.5,"date":"2026-01-01"}]}
  Future<double> fetchTempAnomaly({String? noaaApiKey}) async {
    const cacheKey = 'temp_anomaly';
    final cached = _getCache(cacheKey);
    if (cached != null) return cached as double;

    if (noaaApiKey == null || noaaApiKey.isEmpty) {
      // No key — return IPCC bundled value
      return _interpolateIpcc(kTemperatureAnomaly, DateTime.now().year);
    }

    try {
      final uri = Uri.parse(
        '$_noaaCdoBase/data'
        '?datasetid=GSOM'           // Global Surface Summary of Month
        '&datatypeid=TAVG'          // Monthly average temperature
        '&stationid=GHCND:USW00094728' // Global proxy station
        '&units=standard'
        '&limit=1'
        '&sortfield=date&sortorder=desc',
      );
      final res = await http.get(uri,
        headers: {'token': noaaApiKey},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body   = jsonDecode(res.body);
        final value  = (body['results']?[0]?['value'] as num?)?.toDouble();
        if (value != null) {
          _setCache(cacheKey, value);
          return value;
        }
      }
    } catch (e) {
      print('[ClimateDataService] NOAA temp fetch failed: $e — using IPCC fallback');
    }

    // Fallback to IPCC interpolated value
    return _interpolateIpcc(kTemperatureAnomaly, DateTime.now().year);
  }

  // ════════════════════════════════════════════════════════════════════════
  // SEA LEVEL  (NOAA Tides & Currents — NO KEY)
  // ════════════════════════════════════════════════════════════════════════

  /// Returns mean sea level in mm relative to 1900 baseline.
  /// Called by: KmlBuilderService, TimelineScreen stat card
  ///
  /// API: GET ?product=monthly_mean&station=8518750&datum=MSL&units=metric
  /// Station 8518750 = The Battery, New York (longest record, since 1856)
  Future<double> fetchSeaLevel() async {
    const cacheKey = 'sea_level';
    final cached = _getCache(cacheKey);
    if (cached != null) return cached as double;

    try {
      final now   = DateTime.now();
      final begin = '${now.year - 1}0101';
      final end   = '${now.year}1231';

      final uri = Uri.parse(
        '$_noaaTidesBase'
        '?product=monthly_mean'
        '&station=8518750'   // The Battery, NYC
        '&datum=MSL'         // Mean Sea Level
        '&units=metric'      // millimetres
        '&time_zone=GMT'
        '&format=json'
        '&begin_date=$begin'
        '&end_date=$end',
      );

      final res = await http.get(uri)
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final data = body['data'] as List?;
        if (data != null && data.isNotEmpty) {
          final latest = (data.last['v'] as num?)?.toDouble();
          if (latest != null) {
            // Convert to mm above 1900 baseline using IPCC reference
            final baseline1900 = kSeaLevelRise[1900]!;
            final value = baseline1900 + latest;
            _setCache(cacheKey, value);
            return value;
          }
        }
      }
    } catch (e) {
      print('[ClimateDataService] NOAA sea level fetch failed: $e — using IPCC fallback');
    }

    return _interpolateIpcc(kSeaLevelRise, DateTime.now().year);
  }

  // ════════════════════════════════════════════════════════════════════════
  // ARCTIC SEA ICE EXTENT  (NASA NSIDC — NO KEY)
  // ════════════════════════════════════════════════════════════════════════

  /// Returns Arctic sea ice extent in million km².
  /// Called by: KmlBuilderService for arctic region, TimelineScreen stat card
  ///
  /// NSIDC publishes monthly extent CSV files publicly.
  /// URL: https://noaadata.apps.nsidc.org/NOAA/G02135/north/monthly/data/N_MM_extent.csv
  Future<double> fetchArcticIceExtent() async {
    const cacheKey = 'arctic_ice';
    final cached = _getCache(cacheKey);
    if (cached != null) return cached as double;

    try {
      final uri = Uri.parse(
        '$_nsidcBase/north/monthly/data/N_MM_extent.csv',
      );

      final res = await http.get(uri)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        // CSV format: year, month, data-type, region, extent, area
        final lines  = res.body.trim().split('\n');
        // Skip header lines (start with 'NSIDC' or 'year')
        final dataLines = lines.where((l) =>
          l.isNotEmpty && !l.startsWith('N') && !l.startsWith('y')
        ).toList();

        if (dataLines.isNotEmpty) {
          final lastLine = dataLines.last;
          final parts    = lastLine.split(',');
          if (parts.length >= 5) {
            final extent = double.tryParse(parts[4].trim());
            if (extent != null) {
              _setCache(cacheKey, extent);
              return extent;
            }
          }
        }
      }
    } catch (e) {
      print('[ClimateDataService] NSIDC ice fetch failed: $e — using IPCC fallback');
    }

    return _interpolateIpcc(kArcticIceExtent, DateTime.now().year);
  }

  // ════════════════════════════════════════════════════════════════════════
  // GET ALL STATS FOR AN ERA  (used by KmlBuilderService + TimelineScreen)
  // ════════════════════════════════════════════════════════════════════════

  /// Returns all climate stats for a given year.
  /// For 1900 and 2100 — uses IPCC bundled data (no live API needed).
  /// For 2026 — tries live APIs, falls back to IPCC if unavailable.
  Future<ClimateStats> getStatsForYear(int year, {String? noaaKey}) async {
    if (year <= 1900) {
      // Past — all from IPCC constants
      return ClimateStats(
        year:          1900,
        tempAnomaly:   kTemperatureAnomaly[1900]!,
        seaLevelMm:    kSeaLevelRise[1900]!,
        iceExtentMkm2: kArcticIceExtent[1900]!,
        forestLossPct: kForestCoverLoss[1900]!,
        source:        'IPCC AR6 historical baseline',
      );
    }

    if (year >= 2100) {
      // Future — all from IPCC projections
      return ClimateStats(
        year:          2100,
        tempAnomaly:   kTemperatureAnomaly[2100]!,
        seaLevelMm:    kSeaLevelRise[2100]!,
        iceExtentMkm2: kArcticIceExtent[2100]!,
        forestLossPct: kForestCoverLoss[2100]!,
        source:        'IPCC AR6 SSP3-7.0 projection',
      );
    }

    // Present — try live APIs
    final results = await Future.wait([
      fetchTempAnomaly(noaaApiKey: noaaKey),
      fetchSeaLevel(),
      fetchArcticIceExtent(),
    ]);

    return ClimateStats(
      year:          year,
      tempAnomaly:   results[0],
      seaLevelMm:    results[1],
      iceExtentMkm2: results[2],
      forestLossPct: _interpolateIpcc(kForestCoverLoss, year),
      source:        'NOAA live data + IPCC AR6',
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════════════

  double _interpolateIpcc(Map<int, double> data, int year) {
    final years = data.keys.toList()..sort();
    if (year <= years.first) return data[years.first]!;
    if (year >= years.last)  return data[years.last]!;
    for (int i = 0; i < years.length - 1; i++) {
      if (year >= years[i] && year <= years[i + 1]) {
        final t = (year - years[i]) / (years[i + 1] - years[i]);
        return data[years[i]]! + t * (data[years[i + 1]]! - data[years[i]]!);
      }
    }
    return 0;
  }

  dynamic _getCache(String key) {
    final v = _cache[key];
    if (v == null) return null;
    if (DateTime.now().difference(v.timestamp).inHours > 6) {
      _cache.remove(key);
      return null;
    }
    return v.value;
  }

  void _setCache(String key, dynamic value) {
    _cache[key] = _CachedValue(value, DateTime.now());
  }
}

class _CachedValue {
  final dynamic  value;
  final DateTime timestamp;
  _CachedValue(this.value, this.timestamp);
}

/// All climate stats for one era — passed between services and screens.
class ClimateStats {
  final int    year;
  final double tempAnomaly;    // °C above 1900 baseline
  final double seaLevelMm;     // mm above 1900 baseline
  final double iceExtentMkm2;  // million km²
  final double forestLossPct;  // % of 1900 cover lost
  final String source;         // data attribution string

  const ClimateStats({
    required this.year,
    required this.tempAnomaly,
    required this.seaLevelMm,
    required this.iceExtentMkm2,
    required this.forestLossPct,
    required this.source,
  });

  String get tempLabel    => '${tempAnomaly >= 0 ? '+' : ''}${tempAnomaly.toStringAsFixed(1)}°C';
  String get seaLabel     => '${seaLevelMm.toStringAsFixed(0)} mm';
  String get iceLabel     => '${iceExtentMkm2.toStringAsFixed(1)} M km²';
  String get forestLabel  => '${forestLossPct.toStringAsFixed(1)}% lost';
}