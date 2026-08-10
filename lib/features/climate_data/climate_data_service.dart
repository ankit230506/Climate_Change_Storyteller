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
    for (final r in readings) {
      if (r.parameter == 'pm25') pm25 = r.value;
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
    
    for (int i = 0; i < 5; i++) {
      final radius = baseRadius * (5 - i); // Largest first
      final color = colors[i];
      final points = <String>[];
      for (int a = 0; a <= 32; a++) {
        final angle = a * (3.14159 * 2) / 32;
        final pLat = lat + radius * math.sin(angle);
        // adjust longitude based on latitude to keep roughly circular
        final pLon = lon + radius * math.cos(angle) / math.cos(lat * 3.14159 / 180);
        points.add('${pLon.toStringAsFixed(5)},${pLat.toStringAsFixed(5)},0');
      }
      
      rings.writeln('''
      <Placemark>
        <name>AQI Zone ${5-i}</name>
        <Style>
          <PolyStyle><color>$color</color></PolyStyle>
          <LineStyle><color>00000000</color><width>0</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>1</tessellate>
          <outerBoundaryIs><LinearRing><coordinates>
            ${points.join(' ')}
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>''');
    }

    final projectedPm25 = pm25 * 1.5; // simple projection for demo

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

    <!-- ScreenOverlays (logo + legend) are injected per-screen by sendKml() -->

    <Folder>
      <name>AQI Zones</name>
      $rings
    </Folder>

    <!-- City Station Placemark -->
    <Placemark>
      <name>$city Air Quality Center</name>
      <styleUrl>#customBalloon</styleUrl>
      <description><![CDATA[
        <b>$city Air Quality — Past vs Present vs Future</b><br/>
        <table border='1' cellpadding='4' style='border-collapse:collapse; width:300px; margin-top:10px;'>
          <tr style='background:#f0f0f0'><th>Era</th><th>PM2.5 (µg/m³)</th><th>Status</th></tr>
          <tr style='background:#d4edda'><td>~2000</td><td>~60.0</td><td>Moderate</td></tr>
          <tr style='background:#fff3cd'><td><b>2026</b></td><td><b>${pm25.toStringAsFixed(1)}</b></td><td><b>[LIVE]</b></td></tr>
          <tr style='background:#f8d7da'><td>2100</td><td>~${projectedPm25.toStringAsFixed(1)}</td><td>Projected</td></tr>
        </table>
        <br/>
        <i>WHO Annual Guideline: 5 µg/m³</i><br/>
        Source: OpenAQ Real-Time Global Air Quality API
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
    final tileUrl = _buildGfwUrl(year);
    final canopyUrl = _buildCanopyUrl();

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
     xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>Forest Loss — ${_regionName(regionId)} ($year)</name>
    <description>
      Global Forest Watch data showing tree cover loss.
      Red areas = forest lost since 2000.
      Green areas = remaining tree cover.
      Source: Hansen/UMD/Google/USGS/NASA via Global Forest Watch.
    </description>

    <!-- Camera position for this region -->
    <LookAt>
      <longitude>${(bbox.east + bbox.west) / 2}</longitude>
      <latitude>${(bbox.north + bbox.south) / 2}</latitude>
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

    <!-- Stats placemark in centre -->
    <Placemark>
      <name>${_regionName(regionId)} — Forest Loss Data</name>
      <description><![CDATA[
        <b>${_regionName(regionId)} Deforestation</b><br/>
        Data period: 2000 – $year<br/>
        Source: Global Forest Watch (Hansen et al.)<br/>
        Resolution: 30m per pixel<br/>
        Red = tree cover loss<br/>
        Green = remaining canopy<br/><br/>
        <a href="https://www.globalforestwatch.org">
          globalforestwatch.org
        </a>
      ]]></description>
      <Point>
        <coordinates>
          ${(bbox.east + bbox.west) / 2},
          ${(bbox.north + bbox.south) / 2},0
        </coordinates>
      </Point>
    </Placemark>

    ${_buildDeforestation3DFolder(regionId, year)}

  </Document>
</kml>''';
  }

  String buildComparisonKml({required String regionId}) {
    final bbox = getBBox(regionId);
    final canopyUrl = _buildCanopyUrl();
    final lossUrl = _buildGfwUrl(2023);
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
      <name>Before | After</name>
      <Style>
        <LineStyle><color>ffffffff</color><width>3</width></LineStyle>
      </Style>
      <LineString>
        <tessellate>1</tessellate>
        <coordinates>
          $midLon,${bbox.south},0
          $midLon,${bbox.north},0
        </coordinates>
      </LineString>
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

  String _buildGfwUrl(int year) {
    final url = 'https://api.resourcewatch.org/v1/layer/'
        'umd-tree-cover-loss/tile/gee/{z}/{x}/{y}'
        '?startYear=2000&endYear=$year';
    // Escape for XML embedding — a raw "&" inside a KML <href> is invalid
    // XML and breaks parsing of the whole document, not just this overlay.
    return url.replaceAll('&', '&amp;');
  }

  String _buildCanopyUrl() {
    return 'https://api.resourcewatch.org/v1/layer/'
        'umd-tree-cover-density-2000/tile/gee/{z}/{x}/{y}';
  }

  double _cameraRange(BBox bbox) {
    final latSpan = (bbox.north - bbox.south).abs();
    final lonSpan = (bbox.east - bbox.west).abs();
    final span = latSpan > lonSpan ? latSpan : lonSpan;
    final range = span * 111000.0 * 0.45;
    return range.clamp(35000.0, 220000.0);
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