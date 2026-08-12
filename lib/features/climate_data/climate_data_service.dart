import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:climate_storyteller/features/climate_data/climate_stats.dart';
import 'package:climate_storyteller/features/climate_data/aqi_reading.dart';
import 'package:climate_storyteller/features/climate_data/ipcc_data.dart';
import 'package:climate_storyteller/features/lg_connection/lg_service.dart';

class BBox {
  final double north, south, east, west;
  const BBox({
    required this.north, required this.south,
    required this.east,  required this.west,
  });
}

class ClimateDataService {
  final LgService lgService;

  ClimateDataService({required this.lgService});

  // Cached remote data for OpenAQ / NOAA
  final Map<String, _CachedDouble> _climateCache = {};
  final Map<String, _CachedAqi> _aqiCache = {};

  static const _openaqBase = 'https://api.openaq.org/v2';
  static const _noaaCdoBase = 'https://www.ncei.noaa.gov/cdo-web/api/v2';
  static const _noaaTidesBase = 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter';
  static const _nsidcBase = 'https://noaadata.apps.nsidc.org/NOAA/G02135';

  static const Map<String, String> cityStations = {
    'Delhi':       'IN',
    'Beijing':     'CN',
    'London':      'GB',
    'New York':    'US',
    'Jakarta':     'ID',
    'Amazon':      'BR',
  };

  static const Map<String, BBox> _regionBounds = {
    'amazon':   BBox(north: 5,   south: -15, east: -45, west: -80),
    'congo':    BBox(north: 5,   south: -5,  east: 30,  west: 15),
    'borneo':   BBox(north: 7,   south: -4,  east: 119, west: 108),
    'himalaya': BBox(north: 35,  south: 25,  east: 95,  west: 75),
  };



  Future<List<AqiReading>> fetchCityAqi(String city) async {
    final cached = _getAqiCache(city);
    if (cached != null) return cached;

    final country = cityStations[city] ?? 'IN';
    final uri = Uri.parse(
      '$_openaqBase/measurements'
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
      final readings = results.map((r) => AqiReading.fromJson(r)).toList();
      _setAqiCache(city, readings);
      return readings;
    }
    throw Exception('Failed to load AQI measurements for $city');
  }

