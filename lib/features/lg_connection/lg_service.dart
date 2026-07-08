import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:climate_storyteller/features/explore/climate_region.dart';
import 'package:climate_storyteller/features/explore/climate_era.dart';
import 'package:climate_storyteller/features/climate_data/ipcc_data.dart';
import 'package:climate_storyteller/features/lg_connection/lg_rig_state.dart';
import 'package:climate_storyteller/core/storage/secure_storage_service.dart';

class LgService {
  SSHClient? _client;
  LGRigState _state = const LGRigState();
  final _stateCtrl = StreamController<LGRigState>.broadcast();
  Timer? _keepaliveTimer;

  Stream<LGRigState> get stateStream => _stateCtrl.stream;
  LGRigState get state => _state;

  static const _kmlDir = '/var/www/html/kml';
  static const _queryFile = '/tmp/query.txt';
  static const _kmlSyncFile = '/var/www/html/kmls.txt';

  static const _gibsBase = 'https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi';
  static const _noaaBase = 'https://www.ncei.noaa.gov/cdo-web/api/v2';

  static const Map<String, String> _gibsLayers = {
    'glacier':  'MODIS_Terra_Sea_Ice_Extent',
    'sealevel': 'VIIRS_NOAA20_CorrectedReflectance_TrueColor',
    'forest':   'MODIS_Terra_NDVI_8Day',
    'heat':     'MODIS_Terra_Land_Surface_Temp_Day',
  };

  // ─────────────────────────────────────────────
  // SSH & Connection Methods
  // ─────────────────────────────────────────────

