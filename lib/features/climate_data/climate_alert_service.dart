import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'climate_alert.dart';

/// Service that fetches real-time climate alerts from NASA FIRMS and NOAA.
class ClimateAlertService {
  ClimateAlertService._();
  static final ClimateAlertService instance = ClimateAlertService._();

  List<ClimateAlert> _cachedAlerts = [];
  DateTime? _lastFetch;
  final _streamCtrl = StreamController<List<ClimateAlert>>.broadcast();
  bool _isFetching = false;

  /// Stream of alerts for reactive UI.
  Stream<List<ClimateAlert>> get alertsStream => _streamCtrl.stream;

  /// Current cached alerts (synchronous).
  List<ClimateAlert> get alerts => List.unmodifiable(_cachedAlerts);

  /// Refresh interval: 10 minutes.
  static const _cacheMinutes = 10;

  /// Fetch all alerts (NASA FIRMS fires + NOAA weather alerts).
  /// Returns cached data if fetched within the last 10 minutes.
  Future<List<ClimateAlert>> fetchAlerts({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inMinutes < _cacheMinutes &&
        _cachedAlerts.isNotEmpty) {
      return _cachedAlerts;
    }

    if (_isFetching) return _cachedAlerts;
    _isFetching = true;

    try {
      final results = await Future.wait([
        _fetchNasaFirms(),
        _fetchNoaaAlerts(),
      ]);

      _cachedAlerts = [
        ...results[0],
        ...results[1],
      ];
      _cachedAlerts.sort((a, b) {
        final sevCmp = b.severity.priority.compareTo(a.severity.priority);
        if (sevCmp != 0) return sevCmp;
        return b.timestamp.compareTo(a.timestamp);
      });

      _lastFetch = DateTime.now();
      _streamCtrl.add(_cachedAlerts);
    } catch (e) {
      debugPrint('ClimateAlertService: fetch error: $e');
      if (_cachedAlerts.isEmpty) {
        _cachedAlerts = _fallbackAlerts();
        _streamCtrl.add(_cachedAlerts);
      }
    } finally {
      _isFetching = false;
    }

    return _cachedAlerts;
  }

  /// Fetch active fire hotspots from NASA FIRMS (last 24h, global summary).
  Future<List<ClimateAlert>> _fetchNasaFirms() async {
    try {
      final uri = Uri.parse(
        'https://firms.modaps.eosdis.nasa.gov/api/area/csv/'
        'VIIRS_NOAA21_NRT/WORLD/1',
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) {
        debugPrint('FIRMS API returned ${resp.statusCode}');
        return _fallbackFireAlerts();
      }

      final lines = const LineSplitter().convert(resp.body);
      if (lines.length < 2) return _fallbackFireAlerts();
      final header = lines.first.split(',');
      final latIdx = header.indexOf('latitude');
      final lonIdx = header.indexOf('longitude');
      final frpIdx = header.indexOf('frp');
      final dateIdx = header.indexOf('acq_date');
      final timeIdx = header.indexOf('acq_time');

      if (latIdx < 0 || lonIdx < 0) return _fallbackFireAlerts();

      final alerts = <ClimateAlert>[];
      final dataLines = lines.skip(1).take(500).toList();
      final parsed = <(double frp, List<String> cols)>[];
      for (final line in dataLines) {
        final cols = line.split(',');
        if (cols.length <= latIdx || cols.length <= lonIdx) continue;
        final frp =
            frpIdx >= 0 && cols.length > frpIdx
                ? double.tryParse(cols[frpIdx]) ?? 0
                : 0.0;
        parsed.add((frp, cols));
      }

      parsed.sort((a, b) => b.$1.compareTo(a.$1));

      for (final entry in parsed.take(15)) {
        final cols = entry.$2;
        final lat = double.tryParse(cols[latIdx]);
        final lng = double.tryParse(cols[lonIdx]);
        if (lat == null || lng == null) continue;

        final frp = entry.$1;
        final dateStr = dateIdx >= 0 && cols.length > dateIdx
            ? cols[dateIdx]
            : '';
        final timeStr = timeIdx >= 0 && cols.length > timeIdx
            ? cols[timeIdx]
            : '0000';

        DateTime ts;
        try {
          ts = DateTime.parse('${dateStr}T${timeStr.padLeft(4, '0').substring(0, 2)}:'
              '${timeStr.padLeft(4, '0').substring(2, 4)}:00Z');
        } catch (_) {
          ts = DateTime.now();
        }

        final severity = frp > 100
            ? AlertSeverity.extreme
            : frp > 50
                ? AlertSeverity.high
                : frp > 20
                    ? AlertSeverity.moderate
                    : AlertSeverity.low;

        final locationDesc = _describeCoordinate(lat, lng);

        alerts.add(ClimateAlert(
          id: 'firms_${lat}_${lng}_${ts.millisecondsSinceEpoch}',
          title: '${severity == AlertSeverity.extreme ? 'Major ' : ''}Wildfire — $locationDesc',
          description:
              'Active fire detected at ${lat.toStringAsFixed(2)}°, ${lng.toStringAsFixed(2)}°. '
              'Fire Radiative Power: ${frp.toStringAsFixed(1)} MW.',
          type: AlertType.wildfire,
          severity: severity,
          latitude: lat,
          longitude: lng,
          timestamp: ts,
          source: 'NASA FIRMS VIIRS',
        ));
      }

      return alerts;
    } catch (e) {
      debugPrint('FIRMS fetch error: $e');
      return _fallbackFireAlerts();
    }
  }