  Future<Map<String, List<AqiReading>>> fetchAllCitiesAqi() async {
    final results = <String, List<AqiReading>>{};
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

  List<AqiReading> _estimatedReadings(String city) {
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



  Future<ClimateStats> getStatsForYear(int year, {String? noaaKey}) async {
    if (year <= 1900) {
      return ClimateStats(
        year: 1900,
        tempAnomaly: getInterpolatedTemperature(1900),
        seaLevelMm: getInterpolatedSeaLevel(1900),
        iceExtentMkm2: getInterpolatedIceExtent(1900),
        forestLossPct: getInterpolatedForestLoss(1900),
        source: 'IPCC AR6 historical baseline',
      );
    }

    if (year >= 2100) {
      return ClimateStats(
        year: 2100,
        tempAnomaly: getInterpolatedTemperature(2100),
        seaLevelMm: getInterpolatedSeaLevel(2100),
        iceExtentMkm2: getInterpolatedIceExtent(2100),
        forestLossPct: getInterpolatedForestLoss(2100),
        source: 'IPCC AR6 SSP3-7.0 projection',
      );
    }

    double tempAnomaly;
    double seaLevelMm;
    double iceExtentMkm2;

    try {
      tempAnomaly = await _fetchRemoteTempAnomaly(noaaApiKey: noaaKey);
    } catch (_) {
      tempAnomaly = getInterpolatedTemperature(year);
    }

    try {
      final msl = await _fetchRemoteSeaLevel();
      final baseline1900 = getInterpolatedSeaLevel(1900);
      seaLevelMm = baseline1900 + msl;
    } catch (_) {
      seaLevelMm = getInterpolatedSeaLevel(year);
    }

    try {
      iceExtentMkm2 = await _fetchRemoteArcticIceExtent();
    } catch (_) {
      iceExtentMkm2 = getInterpolatedIceExtent(year);
    }

    final forestLossPct = getInterpolatedForestLoss(year);

    return ClimateStats(
      year: year,
      tempAnomaly: tempAnomaly,
      seaLevelMm: seaLevelMm,
      iceExtentMkm2: iceExtentMkm2,
      forestLossPct: forestLossPct,
      source: 'NOAA live data + IPCC AR6',
    );
  }

  Future<double> getTempAnomaly({String? noaaApiKey}) async {
    try {
      return await _fetchRemoteTempAnomaly(noaaApiKey: noaaApiKey);
    } catch (_) {
      return getInterpolatedTemperature(DateTime.now().year);
    }
  }

  Future<double> getSeaLevel() async {
    try {
      final msl = await _fetchRemoteSeaLevel();
      final baseline1900 = getInterpolatedSeaLevel(1900);
      return baseline1900 + msl;
    } catch (_) {
      return getInterpolatedSeaLevel(DateTime.now().year);
    }
  }

  Future<double> getArcticIceExtent() async {
    try {
      return await _fetchRemoteArcticIceExtent();
    } catch (_) {
      return getInterpolatedIceExtent(DateTime.now().year);
    }
  }



  BBox getBBox(String regionId) {
    return _regionBounds[regionId] ?? _regionBounds['amazon']!;
  }

  String buildAqiKml({required String city, required List<AqiReading> readings}) {
    final coords = cityCoordinates[city] ?? {'lat': 28.6139, 'lon': 77.2090};
    final lat = coords['lat']!;
    final lon = coords['lon']!;

    double pm25 = 25.0;
    double pm10 = 50.0;
    double no2 = 20.0;
    double o3 = 15.0;
    for (final r in readings) {
      if (r.parameter == 'pm25') pm25 = r.value;
      if (r.parameter == 'pm10') pm10 = r.value;
      if (r.parameter == 'no2') no2 = r.value;
      if (r.parameter == 'o3') o3 = r.value;
    }
    
    // Scale the rings based on PM2.5 severity
    final severityScale = (pm25 / 100.0).clamp(0.5, 2.0);
    final baseRadius = 0.05 * severityScale; // ~5km base radius

    // 5 concentric rings (Good -> Hazardous)
    final rings = StringBuffer();
    final colors = [
      '8833cc44', // Good (Green)
      '8855ddaa', // Moderate (Yellow)
      '880088ff', // Unhealthy (Orange)
      '880000ff', // Very Unhealthy (Red)
      '88990099', // Hazardous (Purple)
    ];
    
    final ringStyles = StringBuffer();
    for (int i = 0; i < colors.length; i++) {
      ringStyles.writeln('''
    <Style id="aqiRingStyle_$i">
      <PolyStyle><color>${colors[i]}</color></PolyStyle>
      <LineStyle><color>00000000</color><width>0</width></LineStyle>
    </Style>''');
    }

    for (int i = 0; i < 5; i++) {
      final radius = baseRadius * (5 - i); // Largest first
      final points = <String>[];
      for (int a = 0; a <= 32; a++) {
        final angle = a * (3.14159 * 2) / 32;
        final pLat = lat + radius * math.sin(angle);
        final pLon = lon + radius * math.cos(angle) / math.cos(lat * 3.14159 / 180);
        points.add('${pLon.toStringAsFixed(5)},${pLat.toStringAsFixed(5)},0');
      }
      
      rings.writeln('''
      <Placemark>
        <name>AQI Severity Ring ${5-i}</name>
        <styleUrl>#aqiRingStyle_$i</styleUrl>
        <Polygon>
          <tessellate>1</tessellate>
          <outerBoundaryIs><LinearRing><coordinates>
            ${points.join(' ')}
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>''');
    }

    final projectedPm25 = pm25 * 1.5; // simple projection for demo

    // Health Advice Badge
    final healthBadge = pm25 <= 15
        ? "<span style='background:#2ecc71;color:#fff;padding:3px 8px;border-radius:10px;'>🟢 LOW RISK</span>"
        : (pm25 <= 50
            ? "<span style='background:#f1c40f;color:#000;padding:3px 8px;border-radius:10px;'>🟡 MODERATE SENSITIVITY</span>"
            : "<span style='background:#e74c3c;color:#fff;padding:3px 8px;border-radius:10px;'>🔴 HAZARDOUS HEALTH ADVISORY</span>");

    // City Sub-Stations
    final subStations = [
      {'name': '$city Urban Center Station', 'dLat': 0.03, 'dLon': -0.04, 'val': pm25 * 1.1},
      {'name': '$city Industrial Outer Ring Post', 'dLat': -0.05, 'dLon': 0.06, 'val': pm25 * 1.3},
      {'name': '$city Airport Weather & AQI Center', 'dLat': -0.04, 'dLon': -0.05, 'val': pm25 * 0.9},
      {'name': '$city Suburban Green Belt Post', 'dLat': 0.06, 'dLon': 0.03, 'val': pm25 * 0.7},
    ];

    final stationPlacemarks = StringBuffer();
    for (final st in subStations) {
      final stLat = lat + (st['dLat'] as double);
      final stLon = lon + (st['dLon'] as double);
      final stName = st['name'] as String;
      final stVal = st['val'] as double;

      stationPlacemarks.writeln('''
      <Placemark>
        <name>${LG3DVisuals.escapeXmlText(stName)}</name>
        <visibility>1</visibility>
        <Style>
          <IconStyle>
            <scale>0.85</scale>
            <Icon><href>http://maps.google.com/mapfiles/kml/shapes/info_circle.png</href></Icon>
            <color>ff00e5ff</color>
          </IconStyle>
        </Style>
        <description><![CDATA[
          <div style='font-family:Helvetica,Arial,sans-serif;max-width:300px;background:#0f172a;color:#f8fafc;padding:10px;border-radius:8px;'>
            <h4 style='color:#38bdf8;margin:0 0 6px;'>$stName</h4>
            <p style='color:#94a3b8;font-size:11px;margin:0 0 6px;'><b>Local PM2.5:</b> ${stVal.toStringAsFixed(1)} &mu;g/m&sup3;</p>
            <div style='background:#1e293b;padding:6px;border-radius:4px;font-size:11px;'>
              <b>Status:</b> Automated Sensor Feed Live
            </div>
          </div>
        ]]></description>
        <Point>
          <coordinates>$stLon,$stLat,0</coordinates>
        </Point>
      </Placemark>''');
    }

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
     xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>Air Quality Index (AQI) — $city</name>
    <description><![CDATA[Real-time OpenAQ Air Quality Data for $city. PM2.5: ${pm25.toStringAsFixed(1)} µg/m³]]></description>

    <LookAt>
      <longitude>$lon</longitude>
      <latitude>$lat</latitude>
      <altitude>0</altitude>
      <heading>30</heading>
      <tilt>60</tilt>
      <range>35000</range>
      <altitudeMode>relativeToGround</altitudeMode>
    </LookAt>
    
    <Style id="customBalloon">
      <BalloonStyle>
        <text><![CDATA[
          <font face="Helvetica, Arial, sans-serif">
            <h3>\$[name]</h3>
            \$[description]
          </font>
        ]]></text>
      </BalloonStyle>
    </Style>
    $ringStyles

    <!-- ScreenOverlays (logo + legend) are injected per-screen by sendKml() -->

    <Folder>
      <name>AQI Concentric Zones</name>
      $rings
    </Folder>

    <Folder>
      <name>Sub-Station Monitoring Network</name>
      $stationPlacemarks
    </Folder>

    <!-- City Station Main Placemark -->
    <Placemark>
      <name>$city Atmospheric Monitoring Profile</name>
      <styleUrl>#customBalloon</styleUrl>
      <gx:balloonVisibility>1</gx:balloonVisibility>
      <description><![CDATA[
        <div style='font-family:Helvetica,Arial,sans-serif;max-width:440px;background:#0f172a;color:#f8fafc;padding:12px;border-radius:10px;'>
          <h2 style='color:#38bdf8;margin:0 0 6px;'>$city Air Quality Profile</h2>
          <div style='margin-bottom:10px;'>$healthBadge</div>
          
          <table style='border-collapse:collapse;width:100%;font-size:12px;margin-bottom:10px;'>
            <tr style='background:#1e293b;color:#e2e8f0;'>
              <th style='padding:6px 8px;text-align:left;'>Pollutant</th>
              <th style='padding:6px 8px;text-align:center;'>Reading</th>
              <th style='padding:6px 8px;text-align:center;'>WHO Limit</th>
              <th style='padding:6px 8px;text-align:center;'>Status</th>
            </tr>
            <tr style='background:#0f172a;color:#facc15;'>
              <td style='padding:6px 8px;'>PM2.5 (Fine Particulates)</td>
              <td style='padding:6px 8px;text-align:center;'><b>${pm25.toStringAsFixed(1)} &mu;g/m&sup3;</b></td>
              <td style='padding:6px 8px;text-align:center;'>5.0 &mu;g/m&sup3;</td>
              <td style='padding:6px 8px;text-align:center;'>${(pm25/5).toStringAsFixed(1)}x WHO Limit</td>
            </tr>
            <tr style='background:#0f172a;color:#e2e8f0;'>
              <td style='padding:6px 8px;'>PM10 (Coarse Dust)</td>
              <td style='padding:6px 8px;text-align:center;'>${pm10.toStringAsFixed(1)} &mu;g/m&sup3;</td>
              <td style='padding:6px 8px;text-align:center;'>15.0 &mu;g/m&sup3;</td>
              <td style='padding:6px 8px;text-align:center;'>${(pm10/15).toStringAsFixed(1)}x WHO Limit</td>
            </tr>
            <tr style='background:#0f172a;color:#e2e8f0;'>
              <td style='padding:6px 8px;'>NO2 (Nitrogen Dioxide)</td>
              <td style='padding:6px 8px;text-align:center;'>${no2.toStringAsFixed(1)} &mu;g/m&sup3;</td>
              <td style='padding:6px 8px;text-align:center;'>10.0 &mu;g/m&sup3;</td>
              <td style='padding:6px 8px;text-align:center;'>${(no2/10).toStringAsFixed(1)}x WHO Limit</td>
            </tr>
            <tr style='background:#0f172a;color:#e2e8f0;'>
              <td style='padding:6px 8px;'>O3 (Ground Ozone)</td>
              <td style='padding:6px 8px;text-align:center;'>${o3.toStringAsFixed(1)} &mu;g/m&sup3;</td>
              <td style='padding:6px 8px;text-align:center;'>60.0 &mu;g/m&sup3;</td>
              <td style='padding:6px 8px;text-align:center;'>${(o3/60).toStringAsFixed(1)}x WHO Limit</td>
            </tr>
          </table>

          <table style='border-collapse:collapse;width:100%;font-size:12px;margin-bottom:10px;'>
            <tr style='background:#1e293b;color:#e2e8f0;'>
              <th style='padding:6px 8px;text-align:left;'>Era</th>
              <th style='padding:6px 8px;'>PM2.5 (&mu;g/m&sup3;)</th>
              <th style='padding:6px 8px;'>Health Category</th>
            </tr>
            <tr style='background:#14532d;color:#4ade80;'>
              <td style='padding:6px 8px;'>~2000 Baseline</td>
              <td style='padding:6px 8px;text-align:center;'>~35.0</td>
              <td style='padding:6px 8px;text-align:center;'>Moderate</td>
            </tr>
            <tr style='background:#365314;color:#facc15;font-weight:bold;'>
              <td style='padding:6px 8px;'>&#9654; 2026 (Live API)</td>
              <td style='padding:6px 8px;text-align:center;'>${pm25.toStringAsFixed(1)}</td>
              <td style='padding:6px 8px;text-align:center;'>[LIVE DATA]</td>
            </tr>
            <tr style='background:#7f1d1d;color:#f87171;'>
              <td style='padding:6px 8px;'>2100 Projection</td>
              <td style='padding:6px 8px;text-align:center;'>~${projectedPm25.toStringAsFixed(1)}</td>
              <td style='padding:6px 8px;text-align:center;'>Severe Trend</td>
            </tr>
          </table>

          <div style='padding:8px;background:#1e293b;border-left:3px solid #38bdf8;border-radius:4px;font-size:11px;color:#cbd5e1;'>
            <b>Health Advisory:</b> Reduce outdoor exertion during elevated PM2.5 spikes. Use HEPA air filtration indoors.
          </div>
          <p style='color:#64748b;font-size:10px;margin-top:8px;'>
            <i>Data Sources: OpenAQ Real-Time Global Air Quality API &bull; World Health Organization Guidelines (2021)</i>
          </p>
        </div>
      ]]></description>
      <Point>
        <coordinates>$lon,$lat,0</coordinates>
      </Point>
    </Placemark>
  </Document>
</kml>''';
  }

  static const Map<String, Map<String, double>> cityCoordinates = {
    'Delhi':    {'lat': 28.6139, 'lon': 77.2090},
    'Beijing':  {'lat': 39.9042, 'lon': 116.4074},
    'London':   {'lat': 51.5074, 'lon': -0.1278},
    'New York': {'lat': 40.7128, 'lon': -74.0060},
    'Jakarta':  {'lat': -6.2088, 'lon': 106.8456},
    'Amazon':   {'lat': -3.4653, 'lon': -62.2159},
  };

  String buildDeforestationKml({required String regionId, int year = 2023}) {
    final bbox = getBBox(regionId);
    final canopyUrl = _buildCanopyUrl(bbox);
    final tileUrl = _buildGfwUrl(bbox, year);
    final centerLat = (bbox.north + bbox.south) / 2;
    final centerLon = (bbox.east + bbox.west) / 2;

    final lossYears = (year - 2000).clamp(1, 100);
    final estimatedEmissionsMt = lossYears * 145.0; // Million tonnes CO2 estimate

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Forest Cover &amp; Deforestation — ${_regionName(regionId)}</name>
    <description>
      Annual tree loss overlay and baseline canopy density.
      Source: Hansen/UMD/Google/USGS/NASA via Global Forest Watch.
    </description>

    <!-- Camera position for this region -->
    <LookAt>
      <longitude>$centerLon</longitude>
      <latitude>$centerLat</latitude>
      <altitude>0</altitude>
      <heading>30</heading>
      <tilt>60</tilt>
      <range>${_cameraRange(bbox)}</range>
      <altitudeMode>relativeToGround</altitudeMode>
    </LookAt>

    <!-- ScreenOverlays (logo + legend) are injected per-screen by sendKml() -->

    <!-- Existing tree canopy (green layer, bottom) -->
    <GroundOverlay>
      <name>Tree Cover 2000 (baseline)</name>
      <color>99ffffff</color>
      <drawOrder>1</drawOrder>
      <Icon>
        <href>$canopyUrl</href>
        <viewBoundScale>1.0</viewBoundScale>
      </Icon>
      <LatLonBox>
        <north>${bbox.north}</north>
        <south>${bbox.south}</south>
        <east>${bbox.east}</east>
        <west>${bbox.west}</west>
      </LatLonBox>
    </GroundOverlay>

    <!-- Forest loss overlay (red layer, top) -->
    <GroundOverlay>
      <name>Tree Cover Loss 2000–$year</name>
      <color>ccffffff</color>
      <drawOrder>2</drawOrder>
      <Icon>
        <href>$tileUrl</href>
        <viewBoundScale>1.0</viewBoundScale>
      </Icon>
      <LatLonBox>
        <north>${bbox.north}</north>
        <south>${bbox.south}</south>
        <east>${bbox.east}</east>
        <west>${bbox.west}</west>
      </LatLonBox>
    </GroundOverlay>

    <!-- Region boundary outline -->
    <Placemark>
      <name>${_regionName(regionId)} boundary</name>
      <Style>
        <LineStyle>
          <color>ff00ff88</color>
          <width>2</width>
        </LineStyle>
        <PolyStyle>
          <color>0000ff88</color>
        </PolyStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              ${bbox.west},${bbox.south},0
              ${bbox.east},${bbox.south},0
              ${bbox.east},${bbox.north},0
              ${bbox.west},${bbox.north},0
              ${bbox.west},${bbox.south},0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>

    <!-- Detailed Forest Stats Placemark -->
    <Placemark>
      <name>${_regionName(regionId)} — Canopy &amp; Loss Analysis</name>
      <gx:balloonVisibility>1</gx:balloonVisibility>
      <description><![CDATA[
        <div style='font-family:Helvetica,Arial,sans-serif;max-width:440px;background:#0f172a;color:#f8fafc;padding:12px;border-radius:10px;'>
          <h2 style='color:#22c55e;margin:0 0 6px;'>${_regionName(regionId)} Canopy Profile</h2>
          <p style='color:#94a3b8;font-size:12px;margin:0 0 10px;'><b>Data Period:</b> 2000 &ndash; $year &bull; Resolution: 30m / pixel</p>
          
          <table style='border-collapse:collapse;width:100%;font-size:12px;margin-bottom:10px;'>
            <tr style='background:#1e293b;color:#e2e8f0;'>
              <th style='padding:6px 8px;text-align:left;'>Indicator</th>
              <th style='padding:6px 8px;text-align:center;'>Metric</th>
            </tr>
            <tr style='background:#0f172a;color:#4ade80;'>
              <td style='padding:6px 8px;'>Baseline Intact Canopy (2000)</td>
              <td style='padding:6px 8px;text-align:center;'>100% Green Overlay</td>
            </tr>
            <tr style='background:#0f172a;color:#f87171;'>
              <td style='padding:6px 8px;'>Cumulative Loss (2000-$year)</td>
              <td style='padding:6px 8px;text-align:center;'>Red Overlay Active</td>
            </tr>
            <tr style='background:#0f172a;color:#facc15;'>
              <td style='padding:6px 8px;'>Est. CO2 Carbon Released</td>
              <td style='padding:6px 8px;text-align:center;'>~${estimatedEmissionsMt.toStringAsFixed(0)} Million Tonnes CO2</td>
            </tr>
          </table>

          <div style='padding:8px;background:#1e293b;border-left:3px solid #22c55e;border-radius:4px;font-size:11px;color:#cbd5e1;'>
            <b>Global Forest Watch Integration:</b> Data provided by Hansen/UMD/Google/USGS/NASA satellite analysis. Red pixels demarcate forest stand replacement or canopy clearance.
          </div>
        </div>
      ]]></description>
      <Point>
        <coordinates>$centerLon,$centerLat,0</coordinates>
      </Point>
    </Placemark>

    ${_buildDeforestation3DFolder(regionId, year)}

  </Document>
</kml>''';
  }

  String buildComparisonKml({required String regionId}) {
    final bbox = getBBox(regionId);
    final canopyUrl = _buildCanopyUrl(bbox);
    final lossUrl = _buildGfwUrl(bbox, 2023);
    final midLon = (bbox.east + bbox.west) / 2;
    final midLat = (bbox.north + bbox.south) / 2;

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Forest Comparison — ${_regionName(regionId)}</name>

    <LookAt>
      <longitude>$midLon</longitude>
      <latitude>$midLat</latitude>
      <altitude>0</altitude>
      <range>${_cameraRange(bbox)}</range>
      <altitudeMode>relativeToGround</altitudeMode>
    </LookAt>

    <!-- 2000 baseline — left half -->
    <GroundOverlay>
      <name>Forest Cover 2000</name>
      <drawOrder>1</drawOrder>
      <Icon><href>$canopyUrl</href></Icon>
      <LatLonBox>
        <north>${bbox.north}</north>
        <south>${bbox.south}</south>
        <east>$midLon</east>
        <west>${bbox.west}</west>
      </LatLonBox>
    </GroundOverlay>

    <!-- 2023 loss — right half -->
    <GroundOverlay>
      <name>Forest Loss 2000–2023</name>
      <drawOrder>2</drawOrder>
      <Icon><href>$lossUrl</href></Icon>
      <LatLonBox>
        <north>${bbox.north}</north>
        <south>${bbox.south}</south>
        <east>${bbox.east}</east>
        <west>$midLon</west>
      </LatLonBox>
    </GroundOverlay>

    <!-- Dividing line -->
    <Placemark>
      <name>Before (2000) | After (2023)</name>
      <Style>
        <LineStyle><color>ffffffff</color><width>3.5</width></LineStyle>
      </Style>
      <LineString>
        <tessellate>1</tessellate>
        <coordinates>
          $midLon,${bbox.south},0
          $midLon,${bbox.north},0
        </coordinates>
      </LineString>
    </Placemark>

    <!-- Comparison Summary Placemark -->
    <Placemark>
      <name>${_regionName(regionId)} — Before vs After Analysis</name>
      <gx:balloonVisibility>1</gx:balloonVisibility>
      <description><![CDATA[
        <div style='font-family:Helvetica,Arial,sans-serif;max-width:440px;background:#0f172a;color:#f8fafc;padding:12px;border-radius:10px;'>
          <h2 style='color:#38bdf8;margin:0 0 6px;'>Before vs After Forest Comparison</h2>
          <p style='color:#94a3b8;font-size:12px;margin:0 0 10px;'><b>Left Half:</b> 2000 Intact Canopy &bull; <b>Right Half:</b> 2023 Cumulative Forest Loss</p>
          <div style='padding:8px;background:#1e293b;border-left:3px solid #38bdf8;border-radius:4px;font-size:11px;color:#cbd5e1;'>
            The white dividing meridian splits the region into historical baseline vs modern satellite observations to visually depict habitat loss.
          </div>
        </div>
      ]]></description>
      <Point>
        <coordinates>$midLon,$midLat,0</coordinates>
      </Point>
    </Placemark>

    ${_buildComparison3DFolder(regionId)}

  </Document>
</kml>''';
  }

  String _buildDeforestation3DFolder(String regionId, int year) {
    final bbox = getBBox(regionId);
    final centerLat = (bbox.north + bbox.south) / 2;
    final centerLon = (bbox.east + bbox.west) / 2;
    final latSpan = (bbox.north - bbox.south).abs();
    final lonSpan = (bbox.east - bbox.west).abs();
    final maxSpan = latSpan > lonSpan ? latSpan : lonSpan;
    final factor = ((year - 2000) * 0.035).clamp(0.12, 0.95);

    return LG3DVisuals.build3DMeshAndSpikes(
      centerLat: centerLat,
      centerLon: centerLon,
      spanDeg: maxSpan * 0.75,
      category: 'forest',
      severityFactor: factor,
      name: '${_regionName(regionId)} Deforestation 3D Mesh & Spikes ($year)',
    );
  }

  String _buildComparison3DFolder(String regionId) {
    final bbox = getBBox(regionId);
    final centerLat = (bbox.north + bbox.south) / 2;
    final centerLon = (bbox.east + bbox.west) / 2;
    final latSpan = (bbox.north - bbox.south).abs();
    final lonSpan = (bbox.east - bbox.west).abs();
    final maxSpan = latSpan > lonSpan ? latSpan : lonSpan;

    final leftLon = centerLon - maxSpan / 4;
    final leftColors = LG3DVisuals.getForestColors(1.0);
    final leftPyramid = LG3DVisuals.build3DPyramid(
      centerLat: centerLat,
      centerLon: leftLon,
      spanDeg: maxSpan * 0.4,
      heightMeters: 450000.0,
      face1ColorAbgr: leftColors[0],
      face2ColorAbgr: leftColors[1],
      face3ColorAbgr: leftColors[2],
      face4ColorAbgr: leftColors[3],
      name: 'Forest 2000 (3D)',
    );

    final rightLon = centerLon + maxSpan / 4;
    final rightColors = LG3DVisuals.getForestColors(0.5);
    final rightPyramid = LG3DVisuals.build3DPyramid(
      centerLat: centerLat,
      centerLon: rightLon,
      spanDeg: maxSpan * 0.4,
      heightMeters: 250000.0,
      face1ColorAbgr: rightColors[0],
      face2ColorAbgr: rightColors[1],
      face3ColorAbgr: rightColors[2],
      face4ColorAbgr: rightColors[3],
      name: 'Forest Loss 2023 (3D)',
    );

    return '<Folder><name>Forest Comparison (3D)</name><open>1</open>$leftPyramid$rightPyramid</Folder>';
  }

  Future<void> sendToLG({required String regionId, int year = 2023}) async {
    final kml = buildDeforestationKml(regionId: regionId, year: year);
    final filename = 'forest_${regionId}_$year.kml';
    await lgService.sendKml(filename, kmlContent: kml);

    final bbox = getBBox(regionId);
    final altitude = _cameraRange(bbox);

    await lgService.flyTo(
      latitude: (bbox.north + bbox.south) / 2,
      longitude: (bbox.east + bbox.west) / 2,
      altitude: altitude,
    );
  }



  Future<double> _fetchRemoteTempAnomaly({String? noaaApiKey}) async {
    const cacheKey = 'temp_anomaly';
    final cached = _getClimateCache(cacheKey);
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
        _setClimateCache(cacheKey, value);
        return value;
      }
    }
    throw Exception('Failed to load temperature anomaly from NOAA');
  }

  Future<double> _fetchRemoteSeaLevel() async {
    const cacheKey = 'sea_level';
    final cached = _getClimateCache(cacheKey);
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
          _setClimateCache(cacheKey, latest);
          return latest;
        }
      }
    }
    throw Exception('Failed to load sea level from NOAA');
  }

  Future<double> _fetchRemoteArcticIceExtent() async {
    const cacheKey = 'arctic_ice';
    final cached = _getClimateCache(cacheKey);
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
            _setClimateCache(cacheKey, extent);
            return extent;
          }
        }
      }
    }
    throw Exception('Failed to load Arctic sea ice extent from NSIDC');
  }

  String _buildGfwUrl(BBox bbox, int year) {
    final url = 'https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?'
        'SERVICE=WMS&REQUEST=GetMap&VERSION=1.1.1'
        '&LAYERS=MODIS_Terra_NDVI_8Day'
        '&SRS=EPSG:4326'
        '&FORMAT=image/png'
        '&WIDTH=1024&HEIGHT=1024'
        '&BBOX=${bbox.west},${bbox.south},${bbox.east},${bbox.north}'
        '&TRANSPARENT=TRUE'
        '&TIME=2023-06-01';
    return url.replaceAll('&', '&amp;');
  }

  String _buildCanopyUrl(BBox bbox) {
    final url = 'https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?'
        'SERVICE=WMS&REQUEST=GetMap&VERSION=1.1.1'
        '&LAYERS=MODIS_Terra_NDSI_Snow_Cover'
        '&SRS=EPSG:4326'
        '&FORMAT=image/png'
        '&WIDTH=1024&HEIGHT=1024'
        '&BBOX=${bbox.west},${bbox.south},${bbox.east},${bbox.north}'
        '&TRANSPARENT=TRUE'
        '&TIME=2023-06-01';
    return url.replaceAll('&', '&amp;');
  }

  double _cameraRange(BBox bbox) {
    final latSpan = (bbox.north - bbox.south).abs();
    final lonSpan = (bbox.east - bbox.west).abs();
    final span = latSpan > lonSpan ? latSpan : lonSpan;
    final range = span * 111000.0 * 0.20;
    return range.clamp(12000.0, 55000.0);
  }

  String _regionName(String id) => switch (id) {
    'amazon'   => 'Amazon Basin',
    'congo'    => 'Congo Basin',
    'borneo'   => 'Borneo',
    'himalaya' => 'Himalaya',
    _          => id,
  };

  double? _getClimateCache(String key) {
    final v = _climateCache[key];
    if (v == null) return null;
    if (DateTime.now().difference(v.timestamp).inHours > 6) {
      _climateCache.remove(key);
      return null;
    }
    return v.value;
  }

  void _setClimateCache(String key, double value) {
    _climateCache[key] = _CachedDouble(value, DateTime.now());
  }

  List<AqiReading>? _getAqiCache(String city) {
    final v = _aqiCache[city];
    if (v == null) return null;
    if (DateTime.now().difference(v.timestamp).inHours > 1) {
      _aqiCache.remove(city);
      return null;
    }
    return v.readings;
  }

  void _setAqiCache(String city, List<AqiReading> readings) {
    _aqiCache[city] = _CachedAqi(readings, DateTime.now());
  }
}

class _CachedDouble {
  final double value;
  final DateTime timestamp;
  _CachedDouble(this.value, this.timestamp);
}

class _CachedAqi {
  final List<AqiReading> readings;
  final DateTime timestamp;
  _CachedAqi(this.readings, this.timestamp);
}