  Future<bool> connect({
    required String ipAddress,
    int port = 22,
    String username = 'lg',
    String password = 'lg',
    int screenCount = 3,
  }) async {
    _update(_state.copyWith(status: LGConnectionStatus.connecting));

    try {
      final socket = await SSHSocket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 10),
      );
      final client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );
      await client.authenticated;
      _client = client;

      // Verify kml folder exists, create if not
      await execute('mkdir -p $_kmlDir');

      final sw = Stopwatch()..start();
      await execute('echo ping');
      final latency = sw.elapsedMilliseconds;

      await SecureStorageService.instance.saveLgCredentials(
        ip: ipAddress,
        port: port,
        username: username,
        password: password,
        screen: screenCount.toString(),
      );

      _update(_state.copyWith(
        status: LGConnectionStatus.connected,
        ipAddress: ipAddress,
        port: port,
        screenCount: screenCount,
        latencyMs: latency,
      ));

      _startKeepalive();
      return true;
    } catch (e) {
      _client?.close();
      _client = null;
      _update(_state.copyWith(
        status: LGConnectionStatus.error,
        errorMessage: e.toString(),
      ));
      return false;
    }
  }

  Future<void> disconnect() async {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _client?.close();
    _client = null;
    _update(const LGRigState());
  }

  Future<String> execute(String command) async {
    final client = _client;
    if (client == null) throw Exception('Not connected to LG rig');
    final result = await client.run(command);
    return String.fromCharCodes(result);
  }

  // ─────────────────────────────────────────────
  // LG Action Methods
  // ─────────────────────────────────────────────

  Future<void> sendKml(String kmlFilename, {String? kmlContent}) async {
    if (_client == null) throw Exception('Not connected');

    if (kmlContent != null && kmlContent.isNotEmpty) {
      final b64 = base64Encode(utf8.encode(kmlContent));
      await execute(
        "echo '$b64' | base64 -d > $_kmlDir/$kmlFilename",
      );
    }

    final kmlUrl = 'http://lg1:81/kml/$kmlFilename';
    final netLinkKml = _buildNetworkLinkKml(kmlUrl);
    final b64NetLink = base64Encode(utf8.encode(netLinkKml));

    for (int i = 2; i <= _state.screenCount; i++) {
      try {
        final cmd =
            'sshpass -p lg ssh -o StrictHostKeyChecking=no '
            'lg@lg$i "echo \'$b64NetLink\' | base64 -d > $_kmlDir/kml_$i.kml && echo \'$b64NetLink\' | base64 -d > $_kmlDir/slave_$i.kml" 2>&1';
        await execute(cmd);
      } catch (_) {}
    }

    await execute("echo '$b64NetLink' | base64 -d > $_kmlSyncFile");
    await execute("echo '$b64NetLink' | base64 -d > $_kmlDir/kml_1.kml");
    await execute("echo '$b64NetLink' | base64 -d > $_kmlDir/slave_1.kml");
    await execute("echo '$b64NetLink' | base64 -d > $_kmlDir/master.kml");

    await execute("echo '$kmlUrl' > $_queryFile");

    _update(_state.copyWith(currentKml: kmlFilename));
  }

  Future<void> flyTo({
    required double latitude,
    required double longitude,
    required double altitude,
    double tilt = 0,
    double heading = 0,
  }) async {
    if (_client == null) throw Exception('Not connected');

    final lookAtKml =
        'flytoview=<LookAt>'
        '<longitude>$longitude</longitude>'
        '<latitude>$latitude</latitude>'
        '<altitude>0</altitude>'
        '<heading>$heading</heading>'
        '<tilt>$tilt</tilt>'
        '<range>$altitude</range>'
        '<altitudeMode>relativeToGround</altitudeMode>'
        '</LookAt>';

    await execute("echo '$lookAtKml' > $_queryFile");
  }

  Future<void> clearKml() async {
    if (_client == null) throw Exception('Not connected');

    // Clear KML files and syndication on master
    await execute("rm -f $_kmlDir/*.kml 2>&1");
    await execute("echo '' > $_kmlSyncFile 2>&1");

    // Clear KML files on slave screens
    for (int i = 2; i <= _state.screenCount; i++) {
      try {
        await execute(
          'sshpass -p lg ssh -o StrictHostKeyChecking=no '
          'lg@lg$i "rm -f $_kmlDir/*.kml" 2>&1',
        );
      } catch (_) {}
    }
    _update(_state.copyWith(currentKml: null));
  }

  Future<void> relaunchGoogleEarth() async {
    if (_client == null) throw Exception('Not connected');
    await execute('/home/lg/bin/lg-relaunch 2>&1 || DISPLAY=:0 /home/lg/earth/googleearth &');
  }

  // ─────────────────────────────────────────────
  // KML Generation Methods
  // ─────────────────────────────────────────────

  Future<Directory> get _localKmlDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/kmls');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<String> buildKml({
    required ClimateRegion region,
    required ClimateEra era,
    String? noaaApiKey,
  }) async {
    final filename = '${region.id}_${era.label}_${region.category}.kml';
    final dir = await _localKmlDir;
    final file = File('${dir.path}/$filename');

    if (file.existsSync()) {
      final age = DateTime.now().difference(file.lastModifiedSync());
      if (age.inHours < 24) return file.path;
    }

    final kml = await _generateKml(region: region, era: era, noaaApiKey: noaaApiKey);
    await file.writeAsString(kml, encoding: utf8);
    return file.path;
  }

  Future<List<FileSystemEntity>> listCachedKmls() async {
    final dir = await _localKmlDir;
    return dir.listSync().where((f) => f.path.endsWith('.kml')).toList();
  }

  Future<void> clearCache() async {
    final dir = await _localKmlDir;
    for (final f in dir.listSync()) {
      f.deleteSync();
    }
  }

  // ─────────────────────────────────────────────
  // Private Helper Methods
  // ─────────────────────────────────────────────

  Future<String> _generateKml({
    required ClimateRegion region,
    required ClimateEra era,
    String? noaaApiKey,
  }) async {
    final regionData = getRegionData(region.id);
    final eraYear = int.parse(era.label);

    final overlayUrl = _buildGibsOverlayUrl(region.category, era);
    final stats = _getEraStats(regionData, region.category, eraYear);
    final noaaTemp = await _fetchNoaaTemperature(noaaApiKey);

    return _buildKmlString(
      region: region,
      era: era,
      overlayUrl: overlayUrl,
      stats: stats,
      noaaGlobalTemp: noaaTemp,
      regionData: regionData,
    );
  }

  String _buildGibsOverlayUrl(String category, ClimateEra era) {
    final layer = _gibsLayers[category] ?? _gibsLayers['glacier']!;
    final date = switch (era) {
      ClimateEra.preindustrial1900 => '2000-02-24',
      ClimateEra.present2026       => '2026-01-01',
      ClimateEra.projected2100     => '2024-01-01',
    };

    return '$_gibsBase?'
        'SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0'
        '&LAYERS=$layer'
        '&CRS=CRS:84'
        '&FORMAT=image/png'
        '&WIDTH=1024&HEIGHT=512'
        '&BBOX=-180,-90,180,90'
        '&TIME=$date';
  }

  Future<double?> _fetchNoaaTemperature(String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) return null;
    try {
      final uri = Uri.parse(
        '$_noaaBase/data?datasetid=GHCND'
        '&datatypeid=TAVG'
        '&stationid=GHCND:USW00094728'
        '&limit=1'
        '&sortfield=date&sortorder=desc',
      );
      final res = await http.get(uri,
          headers: {'token': apiKey}).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final value = body['results']?[0]?['value'] as num?;
        return value?.toDouble();
      }
    } catch (_) {}
    return null;
  }

  Map<String, String> _getEraStats(IpccRegionData? data, String category, int year) {
    final tempAnomaly = _interpolate(kTemperatureAnomaly, year);
    final seaLevel = _interpolate(kSeaLevelRise, year);
    final iceExtent = _interpolate(kArcticIceExtent, year);
    final forestLoss = _interpolate(kForestCoverLoss, year);

    return {
      'temp_anomaly': '+${tempAnomaly.toStringAsFixed(1)}°C',
      'sea_level':    '${seaLevel.toStringAsFixed(0)} mm',
      'ice_extent':   '${iceExtent.toStringAsFixed(1)} M km²',
      'forest_loss':  '${forestLoss.toStringAsFixed(1)}%',
    };
  }

  double _interpolate(Map<int, double> data, int year) {
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

  String _buildKmlString({
    required ClimateRegion region,
    required ClimateEra era,
    required String overlayUrl,
    required Map<String, String> stats,
    required double? noaaGlobalTemp,
    required IpccRegionData? regionData,
  }) {
    final description = regionData?.description[int.parse(era.label)] ??
        'Climate data for ${region.name} — ${era.label}';

    final tempLine = noaaGlobalTemp != null
        ? '<Data name="noaa_live_temp"><value>$noaaGlobalTemp°C</value></Data>'
        : '';

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
     xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>${region.name} — ${era.label}</name>
    <description><![CDATA[$description]]></description>

    <!-- Camera position -->
    <LookAt>
      <longitude>${region.longitude}</longitude>
      <latitude>${region.latitude}</latitude>
      <altitude>0</altitude>
      <heading>0</heading>
      <tilt>0</tilt>
      <range>${region.altitude}</range>
      <altitudeMode>relativeToGround</altitudeMode>
    </LookAt>

    <!-- NASA GIBS overlay -->
    <GroundOverlay>
      <name>NASA GIBS — ${era.label}</name>
      <description>Source: NASA GIBS WMTS</description>
      <Icon>
        <href>$overlayUrl</href>
        <viewBoundScale>0.75</viewBoundScale>
      </Icon>
      <LatLonBox>
        <north>90</north>
        <south>-90</south>
        <east>180</east>
        <west>-180</west>
      </LatLonBox>
      <altitude>0</altitude>
      <altitudeMode>clampToGround</altitudeMode>
    </GroundOverlay>

    <!-- Region placemark -->
    <Placemark>
      <name>${region.name}</name>
      <description><![CDATA[
        <b>${region.name} — ${era.label}</b><br/>
        $description<br/><br/>
        <b>Climate Statistics (IPCC AR6 SSP3-7.0)</b><br/>
        🌡️ Temp anomaly: ${stats['temp_anomaly']}<br/>
        🌊 Sea level rise: ${stats['sea_level']}<br/>
        🧊 Arctic ice extent: ${stats['ice_extent']}<br/>
        🌲 Forest cover loss: ${stats['forest_loss']}<br/>
        $tempLine
      ]]></description>
      <ExtendedData>
        <Data name="era"><value>${era.label}</value></Data>
        <Data name="category"><value>${region.category}</value></Data>
        <Data name="temp_anomaly"><value>${stats['temp_anomaly']}</value></Data>
        <Data name="sea_level_rise"><value>${stats['sea_level']}</value></Data>
        <Data name="ice_extent"><value>${stats['ice_extent']}</value></Data>
        <Data name="forest_loss"><value>${stats['forest_loss']}</value></Data>
        $tempLine
      </ExtendedData>
      <Point>
        <coordinates>${region.longitude},${region.latitude},0</coordinates>
      </Point>
    </Placemark>

    ${_buildCategoryLayer(region, era, stats)}

  </Document>
</kml>''';
  }

  String _buildCategoryLayer(ClimateRegion region, ClimateEra era, Map<String, String> stats) {
    switch (region.category) {
      case 'glacier':
        return _glacierPolygon(region, era);
      case 'sealevel':
        return _seaLevelPolygon(region, era);
      case 'forest':
        return _forestPolygon(region, era);
      default:
        return '';
    }
  }

  String _glacierPolygon(ClimateRegion region, ClimateEra era) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => 'aa',
      ClimateEra.present2026       => '77',
      ClimateEra.projected2100     => '33',
    };
    final lat = region.latitude;
    final lon = region.longitude;
    final d = 3.0;
    return '''
    <Placemark>
      <name>Glacier extent — ${era.label}</name>
      <Style>
        <PolyStyle>
          <color>${opacity}aaddff</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>ff88ccff</color>
          <width>1.5</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              ${lon - d},${lat - d},0
              ${lon + d},${lat - d},0
              ${lon + d},${lat + d},0
              ${lon - d},${lat + d},0
              ${lon - d},${lat - d},0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  String _seaLevelPolygon(ClimateRegion region, ClimateEra era) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => '33',
      ClimateEra.present2026       => '66',
      ClimateEra.projected2100     => 'aa',
    };
    final lat = region.latitude;
    final lon = region.longitude;
    const d = 1.5;
    return '''
    <Placemark>
      <name>Sea level inundation — ${era.label}</name>
      <Style>
        <PolyStyle>
          <color>${opacity}3388ff</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>ff3388ff</color>
          <width>2</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              ${lon - d},${lat - d},0
              ${lon + d},${lat - d},0
              ${lon + d},${lat + d},0
              ${lon - d},${lat + d},0
              ${lon - d},${lat - d},0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  String _forestPolygon(ClimateRegion region, ClimateEra era) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => 'aa',
      ClimateEra.present2026       => '77',
      ClimateEra.projected2100     => '44',
    };
    final lat = region.latitude;
    final lon = region.longitude;
    const d = 4.0;
    return '''
    <Placemark>
      <name>Forest cover — ${era.label}</name>
      <Style>
        <PolyStyle>
          <color>${opacity}22aa55</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>ff44bb66</color>
          <width>1.5</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              ${lon - d},${lat - d},0
              ${lon + d},${lat - d},0
              ${lon + d},${lat + d},0
              ${lon - d},${lat + d},0
              ${lon - d},${lat - d},0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  String _buildNetworkLinkKml(String href) =>
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<kml xmlns="http://www.opengis.net/kml/2.2">'
      '<Document>'
      '<name>Climate Storyteller</name>'
      '<NetworkLink>'
      '<name>Climate Storyteller Data</name>'
      '<Link>'
      '<href>$href</href>'
      '<refreshMode>onInterval</refreshMode>'
      '<refreshInterval>2</refreshInterval>'
      '</Link>'
      '</NetworkLink>'
      '</Document>'
      '</kml>';

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        await execute('echo keepalive');
      } catch (_) {
        await disconnect();
      }
    });
  }

  void _update(LGRigState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  void dispose() {
    _keepaliveTimer?.cancel();
    _stateCtrl.close();
  }
}