  /// Fetch active weather alerts from NOAA Weather Alerts API.
  Future<List<ClimateAlert>> _fetchNoaaAlerts() async {
    try {
      final uri = Uri.parse('https://api.weather.gov/alerts/active?limit=15');
      final resp = await http.get(
        uri,
        headers: {
          'User-Agent': 'ClimateStorytellerApp/1.0',
          'Accept': 'application/geo+json',
        },
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) {
        debugPrint('NOAA Alerts API returned ${resp.statusCode}');
        return _fallbackWeatherAlerts();
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = json['features'] as List? ?? [];

      final alerts = <ClimateAlert>[];

      for (final feature in features.take(15)) {
        final props = feature['properties'] as Map<String, dynamic>? ?? {};
        final geo = feature['geometry'] as Map<String, dynamic>?;
        double lat = 39.0;
        double lng = -98.0;

        if (geo != null && geo['type'] == 'Point') {
          final coords = geo['coordinates'] as List;
          lng = (coords[0] as num).toDouble();
          lat = (coords[1] as num).toDouble();
        } else if (props.containsKey('geocode')) {
        }

        final event = props['event'] as String? ?? 'Weather Alert';
        final headline = props['headline'] as String? ?? event;
        final desc = props['description'] as String? ?? '';
        final severityStr = (props['severity'] as String? ?? 'Minor').toLowerCase();
        final effectiveStr = props['effective'] as String? ?? '';

        DateTime ts;
        try {
          ts = DateTime.parse(effectiveStr);
        } catch (_) {
          ts = DateTime.now();
        }

        final severity = switch (severityStr) {
          'extreme' => AlertSeverity.extreme,
          'severe' => AlertSeverity.high,
          'moderate' => AlertSeverity.moderate,
          _ => AlertSeverity.low,
        };

        final type = _classifyWeatherEvent(event);

        alerts.add(ClimateAlert(
          id: 'noaa_${props['id'] ?? DateTime.now().millisecondsSinceEpoch}',
          title: headline.length > 60 ? '${headline.substring(0, 57)}...' : headline,
          description: desc.length > 200 ? '${desc.substring(0, 197)}...' : desc,
          type: type,
          severity: severity,
          latitude: lat,
          longitude: lng,
          timestamp: ts,
          source: 'NOAA Weather',
        ));
      }

      return alerts;
    } catch (e) {
      debugPrint('NOAA alerts fetch error: $e');
      return _fallbackWeatherAlerts();
    }
  }

  AlertType _classifyWeatherEvent(String event) {
    final lower = event.toLowerCase();
    if (lower.contains('fire') || lower.contains('red flag')) {
      return AlertType.wildfire;
    }
    if (lower.contains('flood') || lower.contains('tsunami')) {
      return AlertType.flood;
    }
    if (lower.contains('heat') || lower.contains('excessive')) {
      return AlertType.heatwave;
    }
    if (lower.contains('air quality') || lower.contains('smoke')) {
      return AlertType.aqiSpike;
    }
    return AlertType.extremeWeather;
  }

  /// Rough geographic description from lat/lng.
  String _describeCoordinate(double lat, double lng) {
    if (lat > 60) return 'Northern Latitude';
    if (lat < -60) return 'Southern Latitude';

    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lng >= 0 ? 'E' : 'W';
    if (lng > -30 && lng < 60 && lat > -40 && lat < 40) return 'Africa';
    if (lng > 60 && lng < 150 && lat > -10 && lat < 55) return 'Asia';
    if (lng > -140 && lng < -30 && lat > -60 && lat < 15) return 'South America';
    if (lng > -130 && lng < -50 && lat > 15 && lat < 75) return 'North America';
    if (lng > -15 && lng < 45 && lat > 35 && lat < 72) return 'Europe';
    if (lng > 100 && lng < 180 && lat > -50 && lat < -10) return 'Oceania';

    return '${lat.abs().toStringAsFixed(0)}°$ns ${lng.abs().toStringAsFixed(0)}°$ew';
  }

  /// Fallback fire alerts for demo/offline mode.
  List<ClimateAlert> _fallbackFireAlerts() => [
        ClimateAlert(
          id: 'fb_fire_1',
          title: 'Major Wildfire — Amazon Basin',
          description:
              'Active fire detected in the Amazon rainforest. Deforestation burning contributes to significant carbon release.',
          type: AlertType.wildfire,
          severity: AlertSeverity.extreme,
          latitude: -3.47,
          longitude: -62.22,
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
          source: 'NASA FIRMS (offline)',
        ),
        ClimateAlert(
          id: 'fb_fire_2',
          title: 'Wildfire — Siberian Taiga',
          description:
              'Large-scale forest fire in Siberia releasing stored carbon from permafrost regions.',
          type: AlertType.wildfire,
          severity: AlertSeverity.high,
          latitude: 62.0,
          longitude: 110.0,
          timestamp: DateTime.now().subtract(const Duration(hours: 5)),
          source: 'NASA FIRMS (offline)',
        ),
        ClimateAlert(
          id: 'fb_fire_3',
          title: 'Wildfire — Southeast Australia',
          description:
              'Bushfire activity detected in New South Wales amid drought conditions.',
          type: AlertType.wildfire,
          severity: AlertSeverity.high,
          latitude: -33.8,
          longitude: 150.9,
          timestamp: DateTime.now().subtract(const Duration(hours: 8)),
          source: 'NASA FIRMS (offline)',
        ),
      ];

  /// Fallback weather alerts for demo/offline mode.
  List<ClimateAlert> _fallbackWeatherAlerts() => [
        ClimateAlert(
          id: 'fb_wx_1',
          title: 'Extreme Heatwave — Sahara Region',
          description:
              'Temperatures exceeding 50°C recorded across the Sahara belt with heat index warnings.',
          type: AlertType.heatwave,
          severity: AlertSeverity.extreme,
          latitude: 23.4,
          longitude: 25.7,
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
          source: 'NOAA (offline)',
        ),
        ClimateAlert(
          id: 'fb_wx_2',
          title: 'AQI Hazardous — Delhi NCR',
          description:
              'PM2.5 levels exceeding 300 µg/m³ in Delhi NCR. Health emergency declared.',
          type: AlertType.aqiSpike,
          severity: AlertSeverity.extreme,
          latitude: 28.6,
          longitude: 77.2,
          timestamp: DateTime.now().subtract(const Duration(hours: 3)),
          source: 'OpenAQ (offline)',
        ),
        ClimateAlert(
          id: 'fb_wx_3',
          title: 'Coastal Flood Warning — Maldives',
          description:
              'King tide event expected with wave surges threatening low-lying atolls.',
          type: AlertType.flood,
          severity: AlertSeverity.high,
          latitude: 3.45,
          longitude: 73.3,
          timestamp: DateTime.now().subtract(const Duration(hours: 6)),
          source: 'NOAA (offline)',
        ),
        ClimateAlert(
          id: 'fb_wx_4',
          title: 'Severe Thunderstorm — Pacific Islands',
          description:
              'Tropical cyclone formation potential with destructive wind gusts.',
          type: AlertType.extremeWeather,
          severity: AlertSeverity.high,
          latitude: -8.78,
          longitude: 179.0,
          timestamp: DateTime.now().subtract(const Duration(hours: 4)),
          source: 'NOAA (offline)',
        ),
      ];

  List<ClimateAlert> _fallbackAlerts() => [
        ..._fallbackFireAlerts(),
        ..._fallbackWeatherAlerts(),
      ]..sort((a, b) {
          final sevCmp = b.severity.priority.compareTo(a.severity.priority);
          if (sevCmp != 0) return sevCmp;
          return b.timestamp.compareTo(a.timestamp);
        });
}
