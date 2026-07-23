import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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

  // Default camera tilt used for LookAt blocks. 0 = straight-down (nadir),
  // which makes vertical 3D faces (box walls, pyramid faces, dome faces,
  // column sides) render edge-on and effectively invisible. A tilt in the
  // 50-65 degree range gives the camera an oblique angle so extruded/3D
  // KML geometry is actually visible on the rig screens.
  static const double _default3DTilt = 60.0;
  static const double _default3DHeading = 30.0;

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
    int? webPort,
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

      // Verify kml folder exists and is writable, create if not
      await execute('mkdir -p $_kmlDir');

      // Do the same for slave screens
      for (int i = 2; i <= screenCount; i++) {
        try {
          await execute(
            'sshpass -p lg ssh -o StrictHostKeyChecking=no '
            'lg@lg$i "mkdir -p $_kmlDir" 2>&1'
          );
        } catch (_) {}
      }

      // Try to auto-detect web server port if not manually specified
      int detectedPort = webPort ?? 81;
      if (webPort == null || webPort == 0) {
        detectedPort = 81; // Default fallback
        try {
          final check80 = await execute(
            'curl -s -o /dev/null -w "%{http_code}" http://localhost:80/ || '
            'wget -q --spider http://localhost:80/ && echo "200"'
          );
          if (check80.contains('200') || check80.contains('301') || check80.contains('302') || check80.contains('403') || check80.contains('404')) {
            detectedPort = 80;
          } else {
            final check81 = await execute(
              'curl -s -o /dev/null -w "%{http_code}" http://localhost:81/ || '
              'wget -q --spider http://localhost:81/ && echo "200"'
            );
            if (check81.contains('200') || check81.contains('301') || check81.contains('302') || check81.contains('403') || check81.contains('404')) {
              detectedPort = 81;
            }
          }
        } catch (_) {
          // Fallback to ss/netstat checks if curl/wget is not available
          try {
            final out = await execute(
              '/usr/sbin/ss -tln 2>/dev/null | grep -E ":80|:81" || '
              '/sbin/ss -tln 2>/dev/null | grep -E ":80|:81" || '
              'ss -tln 2>/dev/null | grep -E ":80|:81" || '
              '/usr/sbin/netstat -tln 2>/dev/null | grep -E ":80|:81" || '
              '/sbin/netstat -tln 2>/dev/null | grep -E ":80|:81" || '
              'netstat -tln 2>/dev/null | grep -E ":80|:81"'
            );
            if (out.contains(':80') || out.contains(' 80 ')) {
              detectedPort = 80;
            } else if (out.contains(':81') || out.contains(' 81 ')) {
              detectedPort = 81;
            }
          } catch (_) {}
        }
      }

      final sw = Stopwatch()..start();
      await execute('echo ping');
      final latency = sw.elapsedMilliseconds;

      await SecureStorageService.instance.saveLgCredentials(
        ip: ipAddress,
        port: port,
        username: username,
        password: password,
        screen: screenCount.toString(),
        webPort: detectedPort.toString(),
      );

      _update(_state.copyWith(
        status: LGConnectionStatus.connected,
        ipAddress: ipAddress,
        port: port,
        screenCount: screenCount,
        webPort: detectedPort,
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
    return utf8.decode(result, allowMalformed: true);
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

    final host = _state.ipAddress ?? 'localhost';
    final kmlUrl = 'http://$host:${_state.webPort}/kml/$kmlFilename';
    final netLinkKml = _buildNetworkLinkKml(kmlUrl);
    final b64NetLink = base64Encode(utf8.encode(netLinkKml));

    // 1. Write the NetworkLink KML files to the master node for all screens
    for (int i = 1; i <= _state.screenCount; i++) {
      await execute("echo '$b64NetLink' | base64 -d > $_kmlDir/kml_$i.kml");
      await execute("echo '$b64NetLink' | base64 -d > $_kmlDir/slave_$i.kml");
    }
    await execute("echo '$b64NetLink' | base64 -d > $_kmlDir/master.kml");

    // 2. Write the NetworkLink KML files to the slave nodes (as backup)
    for (int i = 2; i <= _state.screenCount; i++) {
      try {
        final cmd =
            'sshpass -p lg ssh -o StrictHostKeyChecking=no '
            'lg@lg$i "echo \'$b64NetLink\' | base64 -d > $_kmlDir/kml_$i.kml && echo \'$b64NetLink\' | base64 -d > $_kmlDir/slave_$i.kml" 2>&1';
        await execute(cmd);
      } catch (_) {}
    }

    // 3. Write the sync files that Google Earth's MyPlaces.kml NetworkLink
    // actually polls (every 2s, per setupNetworkLink()). These MUST contain
    // valid KML XML, not a plain URL string, or GE will silently fail to
    // parse them and nothing will render on screen.
    if (kmlContent != null && kmlContent.isNotEmpty) {
      final b64Content = base64Encode(utf8.encode(kmlContent));
      await execute("echo '$b64Content' | base64 -d > $_kmlSyncFile");
      for (int i = 1; i <= _state.screenCount; i++) {
        await execute("echo '$b64Content' | base64 -d > /var/www/html/kmls_$i.txt");
      }
    } else {
      await execute("echo '$b64NetLink' | base64 -d > $_kmlSyncFile");
      for (int i = 1; i <= _state.screenCount; i++) {
        await execute("echo '$b64NetLink' | base64 -d > /var/www/html/kmls_$i.txt");
      }
    }

    await execute("echo '$kmlUrl' > $_queryFile");

    _update(_state.copyWith(currentKml: kmlFilename));
  }

  Future<void> flyTo({
    required double latitude,
    required double longitude,
    required double altitude,
    double tilt = _default3DTilt,
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

    // Clear all kmls_i.txt files on master
    for (int i = 1; i <= _state.screenCount; i++) {
      await execute("echo '' > /var/www/html/kmls_$i.txt 2>&1");
    }

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

  Future<void> setupNetworkLink() async {
    if (_client == null) throw Exception('Not connected to LG Rig');

    final ip = _state.ipAddress ?? 'localhost';
    final port = _state.webPort;

    // 1. Force kill Google Earth on Master and Slaves first to prevent setting overwrite on exit
    try {
      await execute('killall -9 googleearth-bin googleearth 2>/dev/null || pkill -9 googleearth 2>/dev/null');
    } catch (_) {}

    for (int i = 2; i <= _state.screenCount; i++) {
      try {
        final killCmd =
            'sshpass -p lg ssh -o StrictHostKeyChecking=no lg@lg$i '
            '"killall -9 googleearth-bin googleearth 2>/dev/null || pkill -9 googleearth 2>/dev/null"';
        await execute(killCmd);
      } catch (_) {}
    }

    // Wait for Google Earth processes to exit
    await Future.delayed(const Duration(milliseconds: 800));

    // 2. Set up Master Node (Screen 1) pointing to http://localhost:$port/kmls.txt
    final masterLinkKml = _buildSyncPlacesKml('http://localhost:$port/kmls.txt');
    final masterB64 = base64Encode(utf8.encode(masterLinkKml));

    await execute('mkdir -p /home/lg/.googleearth /home/lg/.local/share/Google/GoogleEarth');
    await execute(
      "echo '$masterB64' | base64 -d > /home/lg/.googleearth/MyPlaces.kml && "
      "echo '$masterB64' | base64 -d > /home/lg/.googleearth/myplaces.kml && "
      "echo '$masterB64' | base64 -d > /home/lg/.local/share/Google/GoogleEarth/MyPlaces.kml && "
      "echo '$masterB64' | base64 -d > /home/lg/.local/share/Google/GoogleEarth/myplaces.kml"
    );

    // 3. Set up Slave Nodes (Screen 2 to screenCount) pointing to http://$ip:$port/kmls.txt
    for (int i = 2; i <= _state.screenCount; i++) {
      try {
        final slaveLinkKml = _buildSyncPlacesKml('http://$ip:$port/kmls.txt');
        final slaveB64 = base64Encode(utf8.encode(slaveLinkKml));

        // Create directories and write both uppercase and lowercase KML files on the slave node
        final cmd =
            'sshpass -p lg ssh -o StrictHostKeyChecking=no lg@lg$i '
            '"mkdir -p /home/lg/.googleearth /home/lg/.local/share/Google/GoogleEarth && '
            'echo \'$slaveB64\' | base64 -d > /home/lg/.googleearth/MyPlaces.kml && '
            'echo \'$slaveB64\' | base64 -d > /home/lg/.googleearth/myplaces.kml && '
            'echo \'$slaveB64\' | base64 -d > /home/lg/.local/share/Google/GoogleEarth/MyPlaces.kml && '
            'echo \'$slaveB64\' | base64 -d > /home/lg/.local/share/Google/GoogleEarth/myplaces.kml"';
        await execute(cmd);
      } catch (_) {}
    }

    // Wait for the files to write completely
    await Future.delayed(const Duration(milliseconds: 300));

    // 4. Relaunch Google Earth on all screens to apply changes
    await relaunchGoogleEarth();
    for (int i = 2; i <= _state.screenCount; i++) {
      try {
        await execute(
          'sshpass -p lg ssh -o StrictHostKeyChecking=no lg@lg$i '
          '"/home/lg/bin/lg-relaunch 2>&1 || DISPLAY=:0 /home/lg/earth/googleearth &"'
        );
      } catch (_) {}
    }
  }

  String _buildSyncPlacesKml(String url) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
<Document>
	<name>My Places</name>
	<open>1</open>
	<Folder>
		<name>Climate Storyteller Link</name>
		<visibility>1</visibility>
		<open>1</open>
		<NetworkLink>
			<name>Climate Storyteller Sync</name>
			<visibility>1</visibility>
			<open>1</open>
			<Link>
				<href>$url</href>
				<refreshMode>onInterval</refreshMode>
				<refreshInterval>2</refreshInterval>
			</Link>
		</NetworkLink>
	</Folder>
</Document>
</kml>''';
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
      ClimateEra.projected2100     => '2026-01-01',
    };

    return '$_gibsBase?'
        'SERVICE=WMS&REQUEST=GetMap&VERSION=1.1.1'
        '&LAYERS=$layer'
        '&SRS=EPSG:4326'
        '&FORMAT=image/png'
        '&WIDTH=1024&HEIGHT=512'
        '&BBOX=-180,-90,180,90'
        '&TRANSPARENT=TRUE'
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
    <visibility>1</visibility>
    <description><![CDATA[$description]]></description>

    <!-- Camera position (tilted so extruded/3D geometry below is actually
         visible instead of being viewed edge-on from straight overhead) -->
    <LookAt>
      <longitude>${region.longitude}</longitude>
      <latitude>${region.latitude}</latitude>
      <altitude>0</altitude>
      <heading>$_default3DHeading</heading>
      <tilt>$_default3DTilt</tilt>
      <range>${region.altitude}</range>
      <altitudeMode>relativeToGround</altitudeMode>
    </LookAt>

    <!-- NASA GIBS overlay -->
    <GroundOverlay>
      <name>NASA GIBS — ${era.label}</name>
      <visibility>1</visibility>
      <color>99ffffff</color>
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
      <visibility>1</visibility>
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
    final buffer = StringBuffer();

    // 2D polygon layers
    switch (region.category) {
      case 'glacier':
        buffer.writeln(_glacierPolygon(region, era));
        break;
      case 'sealevel':
        buffer.writeln(_seaLevelPolygon(region, era));
        break;
      case 'forest':
        buffer.writeln(_forestPolygon(region, era));
        break;
      case 'heat':
        buffer.writeln(_heatPolygon(region, era));
        break;
    }

    // 3D extruded grid layers (visible on screen)
    buffer.writeln(_build3DVisuals(region, era));

    return buffer.toString();
  }

  String _build3DVisuals(ClimateRegion region, ClimateEra era) {
    final localData = getRegionData(region.id);

    switch (region.category) {
      case 'glacier':
        final iceExtentKm2 = localData?.iceExtentKm2[int.parse(era.label)] ?? 10000.0;
        final baseExtent = localData?.iceExtentKm2[1900] ?? 10000.0;
        final factor = (iceExtentKm2 / baseExtent).clamp(0.0, 1.0);
        final height = 50000.0 + factor * 450000.0;
        final colors = LG3DVisuals.getGlacierColors(factor);

        return LG3DVisuals.build3DBox(
          centerLat: region.latitude,
          centerLon: region.longitude,
          spanDeg: 5.0,
          heightMeters: height,
          faceColorsAbgr: colors,
          name: 'Glacier Thickness (3D Box)',
          description: '3D Glacier thickness representing volume in year ${era.label}',
        );

      case 'sealevel':
        final seaLevelMm = localData?.seaLevelMm[int.parse(era.label)] ?? 0.0;
        final factor = (seaLevelMm / 1000.0).clamp(0.0, 1.0);
        final height = 20000.0 + factor * 380000.0;
        final colors = LG3DVisuals.getSeaLevelColors(factor);

        return LG3DVisuals.build3DOctagonalColumn(
          centerLat: region.latitude,
          centerLon: region.longitude,
          radiusDeg: 1.75, // radius is half of span 3.5
          heightMeters: height,
          sideColorsAbgr: colors,
          name: 'Sea Level Rise (3D Column)',
          description: '3D Sea level inundation representing height in year ${era.label}',
        );

      case 'forest':
        final forestCoverPct = localData?.forestCoverPct[int.parse(era.label)] ?? 100.0;
        final factor = (forestCoverPct / 100.0).clamp(0.0, 1.0);
        final height = 50000.0 + factor * 400000.0;
        final colors = LG3DVisuals.getForestColors(factor);

        return LG3DVisuals.build3DPyramid(
          centerLat: region.latitude,
          centerLon: region.longitude,
          spanDeg: 6.0,
          heightMeters: height,
          face1ColorAbgr: colors[0],
          face2ColorAbgr: colors[1],
          face3ColorAbgr: colors[2],
          face4ColorAbgr: colors[3],
          name: 'Forest Canopy Density (3D Pyramid)',
          description: '3D Forest canopy density in year ${era.label}',
        );

      case 'heat':
        final heatFactor = switch (era) {
          ClimateEra.preindustrial1900 => 0.15,
          ClimateEra.present2026       => 0.55,
          ClimateEra.projected2100     => 1.0,
        };
        final height = 40000.0 + heatFactor * 360000.0;
        final colors = LG3DVisuals.getHeatColors(heatFactor);

        return LG3DVisuals.build3DHeatDome(
          centerLat: region.latitude,
          centerLon: region.longitude,
          radiusDeg: 2.75, // radius is half of span 5.5
          heightMeters: height,
          faceColorsAbgr: colors,
          name: 'Extreme Heat Dome (3D)',
          description: '3D Temperature anomaly representing heat intensity in year ${era.label}',
        );

      default:
        return '';
    }
  }

  String _heatPolygon(ClimateRegion region, ClimateEra era) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => '55', // Yellowish-orange, light
      ClimateEra.present2026       => '99', // Orange, medium
      ClimateEra.projected2100     => 'dd', // Red, heavy
    };
    final color = switch (era) {
      ClimateEra.preindustrial1900 => '00aaff', // KML color: aabbggrr -> Alpha + Blue=00, Green=aa, Red=ff -> Orange/Yellow
      ClimateEra.present2026       => '0055ff', // KML color: aabbggrr -> Alpha + Blue=00, Green=55, Red=ff -> Bright Orange-Red
      ClimateEra.projected2100     => '0000ff', // KML color: aabbggrr -> Alpha + Blue=00, Green=00, Red=ff -> Solid Red
    };
    final lat = region.latitude;
    final lon = region.longitude;
    const d = 3.5;
    return '''
    <Placemark>
      <name>Extreme Heat Area — ${era.label}</name>
      <visibility>1</visibility>
      <Style>
        <PolyStyle>
          <color>$opacity$color</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>ff0000ff</color>
          <width>2.0</width>
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

  String _glacierPolygon(ClimateRegion region, ClimateEra era) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => 'aa',
      ClimateEra.present2026       => '77',
      ClimateEra.projected2100     => '33',
    };
    final lat = region.latitude;
    final lon = region.longitude;
    const d = 3.0;
    return '''
    <Placemark>
      <name>Glacier extent — ${era.label}</name>
      <visibility>1</visibility>
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
      <visibility>1</visibility>
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
      <visibility>1</visibility>
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
      '<visibility>1</visibility>'
      '<NetworkLink>'
      '<name>Climate Storyteller Data</name>'
      '<visibility>1</visibility>'
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

  Future<String> runDiagnostics() async {
    if (_client == null) return 'Error: Not connected to LG Rig. Please connect first.';

    final sb = StringBuffer();
    sb.writeln('=== Liquid Galaxy Diagnostic Report ===');
    sb.writeln('Timestamp: ${DateTime.now()}');
    sb.writeln('Rig IP: ${_state.ipAddress}:${_state.port}');
    sb.writeln('Screen Count: ${_state.screenCount}');
    sb.writeln('');

    // 1. Check disk space and basic system info
    try {
      final uname = await execute('uname -a');
      sb.writeln('🐧 OS Info: ${uname.trim()}');
    } catch (e) {
      sb.writeln('🐧 OS Info Check Failed: $e');
    }

    // 2. Check Web Server (Apache/Nginx) status
    sb.writeln('\n--- Web Server Check ---');
    try {
      final ports = await execute('sudo netstat -tlnp 2>/dev/null | grep -E "apache|nginx|lighttpd" || ss -tlnp 2>/dev/null | grep -E "80|81" || netstat -tln 2>/dev/null | grep -E "80|81"');
      sb.writeln('Listening Web Ports:\n${ports.trim()}');
    } catch (e) {
      sb.writeln('Failed to check listening ports: $e');
    }

    try {
      final curl80 = await execute('curl -s -I http://localhost:80/ | head -n 1');
      sb.writeln('Local Port 80 Response: ${curl80.trim()}');
    } catch (e) {
      sb.writeln('Local Port 80 Check Failed: $e');
    }

    try {
      final curl81 = await execute('curl -s -I http://localhost:81/ | head -n 1');
      sb.writeln('Local Port 81 Response: ${curl81.trim()}');
    } catch (e) {
      sb.writeln('Local Port 81 Check Failed: $e');
    }

    // 3. Check KML Directory existence and permissions
    sb.writeln('\n--- KML Directory & Permissions ---');
    try {
      final lsKml = await execute('ls -la $_kmlDir');
      sb.writeln('Directory $_kmlDir contents:\n$lsKml');
    } catch (e) {
      sb.writeln('Failed to list $_kmlDir: $e');
    }

    try {
      final lsHtml = await execute('ls -la /var/www/html');
      sb.writeln('Directory /var/www/html contents:\n$lsHtml');
    } catch (e) {
      sb.writeln('Failed to list /var/www/html: $e');
    }

    // 4. Check Apache Access Logs
    sb.writeln('\n--- Apache Access Logs (Last 15 lines) ---');
    try {
      final logs = await execute('sudo tail -n 15 /var/log/apache2/access.log || sudo tail -n 15 /var/log/nginx/access.log || tail -n 15 /var/log/httpd/access_log');
      sb.writeln(logs.trim().isEmpty ? 'No logs found or empty.' : logs.trim());
    } catch (e) {
      sb.writeln('Failed to read access logs: $e');
    }

    sb.writeln('\n--- Google Earth Process Check ---');
    try {
      final extra = await execute(
        'ps aux | grep -i earth; echo ---; who; echo ---; echo DISPLAY=\$DISPLAY'
      );
      sb.writeln(extra.trim().isEmpty ? 'No processes found.' : extra.trim());
      // ignore: avoid_print
      print(extra);
    } catch (e) {
      sb.writeln('Failed to execute process check: $e');
    }

    // 5. Check Google Earth places.kml for NetworkLink
    sb.writeln('\n--- Google Earth Configuration Check ---');
    try {
      final gePlaces = await execute('cat /home/lg/.googleearth/MyPlaces.kml 2>/dev/null || cat /home/lg/.local/share/Google/GoogleEarth/myplaces.kml 2>/dev/null');
      if (gePlaces.contains('kmls.txt') || gePlaces.contains('kml_1.kml') || gePlaces.contains('master.kml')) {
        sb.writeln('✅ Found active NetworkLink for app synchronization in MyPlaces.kml!');
      } else {
        sb.writeln('⚠️ WARNING: No NetworkLink pointing to kmls.txt, kml_1.kml or master.kml found in MyPlaces.kml!');
        sb.writeln('Ensure Google Earth has a NetworkLink configured to http://localhost:81/kmls.txt (or kml_1.kml).');
      }
    } catch (e) {
      sb.writeln('Could not read MyPlaces.kml: $e');
    }

    return sb.toString();
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







  class LG3DVisuals {
  LG3DVisuals._();

  static String wrapDocument({
    required String name,
    required String body,
    String description = '',
  }) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>$name</name>
    <visibility>1</visibility>
    <open>1</open>
    ${description.isNotEmpty ? '<description><![CDATA[$description]]></description>' : ''}
    $body
  </Document>
</kml>''';
  }

  static String build3DBox({
    required double centerLat,
    required double centerLon,
    required double spanDeg,
    required double heightMeters,
    required List<String> faceColorsAbgr, // 5 colors: South, East, North, West, Top
    String name = '3D Box',
    String description = '',
  }) {
    final half = spanDeg / 2;
    // Ground Coordinates (altitude = 0)
    final swG = '${centerLon - half},${centerLat - half},0';
    final seG = '${centerLon + half},${centerLat - half},0';
    final neG = '${centerLon + half},${centerLat + half},0';
    final nwG = '${centerLon - half},${centerLat + half},0';

    // Top Coordinates (altitude = heightMeters)
    final h = heightMeters.toStringAsFixed(1);
    final swT = '${centerLon - half},${centerLat - half},$h';
    final seT = '${centerLon + half},${centerLat - half},$h';
    final neT = '${centerLon + half},${centerLat + half},$h';
    final nwT = '${centerLon - half},${centerLat + half},$h';

    return '''
    <Folder>
      <name>$name</name>
      <visibility>1</visibility>
      <open>0</open>
      ${description.isNotEmpty ? '<description><![CDATA[$description]]></description>' : ''}

      <!-- South Face -->
      <Placemark>
        <name>South Face</name>
        <Style><PolyStyle><color>${faceColorsAbgr[0]}</color><outline>0</outline></PolyStyle></Style>
        <Polygon><tessellate>0</tessellate><altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $swG
            $seG
            $seT
            $swT
            $swG
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>

      <!-- East Face -->
      <Placemark>
        <name>East Face</name>
        <Style><PolyStyle><color>${faceColorsAbgr[1]}</color><outline>0</outline></PolyStyle></Style>
        <Polygon><tessellate>0</tessellate><altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $seG
            $neG
            $neT
            $seT
            $seG
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>

      <!-- North Face -->
      <Placemark>
        <name>North Face</name>
        <Style><PolyStyle><color>${faceColorsAbgr[2]}</color><outline>0</outline></PolyStyle></Style>
        <Polygon><tessellate>0</tessellate><altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $neG
            $nwG
            $nwT
            $neT
            $neG
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>

      <!-- West Face -->
      <Placemark>
        <name>West Face</name>
        <Style><PolyStyle><color>${faceColorsAbgr[3]}</color><outline>0</outline></PolyStyle></Style>
        <Polygon><tessellate>0</tessellate><altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $nwG
            $swG
            $swT
            $nwT
            $nwG
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>

      <!-- Top Face -->
      <Placemark>
        <name>Top Face</name>
        <Style><PolyStyle><color>${faceColorsAbgr[4]}</color><outline>0</outline></PolyStyle></Style>
        <Polygon><tessellate>0</tessellate><altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $swT
            $seT
            $neT
            $nwT
            $swT
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>
    </Folder>
    ''';
  }

  static String build3DOctagonalColumn({
    required double centerLat,
    required double centerLon,
    required double radiusDeg,
    required double heightMeters,
    required List<String> sideColorsAbgr, // 9 colors: 8 sides + 1 top
    String name = '3D Octagonal Column',
    String description = '',
  }) {
    final pointsG = <String>[];
    final pointsT = <String>[];
    final h = heightMeters.toStringAsFixed(1);

    for (int i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final lat = centerLat + radiusDeg * math.sin(angle);
      final lon = centerLon + radiusDeg * math.cos(angle);
      pointsG.add('${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)},0');
      pointsT.add('${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)},$h');
    }

    final sb = StringBuffer();
    sb.writeln('<Folder>');
    sb.writeln('  <name>$name</name>');
    sb.writeln('  <visibility>1</visibility>');
    sb.writeln('  <open>0</open>');
    if (description.isNotEmpty) {
      sb.writeln('  <description><![CDATA[$description]]></description>');
    }

    for (int i = 0; i < 8; i++) {
      final next = (i + 1) % 8;
      final color = sideColorsAbgr[i % sideColorsAbgr.length];
      sb.writeln('''
      <Placemark>
        <name>Side ${i + 1}</name>
        <Style><PolyStyle><color>$color</color><outline>0</outline></PolyStyle></Style>
        <Polygon><tessellate>0</tessellate><altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            ${pointsG[i]}
            ${pointsG[next]}
            ${pointsT[next]}
            ${pointsT[i]}
            ${pointsG[i]}
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>
      ''');
    }

    final topColor = sideColorsAbgr[8 % sideColorsAbgr.length];
    final topCoordinates = '${pointsT.join('\n')}\n${pointsT[0]}';
    sb.writeln('''
    <Placemark>
      <name>Top Face</name>
      <Style><PolyStyle><color>$topColor</color><outline>0</outline></PolyStyle></Style>
      <Polygon><tessellate>0</tessellate><altitudeMode>relativeToGround</altitudeMode>
        <outerBoundaryIs><LinearRing><coordinates>
          $topCoordinates
        </coordinates></LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>
    ''');

    sb.writeln('</Folder>');
    return sb.toString();
  }

  static String build3DHeatDome({
    required double centerLat,
    required double centerLon,
    required double radiusDeg,
    required double heightMeters,
    required List<String> faceColorsAbgr, // 8 colors
    String name = '3D Heat Dome',
    String description = '',
  }) {
    final pointsG = <String>[];
    final h = heightMeters.toStringAsFixed(1);
    final peak = '$centerLon,$centerLat,$h';

    for (int i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final lat = centerLat + radiusDeg * math.sin(angle);
      final lon = centerLon + radiusDeg * math.cos(angle);
      pointsG.add('${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)},0');
    }

    final sb = StringBuffer();
    sb.writeln('<Folder>');
    sb.writeln('  <name>$name</name>');
    sb.writeln('  <visibility>1</visibility>');
    sb.writeln('  <open>0</open>');
    if (description.isNotEmpty) {
      sb.writeln('  <description><![CDATA[$description]]></description>');
    }

    for (int i = 0; i < 8; i++) {
      final next = (i + 1) % 8;
      final color = faceColorsAbgr[i % faceColorsAbgr.length];
      sb.writeln('''
      <Placemark>
        <name>Dome Face ${i + 1}</name>
        <Style><PolyStyle><color>$color</color><outline>0</outline></PolyStyle></Style>
        <Polygon><tessellate>0</tessellate><altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            ${pointsG[i]}
            ${pointsG[next]}
            $peak
            ${pointsG[i]}
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>
      ''');
    }

    sb.writeln('</Folder>');
    return sb.toString();
  }

  static String build3DPyramid({
    required double centerLat,
    required double centerLon,
    required double spanDeg,
    required double heightMeters,
    required String face1ColorAbgr,
    required String face2ColorAbgr,
    required String face3ColorAbgr,
    required String face4ColorAbgr,
    String name = '3D Pyramid',
    String description = '',
  }) {
    final half = spanDeg / 2;

    // Base Corners on Ground (altitude = 0)
    final sw = '${centerLon - half},${centerLat - half},0';
    final se = '${centerLon + half},${centerLat - half},0';
    final ne = '${centerLon + half},${centerLat + half},0';
    final nw = '${centerLon - half},${centerLat + half},0';

    // Apex / Peak at the center with altitude heightMeters
    final h = heightMeters.toStringAsFixed(1);
    final peak = '$centerLon,$centerLat,$h';

    return '''
    <Folder>
      <name>$name</name>
      <visibility>1</visibility>
      <open>0</open>
      ${description.isNotEmpty ? '<description><![CDATA[$description]]></description>' : ''}

      <!-- South Face -->
      <Placemark>
        <name>South Face</name>
        <Style>
          <PolyStyle>
            <color>$face1ColorAbgr</color>
            <outline>0</outline>
          </PolyStyle>
          <LineStyle>
            <color>00000000</color>
            <width>0</width>
          </LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $sw
            $se
            $peak
            $sw
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>

      <!-- East Face -->
      <Placemark>
        <name>East Face</name>
        <Style>
          <PolyStyle>
            <color>$face2ColorAbgr</color>
            <outline>0</outline>
          </PolyStyle>
          <LineStyle>
            <color>00000000</color>
            <width>0</width>
          </LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $se
            $ne
            $peak
            $se
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>

      <!-- North Face -->
      <Placemark>
        <name>North Face</name>
        <Style>
          <PolyStyle>
            <color>$face3ColorAbgr</color>
            <outline>0</outline>
          </PolyStyle>
          <LineStyle>
            <color>00000000</color>
            <width>0</width>
          </LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $ne
            $nw
            $peak
            $ne
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>

      <!-- West Face -->
      <Placemark>
        <name>West Face</name>
        <Style>
          <PolyStyle>
            <color>$face4ColorAbgr</color>
            <outline>0</outline>
          </PolyStyle>
          <LineStyle>
            <color>00000000</color>
            <width>0</width>
          </LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $nw
            $sw
            $peak
            $nw
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>
    </Folder>
    ''';
  }

  static List<String> getGlacierColors(double thickness) {
    final r = (200 - thickness * 100).round();
    final g = (235 - thickness * 35).round();
    const b = 255;
    final a = (120 + thickness * 80).round();

    final f1 = _abgr(r, g, b, a);
    final f2 = _abgr((r * 0.85).round(), (g * 0.85).round(), (b * 0.85).round(), a);
    final f3 = _abgr((r * 0.95).round(), (g * 0.95).round(), (b * 0.95).round(), a);
    final f4 = _abgr((r * 0.7).round(), (g * 0.7).round(), (b * 0.7).round(), a);
    final f5 = _abgr((r * 1.05).round(), (g * 1.05).round(), b, a);
    return [f1, f2, f3, f4, f5];
  }

  static List<String> getSeaLevelColors(double level) {
    final r = (30 - level * 10).round();
    final g = (100 + level * 80).round();
    final b = (220 + level * 35).round();
    final a = (120 + level * 80).round();

    final colors = <String>[];
    for (int i = 0; i < 8; i++) {
      final shade = 0.65 + 0.35 * math.sin(i * math.pi / 4).abs();
      colors.add(_abgr((r * shade).round(), (g * shade).round(), (b * shade).round(), a));
    }
    colors.add(_abgr((r * 1.15).round(), (g * 1.15).round(), b, a));
    return colors;
  }

  static List<String> getForestColors(double factor) {
    final r = (204 - factor * 170).round();
    final g = (170 + factor * 30).round();
    final b = (factor * 68).round();
    final a = (120 + factor * 80).round();

    final f1 = _abgr(r, g, b, a);
    final f2 = _abgr((r * 0.85).round(), (g * 0.85).round(), (b * 0.85).round(), a);
    final f3 = _abgr((r * 0.95).round(), (g * 0.95).round(), (b * 0.95).round(), a);
    final f4 = _abgr((r * 0.7).round(), (g * 0.7).round(), (b * 0.7).round(), a);
    return [f1, f2, f3, f4];
  }

  static List<String> getHeatColors(double factor) {
    const r = 255;
    final g = (220 - factor * 220).round();
    const b = 0;
    final a = (120 + factor * 80).round();

    final colors = <String>[];
    for (int i = 0; i < 8; i++) {
      final shade = 0.65 + 0.35 * math.sin(i * math.pi / 4).abs();
      colors.add(_abgr((r * shade).round(), (g * shade).round(), (b * shade).round(), a));
    }
    return colors;
  }

  static String _abgr(int r, int g, int b, int a) {
    String hx(int v) => v.clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '${hx(a)}${hx(b)}${hx(g)}${hx(r)}';
  }
}