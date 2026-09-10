import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:climate_storyteller/features/explore/climate_region.dart';
import 'package:climate_storyteller/features/explore/climate_era.dart';
import 'package:climate_storyteller/features/climate_data/ipcc_data.dart';
import 'package:climate_storyteller/features/lg_connection/lg_rig_state.dart';
import 'package:climate_storyteller/features/lg_connection/lg_overlays.dart';
import 'package:climate_storyteller/core/storage/secure_storage_service.dart';

/// The narrative role a given LG screen plays in a multi-screen layout.
/// Screen 1 is always [branding] and the last screen is always [legend];
/// everything in between is assigned symmetrically around [main] based on
/// how many middle screens there are, matching the 3/5/7-screen layouts:
///
///   3 screens: branding, main, legend
///   5 screens: branding, history, main, analysis, legend
///   7 screens: branding, history, reference, main, analysis, graphs, legend
enum ScreenRole { branding, history, reference, main, analysis, graphs, legend }

/// Returns the 1-based physical screen number of the Left-Most screen
/// on a Liquid Galaxy rig with [screenCount] screens.
/// Standard LG physical layout: Screen 1 is Master (Center).
/// Odd screens > 1 (3, 5, 7) are situated on the left.
/// Even screens (2, 4, 6) are situated on the right.
int getLeftMostScreenNumber(int screenCount) {
  if (screenCount <= 1) return 1;
  if (screenCount == 2) return 2;
  if (screenCount % 2 == 1) return screenCount;
  return screenCount - 1;
}

/// Returns the 1-based physical screen number of the Right-Most screen
/// on a Liquid Galaxy rig with [screenCount] screens.
int getRightMostScreenNumber(int screenCount) {
  if (screenCount <= 1) return 1;
  if (screenCount == 2) return 1;
  if (screenCount % 2 == 1) return screenCount - 1;
  return screenCount;
}

/// Returns the 1-based physical screen number of the Master / Center screen.
int getMasterScreenNumber(int screenCount) => 1;

class LgViewpoint {
  final double latitude;
  final double longitude;
  final double range;

  const LgViewpoint({
    required this.latitude,
    required this.longitude,
    required this.range,
  });
}

class LgService {
  SSHClient? _client;
  SftpClient? _sftp;
  LGRigState _state = const LGRigState();
  final _stateCtrl = StreamController<LGRigState>.broadcast();
  Timer? _keepaliveTimer;

  Stream<LGRigState> get stateStream => _stateCtrl.stream;
  LGRigState get state => _state;

  static const _kmlDir = '/var/www/html/kml';
  static const _queryFile = '/tmp/query.txt';
  static const _kmlSyncFile = '/var/www/html/kmls.txt';

  static const _gibsBase = 'http://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi';
  static const _noaaBase = 'https://www.ncei.noaa.gov/cdo-web/api/v2';
  static const String kLgLogoUrl =
      'https://blogger.googleusercontent.com/img/b/R29vZ2xl/AVvXsEgXmdNgBTXup6bdWew5RzgCmC9pPb7rK487CpiscWB2S8OlhwFHmeeACHIIjx4B5-Iv-t95mNUx0JhB_oATG3-Tq1gs8Uj0-Xb9Njye6rHtKKsnJQJlzZqJxMDnj_2TXX3eA5x6VSgc8aw/s320-rw/LOGO+LIQUID+GALAXY-sq1000-+OKnoline.png';
  static const double _default3DTilt = 35.0;
  static const double _default3DHeading = 15.0;

  static const Map<String, String> _gibsLayers = {
    'glacier':  'MODIS_Terra_NDSI_Snow_Cover',
    'sealevel': 'VIIRS_NOAA20_CorrectedReflectance_TrueColor',
    'forest':   'MODIS_Terra_NDVI_8Day',
    'heat':     'MODIS_Terra_Land_Surface_Temp_Day',
    'aqi':      'MODIS_Terra_Aerosol',
  };

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
      try {
        _sftp = await client.sftp();
      } catch (_) {
        _sftp = null;
      }
      await execute('mkdir -p $_kmlDir');
      for (int i = 2; i <= screenCount; i++) {
        try {
          await execute(
            'sshpass -p $password ssh -o StrictHostKeyChecking=no '
            '$username@lg$i "mkdir -p $_kmlDir" 2>&1'
          );
        } catch (_) {}
      }
      int detectedPort = webPort ?? 81;
      if (webPort == null || webPort == 0) {
        detectedPort = 81;
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
      await execute('sudo chown -R lg:lg $_kmlDir 2>/dev/null; '
          'chmod -R 755 $_kmlDir 2>/dev/null; '
          'chmod 755 /var/www/html 2>/dev/null');
      try {
        await setupNetworkLink();
        await _sendInitialConnectionOverlays();
      } catch (e) {
        print('Auto setupNetworkLink failed: $e');
      }

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

    try {
      if (_client != null && _state.isConnected) {
        await cleanKml();
      }
    } catch (_) {}

    _sftp?.close();
    _sftp = null;
    _client?.close();
    _client = null;
    _uploadedAssets.clear();
    _imageCache.clear();
    _update(const LGRigState());
  }

  Future<String> execute(String command) async {
    final client = _client;
    if (client == null) throw Exception('Not connected to LG rig');
    final result = await client.run(command);
    return utf8.decode(result, allowMalformed: true);
  }

  int? _pendingTimeQueryYear;
  double? _pendingTimeQueryLat;
  double? _pendingTimeQueryLon;
  double? _pendingTimeQueryAlt;
  double? _pendingTimeQueryTilt;
  double? _pendingTimeQueryHeading;
  bool _isSendingTimeQuery = false;

  /// Immediately sends a time command to Liquid Galaxy query.txt
  /// moving Google Earth's time slider clock in real-time (0ms latency).
  Future<void> sendTimeQuery(
    int year, {
    double? latitude,
    double? longitude,
    double? altitude,
    double? tilt,
    double? heading,
  }) async {
    if (_client == null || !_state.isConnected) return;

    _pendingTimeQueryYear = year;
    _pendingTimeQueryLat = latitude;
    _pendingTimeQueryLon = longitude;
    _pendingTimeQueryAlt = altitude;
    _pendingTimeQueryTilt = tilt;
    _pendingTimeQueryHeading = heading;

    if (_isSendingTimeQuery) return;
    _isSendingTimeQuery = true;

    try {
      while (_pendingTimeQueryYear != null) {
        final targetYear = _pendingTimeQueryYear!;
        final lat = _pendingTimeQueryLat ?? _lastFlyToLat ?? 28.6139;
        final lon = _pendingTimeQueryLon ?? _lastFlyToLon ?? 77.2090;
        final alt = _pendingTimeQueryAlt ?? _lastFlyToAlt ?? 500000.0;
        final t = _pendingTimeQueryTilt ?? _default3DTilt;
        final h = _pendingTimeQueryHeading ?? _default3DHeading;
        _pendingTimeQueryYear = null;

        final timeStr = '$targetYear-01-01T00:00:00Z';
        final endStr = '$targetYear-12-31T23:59:59Z';

        final flyStr =
            'flytoview=<LookAt xmlns:gx="http://www.google.com/kml/ext/2.2">'
            '<longitude>$lon</longitude>'
            '<latitude>$lat</latitude>'
            '<altitude>0</altitude>'
            '<heading>$h</heading>'
            '<tilt>$t</tilt>'
            '<range>$alt</range>'
            '<altitudeMode>relativeToGround</altitudeMode>'
            '<gx:TimeSpan><begin>$timeStr</begin><end>$endStr</end></gx:TimeSpan>'
            '<gx:TimeStamp><when>$timeStr</when></gx:TimeStamp>'
            '</LookAt>';

        await execute("echo '$flyStr' > $_queryFile");
      }
    } catch (e) {
      debugPrint('sendTimeQuery error: $e');
    } finally {
      _isSendingTimeQuery = false;
    }
  }
  Timer? _bgViewpointTimer;
  final _viewpointCtrl = StreamController<LgViewpoint>.broadcast();

  /// Stream of camera position coordinates received from LG globe (Bi-directional sync)
  Stream<LgViewpoint> get lgViewpointStream => _viewpointCtrl.stream;

  void startLgViewpointPolling() {
    _bgViewpointTimer?.cancel();
    bool isPollingViewpoint = false;
    _bgViewpointTimer = Timer.periodic(const Duration(milliseconds: 600), (_) async {
      if (_client == null || !_state.isConnected) return;
      if (isPollingViewpoint) return;
      isPollingViewpoint = true;
      try {
        final out = await execute(
          'cat /tmp/views.txt 2>/dev/null || '
          'cat /var/www/cgi-bin/views.txt 2>/dev/null || '
          'cat /tmp/query.txt 2>/dev/null'
        );
        if (out.isNotEmpty) {
          final vp = _parseLgQueryViewpoint(out);
          if (vp != null) {
            _viewpointCtrl.add(vp);
          }
        }
      } catch (_) {} finally {
        isPollingViewpoint = false;
      }
    });
  }

  void stopLgViewpointPolling() {
    _bgViewpointTimer?.cancel();
    _bgViewpointTimer = null;
  }

  LgViewpoint? _parseLgQueryViewpoint(String queryText) {
    try {
      var latMatch = RegExp(r'<latitude>\s*([0-9.-]+)\s*</latitude>').firstMatch(queryText);
      var lonMatch = RegExp(r'<longitude>\s*([0-9.-]+)\s*</longitude>').firstMatch(queryText);
      var rangeMatch = RegExp(r'<range>\s*([0-9.-]+)\s*</range>').firstMatch(queryText);
      latMatch ??= RegExp(r'latitude=([0-9.-]+)').firstMatch(queryText);
      lonMatch ??= RegExp(r'longitude=([0-9.-]+)').firstMatch(queryText);
      rangeMatch ??= RegExp(r'range=([0-9.-]+)').firstMatch(queryText);

      if (latMatch != null && lonMatch != null) {
        final lat = double.parse(latMatch.group(1)!);
        final lon = double.parse(lonMatch.group(1)!);
        final range = rangeMatch != null ? double.parse(rangeMatch.group(1)!) : 100000.0;
        return LgViewpoint(latitude: lat, longitude: lon, range: range);
      }
    } catch (_) {}
    return null;
  }

  /// Real-time KML sender: uploads KML and forces Google Earth to load it immediately via /tmp/query.txt
  Future<void> sendKmlRealtime(String kmlFilename, {String? kmlContent}) async {
    if (_client == null || !_state.isConnected) return;
    try {
      await sendKml(kmlFilename, kmlContent: kmlContent);
    } catch (e) {
      debugPrint('sendKmlRealtime error: $e');
    }
  }

  Timer? _kmlDebounceTimer;

  /// Debounced version of sendKml() for continuous UI controls (e.g. time sliders).
  /// Delays execution until [duration] has passed without any new calls.
  Future<void> sendKmlDebounced(
    String kmlFilename, {
    String? kmlContent,
    Duration duration = const Duration(milliseconds: 100),
  }) async {
    _kmlDebounceTimer?.cancel();
    final completer = Completer<void>();
    _kmlDebounceTimer = Timer(duration, () async {
      try {
        await sendKmlRealtime(kmlFilename, kmlContent: kmlContent);
        if (!completer.isCompleted) completer.complete();
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });
    return completer.future;
  }

  Future<void> sendKml(String kmlFilename, {String? kmlContent}) async {
    if (_client == null) throw Exception('Not connected');
    final category = _extractCategoryFromFilename(kmlFilename);
    await _uploadOverlayAssets(category);

    final host = _state.ipAddress ?? 'localhost';
    final webPort = _state.webPort;
    final masterKmlFilename = 'master_$kmlFilename';
    final slaveKmlFilename = 'slave_$kmlFilename';
    final leftKmlFilename = 'left_$kmlFilename';

    final leftScreenIndex = getLeftMostScreenNumber(_state.screenCount);
    final masterScreenIndex = getMasterScreenNumber(_state.screenCount);
    final rightScreenIndex = getRightMostScreenNumber(_state.screenCount);

    if (kmlContent != null && kmlContent.isNotEmpty) {
      final sceneOnly = _stripScreenOverlays(kmlContent);
      final logoBlock = _extractScreenOverlay(kmlContent, 'lg_logo.png');

      final effectiveLogoBlock = logoBlock.isNotEmpty
          ? logoBlock
          : '''<ScreenOverlay>
      <name>Liquid Galaxy Logo</name>
      <Icon><href>http://$host:$webPort/kml/lg_logo.png</href></Icon>
      <overlayXY x="0" y="1" xunits="fraction" yunits="fraction"/>
      <screenXY x="0.02" y="0.95" xunits="fraction" yunits="fraction"/>
      <rotationXY x="0" y="0" xunits="fraction" yunits="fraction"/>
      <size x="180" y="180" xunits="pixels" yunits="pixels"/>
    </ScreenOverlay>''';
      final masterContent = _stripBalloonVisibility(sceneOnly);
      var leftMostContent = _stripBalloonVisibility(_stripTimeSpans(sceneOnly));
      if (!leftMostContent.contains('<ScreenOverlay>')) {
        leftMostContent = leftMostContent.replaceFirst('</Document>', '$effectiveLogoBlock</Document>');
      }
      final rightMostContent = _ensureBalloonVisibility(_stripTimeSpans(sceneOnly));
      final slaveContent = _stripBalloonVisibility(_stripTimeSpans(sceneOnly));

      final rightKmlFilename = 'right_$kmlFilename';
      final masterNetLinkKml = _buildNetworkLinkKml('http://$host:$webPort/kml/$masterKmlFilename');
      final slaveNetLinkKml = _buildNetworkLinkKml('http://$host:$webPort/kml/$slaveKmlFilename');

      final uploadMap = <String, List<int>>{
        '$_kmlDir/$kmlFilename': utf8.encode(masterContent),
        '$_kmlDir/$masterKmlFilename': utf8.encode(masterContent),
        '$_kmlDir/$slaveKmlFilename': utf8.encode(slaveContent),
        '$_kmlDir/$leftKmlFilename': utf8.encode(leftMostContent),
        '$_kmlDir/$rightKmlFilename': utf8.encode(rightMostContent),
        _kmlSyncFile: utf8.encode(slaveContent),
      };

      for (int i = 1; i <= _state.screenCount; i++) {
        if (i == masterScreenIndex) {
          uploadMap['$_kmlDir/kml_$i.kml'] = utf8.encode(masterNetLinkKml);
          uploadMap['$_kmlDir/master.kml'] = utf8.encode(masterNetLinkKml);
          uploadMap['/var/www/html/kmls_$i.txt'] = utf8.encode(masterContent);
        } else if (i == leftScreenIndex) {
          uploadMap['$_kmlDir/kml_$i.kml'] = utf8.encode(slaveNetLinkKml);
          uploadMap['/var/www/html/kmls_$i.txt'] = utf8.encode(leftMostContent);
        } else if (i == rightScreenIndex) {
          uploadMap['$_kmlDir/kml_$i.kml'] = utf8.encode(slaveNetLinkKml);
          uploadMap['/var/www/html/kmls_$i.txt'] = utf8.encode(rightMostContent);
        } else {
          uploadMap['$_kmlDir/kml_$i.kml'] = utf8.encode(slaveNetLinkKml);
          uploadMap['/var/www/html/kmls_$i.txt'] = utf8.encode(slaveContent);
        }
      }

      for (final entry in uploadMap.entries) {
        await _sftpUpload(entry.key, entry.value);
      }
    } else {
      final masterNetLinkKml = _buildNetworkLinkKml('http://$host:$webPort/kml/$masterKmlFilename');
      final slaveNetLinkKml = _buildNetworkLinkKml('http://$host:$webPort/kml/$slaveKmlFilename');

      await _sftpUpload(_kmlSyncFile, utf8.encode(slaveNetLinkKml));
      for (int i = 1; i <= _state.screenCount; i++) {
        final netLink = (i == masterScreenIndex) ? masterNetLinkKml : slaveNetLinkKml;
        await _sftpUpload('/var/www/html/kmls_$i.txt', utf8.encode(netLink));
      }
    }

    _update(_state.copyWith(currentKml: kmlFilename));
  }

  /// Clears all loaded KML layers, placemarks, and overlays from Liquid Galaxy screens.
  Future<void> cleanKml() async {
    if (_client == null || !_state.isConnected) return;
    try {
      stopOrbit();
      const emptyKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Liquid Galaxy Cleared</name>
  </Document>
</kml>''';
      final emptyBytes = utf8.encode(emptyKml);
      for (int i = 1; i <= _state.screenCount; i++) {
        await _sftpUpload('/var/www/html/kmls_$i.txt', emptyBytes);
      }
      await _sftpUpload(_kmlSyncFile, emptyBytes);
      await execute("echo 'exittour=true' > $_queryFile");
      _update(_state.copyWith(currentKml: null));
    } catch (e) {
      debugPrint('cleanKml error: $e');
    }
  }

  String _stripBalloonVisibility(String kml) {
    return kml.replaceAll(
      RegExp(r'<gx:balloonVisibility>\s*1\s*</gx:balloonVisibility>', dotAll: true),
      '<gx:balloonVisibility>0</gx:balloonVisibility>',
    );
  }

  String _ensureBalloonVisibility(String kml) {
    if (kml.contains('<gx:balloonVisibility>')) {
      return kml.replaceAll(
        RegExp(r'<gx:balloonVisibility>\s*0\s*</gx:balloonVisibility>', dotAll: true),
        '<gx:balloonVisibility>1</gx:balloonVisibility>',
      );
    }
    return kml.replaceAll('<Placemark>', '<Placemark><gx:balloonVisibility>1</gx:balloonVisibility>');
  }

  /// Returns the first `<ScreenOverlay>...</ScreenOverlay>` block in [kml]
  /// whose `<href>` contains [hrefContains] (e.g. 'lg_logo.png' or
  /// 'legend_'), or '' if none is found.
  String _extractScreenOverlay(String kml, String hrefContains) {
    final matches = RegExp(
      r'<ScreenOverlay>.*?</ScreenOverlay>',
      dotAll: true,
    ).allMatches(kml);
    for (final m in matches) {
      final block = m.group(0)!;
      if (block.contains(hrefContains)) return block;
    }
    return '';
  }

  /// Removes every `<ScreenOverlay>...</ScreenOverlay>` block from [kml],
  /// leaving just the underlying scene (Placemarks, Polygons, camera, etc.)
  /// so it can be sent to every screen without duplicating the logo/legend
  /// panels on each one.
  String _stripScreenOverlays(String kml) => kml.replaceAll(
        RegExp(r'<ScreenOverlay>.*?</ScreenOverlay>', dotAll: true),
        '',
      );

  String _stripTimeSpans(String kml) {
    return kml
        .replaceAll(
          RegExp(
            r'<(gx:)?Time(Span|Stamp|Primitive)\b[^>]*>.*?</\s*(gx:)?Time(Span|Stamp|Primitive)\s*>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'<(gx:)?Time(Span|Stamp|Primitive)\b[^>]*/>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'<when>[^<]*</when>|<begin>[^<]*</begin>|<end>[^<]*</end>|<gx:begin>[^<]*</gx:begin>|<gx:end>[^<]*</gx:end>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        );
  }


  Future<void> _sendInitialConnectionOverlays() async {
    if (_client == null || !_state.isConnected) return;
    try {
      final host = _state.ipAddress ?? 'localhost';
      final port = _state.webPort;

      final logoPng = await _fetchOrGenerateLgLogoPng();
      await _sftpUpload('$_kmlDir/lg_logo.png', logoPng);

      final leftScreenIndex = getLeftMostScreenNumber(_state.screenCount);

      final logoKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Liquid Galaxy Initial Branding</name>
    <visibility>1</visibility>
    <ScreenOverlay>
      <name>Liquid Galaxy Logo</name>
      <Icon>
        <href>http://$host:$port/kml/lg_logo.png</href>
      </Icon>
      <overlayXY x="0" y="1" xunits="fraction" yunits="fraction"/>
      <screenXY x="0.02" y="0.95" xunits="fraction" yunits="fraction"/>
      <rotationXY x="0" y="0" xunits="fraction" yunits="fraction"/>
      <size x="180" y="180" xunits="pixels" yunits="pixels"/>
    </ScreenOverlay>
  </Document>
</kml>''';

      const emptyKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Liquid Galaxy Base</name>
    <visibility>1</visibility>
  </Document>
</kml>''';

      for (int i = 1; i <= _state.screenCount; i++) {
        if (i == leftScreenIndex) {
          await _sftpUpload('/var/www/html/kmls_$i.txt', utf8.encode(logoKml));
        } else {
          await _sftpUpload('/var/www/html/kmls_$i.txt', utf8.encode(emptyKml));
        }
      }
      await _sftpUpload(_kmlSyncFile, utf8.encode(emptyKml));
    } catch (e) {
      debugPrint('_sendInitialConnectionOverlays error: $e');
    }
  }

  Uint8List? _cachedLogoBytes;

  Future<Uint8List> _fetchOrGenerateLgLogoPng() async {
    if (_cachedLogoBytes != null) return _cachedLogoBytes!;
    try {
      final res = await http.get(Uri.parse(kLgLogoUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        _cachedLogoBytes = res.bodyBytes;
        return res.bodyBytes;
      }
    } catch (_) {}
    return LGOverlays.createLgLogoPng();
  }

  final Set<String> _uploadedAssets = {};
  final Map<String, Uint8List> _imageCache = {};

  Future<Uint8List> _fetchOrLoadRegionImagePng(ClimateRegion r) async {
    if (_imageCache.containsKey(r.id)) return _imageCache[r.id]!;
    try {
      final file = File(r.assetPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _imageCache[r.id] = bytes;
          return bytes;
        }
      }
    } catch (_) {}
    try {
      final res = await http.get(Uri.parse(r.imageUrl)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        _imageCache[r.id] = res.bodyBytes;
        return res.bodyBytes;
      }
    } catch (_) {}
    final fallback = LGOverlays.createRegionBannerPng(r.id, r.name, r.category);
    _imageCache[r.id] = fallback;
    return fallback;
  }

  Future<void> _uploadOverlayAssets(String category) async {
    if (_client == null || !_state.isConnected) return;
    try {
      if (!_uploadedAssets.contains('logo')) {
        final logoPng = await _fetchOrGenerateLgLogoPng();
        await _sftpUpload('$_kmlDir/lg_logo.png', logoPng);
        _uploadedAssets.add('logo');
      }

      final legendKey = 'legend_$category';
      if (!_uploadedAssets.contains(legendKey)) {
        final legendPng = LGOverlays.createLegendPng(category);
        await _sftpUpload('$_kmlDir/legend_$category.png', legendPng);
        _uploadedAssets.add(legendKey);
      }

      for (final r in kDefaultRegions) {
        final regionKey = 'region_${r.id}';
        if (!_uploadedAssets.contains(regionKey)) {
          final regionPng = await _fetchOrLoadRegionImagePng(r);
          await _sftpUpload('$_kmlDir/region_${r.id}.png', regionPng);
          _uploadedAssets.add(regionKey);
        }
      }
    } catch (_) {}
  }
  Future<void> _sftpUpload(String remotePath, List<int> data) async {
    if (_sftp != null) {
      try {
        final file = await _sftp!.open(
          remotePath,
          mode: SftpFileOpenMode.create |
                SftpFileOpenMode.write |
                SftpFileOpenMode.truncate,
        );
        await file.writeBytes(Uint8List.fromList(data));
        await file.close();
        return;
      } catch (e) {
        debugPrint('SFTP upload fallback for $remotePath: $e');
      }
    }

    final b64 = base64Encode(data);
    const chunkSize = 65000;

    if (b64.length <= chunkSize) {
      await execute("echo '$b64' | base64 -d > $remotePath");
    } else {
      await execute("> $remotePath.b64");
      for (int offset = 0; offset < b64.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, b64.length);
        final chunk = b64.substring(offset, end);
        await execute("echo -n '$chunk' >> $remotePath.b64");
      }
      await execute('base64 -d $remotePath.b64 > $remotePath && rm -f $remotePath.b64');
    }
  }

  String _extractCategoryFromFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.contains('aqi')) return 'aqi';
    if (lower.contains('forest')) return 'forest';
    if (lower.contains('sealevel') || lower.contains('sea_level')) return 'sealevel';
    if (lower.contains('glacier') || lower.contains('ice')) return 'glacier';
    if (lower.contains('heat')) return 'heat';
    return 'aqi';
  }

  double? _lastFlyToLat;
  double? _lastFlyToLon;
  double? _lastFlyToAlt;

  Timer? _orbitTimer;
  double _currentOrbitHeading = 0.0;

  Future<void> startOrbit({
    double? latitude,
    double? longitude,
    double? altitude,
    double tilt = _default3DTilt,
    double speed = 3.5,
    Duration flightDelay = const Duration(milliseconds: 4000),
  }) async {
    stopOrbit();

    final targetLat = latitude ?? _lastFlyToLat ?? 28.6139;
    final targetLon = longitude ?? _lastFlyToLon ?? 77.2090;
    final targetAlt = altitude ?? _lastFlyToAlt ?? 500000.0;

    _lastFlyToLat = targetLat;
    _lastFlyToLon = targetLon;
    _lastFlyToAlt = targetAlt;

    _update(_state.copyWith(isOrbiting: true));
    try {
      final initialLookAtKml =
          'flytoview=<LookAt>'
          '<longitude>$targetLon</longitude>'
          '<latitude>$targetLat</latitude>'
          '<altitude>0</altitude>'
          '<heading>0</heading>'
          '<tilt>$tilt</tilt>'
          '<range>$targetAlt</range>'
          '<altitudeMode>relativeToGround</altitudeMode>'
          '</LookAt>';
      await execute("echo '$initialLookAtKml' > $_queryFile");
    } catch (_) {}
    if (flightDelay > Duration.zero) {
      await Future.delayed(flightDelay);
    }
    if (!_state.isOrbiting || _client == null || !_state.isConnected) {
      return;
    }

    bool isSendingOrbitStep = false;
    _currentOrbitHeading = 0.0;
    _orbitTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) async {
      if (!_state.isConnected || _client == null || !_state.isOrbiting) {
        stopOrbit();
        return;
      }
      if (isSendingOrbitStep) return;
      isSendingOrbitStep = true;
      _currentOrbitHeading = (_currentOrbitHeading + speed) % 360.0;
      try {
        final lookAtKml =
            'flytoview=<LookAt>'
            '<longitude>$targetLon</longitude>'
            '<latitude>$targetLat</latitude>'
            '<altitude>0</altitude>'
            '<heading>${_currentOrbitHeading.toStringAsFixed(1)}</heading>'
            '<tilt>$tilt</tilt>'
            '<range>$targetAlt</range>'
            '<altitudeMode>relativeToGround</altitudeMode>'
            '</LookAt>';
        await execute("echo '$lookAtKml' > $_queryFile");
      } catch (_) {} finally {
        isSendingOrbitStep = false;
      }
    });
  }

  void stopOrbit() {
    _orbitTimer?.cancel();
    _orbitTimer = null;
    if (_state.isOrbiting) {
      _update(_state.copyWith(isOrbiting: false));
    }
  }

  Future<void> toggleOrbit({
    double? latitude,
    double? longitude,
    double? altitude,
  }) async {
    if (_state.isOrbiting) {
      stopOrbit();
    } else {
      await startOrbit(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
      );
    }
  }

  Future<void> flyTo({
    required double latitude,
    required double longitude,
    required double altitude,
    double tilt = _default3DTilt,
    double heading = 0,
  }) async {
    if (_client == null) throw Exception('Not connected');

    stopOrbit();

    _lastFlyToLat = latitude;
    _lastFlyToLon = longitude;
    _lastFlyToAlt = altitude;

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

  DateTime? _lastFlyToTime;

  static double zoomToAltitude(double zoom, double latitude) {
    final clampedZoom = zoom.clamp(1.0, 20.0);
    final latRad = latitude * math.pi / 180.0;
    final metersPerPixel = (156543.03392 * math.cos(latRad)) / math.pow(2, clampedZoom);
    final alt = metersPerPixel * 800.0 * 1.2;
    return alt.clamp(100.0, 20000000.0);
  }

  Future<void> flyToThrottled({
    required double latitude,
    required double longitude,
    required double zoom,
    double tilt = _default3DTilt,
    double heading = 0,
  }) async {
    if (!_state.isConnected || _client == null) return;
    final now = DateTime.now();
    if (_lastFlyToTime != null &&
        now.difference(_lastFlyToTime!).inMilliseconds < 120) {
      return;
    }
    _lastFlyToTime = now;
    final altitude = zoomToAltitude(zoom, latitude);
    try {
      await flyTo(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        tilt: tilt,
        heading: heading,
      );
    } catch (_) {}
  }

  Future<void> clearKml() async {
    if (_client == null) throw Exception('Not connected');
    const emptyKml =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<kml xmlns="http://www.opengis.net/kml/2.2">'
        '<Document><name>Empty</name></Document></kml>';
    final emptyBytes = utf8.encode(emptyKml);
    await execute("rm -f $_kmlDir/*.kml 2>&1");
    await _sftpUpload(_kmlSyncFile, emptyBytes);
    for (int i = 1; i <= _state.screenCount; i++) {
      await _sftpUpload('/var/www/html/kmls_$i.txt', emptyBytes);
    }
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
    await Future.delayed(const Duration(milliseconds: 800));
    final masterLinkKml = _buildSyncPlacesKml('http://localhost:$port/kmls_1.txt');
    final masterBytes = utf8.encode(masterLinkKml);

    await execute('mkdir -p /home/lg/.googleearth /home/lg/.local/share/Google/GoogleEarth');
    for (final path in [
      '/home/lg/.googleearth/MyPlaces.kml',
      '/home/lg/.googleearth/myplaces.kml',
      '/home/lg/.local/share/Google/GoogleEarth/MyPlaces.kml',
      '/home/lg/.local/share/Google/GoogleEarth/myplaces.kml',
    ]) {
      await _sftpUpload(path, masterBytes);
    }
    const slaveTmp = '/tmp/_cs_slave_myplaces.kml';

    for (int i = 2; i <= _state.screenCount; i++) {
      try {
        final slaveLinkKml = _buildSyncPlacesKml('http://$ip:$port/kmls_$i.txt');
        await _sftpUpload(slaveTmp, utf8.encode(slaveLinkKml));
        await execute(
          'sshpass -p lg ssh -o StrictHostKeyChecking=no lg@lg$i '
          '"mkdir -p /home/lg/.googleearth /home/lg/.local/share/Google/GoogleEarth"'
        );
        for (final destPath in [
          '/home/lg/.googleearth/MyPlaces.kml',
          '/home/lg/.googleearth/myplaces.kml',
          '/home/lg/.local/share/Google/GoogleEarth/MyPlaces.kml',
          '/home/lg/.local/share/Google/GoogleEarth/myplaces.kml',
        ]) {
          await execute(
            'sshpass -p lg scp -o StrictHostKeyChecking=no '
            '$slaveTmp lg@lg$i:$destPath 2>&1'
          );
        }
      } catch (_) {}
    }
    await execute('rm -f $slaveTmp 2>/dev/null');
    await Future.delayed(const Duration(milliseconds: 300));
    const seedKml =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<kml xmlns="http://www.opengis.net/kml/2.2">'
        '<Document><name>Climate Storyteller</name></Document></kml>';
    final seedBytes = utf8.encode(seedKml);
    await _sftpUpload(_kmlSyncFile, seedBytes);
    for (int i = 1; i <= _state.screenCount; i++) {
      await _sftpUpload('/var/www/html/kmls_$i.txt', seedBytes);
    }
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

  Future<Directory> get _localKmlDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/kmls');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
  static const int _kmlCacheVersion = 60;

  Future<String> buildKml({
    required ClimateRegion region,
    required ClimateEra era,
    String? noaaApiKey,
  }) async {
    final year = int.tryParse(era.label) ?? 2026;
    return buildKmlForYear(region: region, year: year, noaaApiKey: noaaApiKey);
  }

  Future<String> buildKmlForYear({
    required ClimateRegion region,
    required int year,
    String? noaaApiKey,
  }) async {
    final filename =
        '${region.id}_year_${year}_${region.category}_v$_kmlCacheVersion.kml';
    final dir = await _localKmlDir;
    final file = File('${dir.path}/$filename');

    if (file.existsSync()) {
      final age = DateTime.now().difference(file.lastModifiedSync());
      if (age.inHours < 24) return file.path;
    }

    final era = switch (year) {
      <= 1924 => ClimateEra.preindustrial1900,
      <= 1964 => ClimateEra.midCentury1950,
      <= 1999 => ClimateEra.lateCentury1980,
      <= 2049 => ClimateEra.present2026,
      <= 2084 => ClimateEra.midProjection2060,
      _       => ClimateEra.projected2100,
    };

    final kml = await _generateKml(region: region, era: era, year: year, noaaApiKey: noaaApiKey);
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


  Future<String> _generateKml({
    required ClimateRegion region,
    required ClimateEra era,
    required int year,
    String? noaaApiKey,
  }) async {
    final regionData = getRegionData(region.id);

    final overlayUrl = _buildGibsOverlayUrl(
      region.category,
      era,
      region.latitude,
      region.longitude,
    );
    final stats = _getEraStats(regionData, region.category, year);
    final noaaTemp = await _fetchNoaaTemperature(noaaApiKey);

    return _buildKmlString(
      region: region,
      era: era,
      year: year,
      overlayUrl: overlayUrl,
      stats: stats,
      noaaGlobalTemp: noaaTemp,
      regionData: regionData,
    );
  }
  static const double _overlayDegreeOffset = 2.0;

  String _buildGibsOverlayUrl(
    String category,
    ClimateEra era,
    double lat,
    double lon,
  ) {
    final layer = _gibsLayers[category] ?? _gibsLayers['glacier']!;
    final date = switch (era) {
      ClimateEra.preindustrial1900 => '2000-02-24',
      ClimateEra.midCentury1950    => '2005-06-01',
      ClimateEra.lateCentury1980   => '2010-06-01',
      ClimateEra.present2026       => '2023-06-01',
      ClimateEra.midProjection2060 => '2023-06-01',
      ClimateEra.projected2100     => '2023-06-01',
    };

    final north = (lat + _overlayDegreeOffset).clamp(-90, 90);
    final south = (lat - _overlayDegreeOffset).clamp(-90, 90);
    final east = lon + _overlayDegreeOffset;
    final west = lon - _overlayDegreeOffset;

    final url = '$_gibsBase?'
        'SERVICE=WMS&REQUEST=GetMap&VERSION=1.1.1'
        '&LAYERS=$layer'
        '&SRS=EPSG:4326'
        '&FORMAT=image/png'
        '&WIDTH=1024&HEIGHT=1024'
        '&BBOX=$west,$south,$east,$north'
        '&TRANSPARENT=TRUE'
        '&TIME=$date';
    return url.replaceAll('&', '&amp;');
  }

  static double? _cachedNoaaTemp;
  static DateTime? _lastNoaaFetch;

  Future<double?> _fetchNoaaTemperature(String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) return null;
    if (_cachedNoaaTemp != null && _lastNoaaFetch != null) {
      if (DateTime.now().difference(_lastNoaaFetch!).inHours < 1) {
        return _cachedNoaaTemp;
      }
    }
    try {
      final uri = Uri.parse(
        '$_noaaBase/data?datasetid=GHCND'
        '&datatypeid=TAVG'
        '&stationid=GHCND:USW00094728'
        '&limit=1'
        '&sortfield=date&sortorder=desc',
      );
      final res = await http.get(uri,
          headers: {'token': apiKey}).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final value = body['results']?[0]?['value'] as num?;
        if (value != null) {
          _cachedNoaaTemp = value.toDouble();
          _lastNoaaFetch = DateTime.now();
        }
        return value?.toDouble();
      }
    } catch (_) {}
    return _cachedNoaaTemp;
  }

  double _interpolateMap(Map<int, double> map, int year) {
    if (map.isEmpty) return 0.0;
    final years = map.keys.toList()..sort();
    if (year <= years.first) return map[years.first]!;
    if (year >= years.last) return map[years.last]!;
    for (int i = 0; i < years.length - 1; i++) {
      if (year >= years[i] && year <= years[i + 1]) {
        final t = (year - years[i]) / (years[i + 1] - years[i]);
        return map[years[i]]! + t * (map[years[i + 1]]! - map[years[i]]!);
      }
    }
    return 0.0;
  }

  Map<String, String> _getEraStats(IpccRegionData? data, String category, int year) {
    if (data == null) {
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

    final localTemp = _interpolateMap(data.localTempAnomaly, year);
    final seaLevel = _interpolateMap(data.seaLevelMm, year);
    final iceExtentKm2 = _interpolateMap(data.iceExtentKm2, year);
    final forestPct = _interpolateMap(data.forestCoverPct, year);
    final aqi = _interpolateMap(data.aqiIndex, year);

    final iceExtentM = iceExtentKm2 / 1000000.0;
    final forestLossPct = (100.0 - forestPct).clamp(0.0, 100.0);

    return {
      'temp_anomaly': '+${localTemp.toStringAsFixed(1)}°C',
      'sea_level':    '${seaLevel.toStringAsFixed(0)} mm',
      'ice_extent':   '${iceExtentM.toStringAsFixed(1)} M km²',
      'forest_loss':  '${forestLossPct.toStringAsFixed(1)}%',
      'forest_cover': '${forestPct.toStringAsFixed(1)}%',
      'aqi':          aqi.toStringAsFixed(0),
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
    int? year,
    required String overlayUrl,
    required Map<String, String> stats,
    required double? noaaGlobalTemp,
    required IpccRegionData? regionData,
  }) {
    final activeYear = year ?? int.tryParse(era.label) ?? 2026;
    final description = regionData?.description[int.parse(era.label)] ??
        'Climate data for ${region.name} — ${era.label}';

    final tempLine = noaaGlobalTemp != null
        ? '<Data name="noaa_live_temp"><value>$noaaGlobalTemp°C</value></Data>'
        : '';

    final host = _state.ipAddress ?? 'localhost';
    final port = _state.webPort;

    final pastTemp = regionData != null ? _interpolateMap(regionData.localTempAnomaly, 1900) : 0.0;
    final nowTemp = regionData != null ? _interpolateMap(regionData.localTempAnomaly, 2026) : 0.0;
    final activeTemp = regionData != null ? _interpolateMap(regionData.localTempAnomaly, activeYear) : 0.0;
    final futureTemp = regionData != null ? _interpolateMap(regionData.localTempAnomaly, 2100) : 0.0;

    String pastStat = '';
    String nowStat = '';
    String activeStat = '';
    String futureStat = '';
    String statHeader = '';

    if (region.category == 'glacier') {
      statHeader = 'Ice Extent';
      pastStat = '${((regionData != null ? _interpolateMap(regionData.iceExtentKm2, 1900) : 0.0) / 1000000).toStringAsFixed(1)}M km²';
      nowStat = '${((regionData != null ? _interpolateMap(regionData.iceExtentKm2, 2026) : 0.0) / 1000000).toStringAsFixed(1)}M km²';
      activeStat = '${((regionData != null ? _interpolateMap(regionData.iceExtentKm2, activeYear) : 0.0) / 1000000).toStringAsFixed(1)}M km²';
      futureStat = '${((regionData != null ? _interpolateMap(regionData.iceExtentKm2, 2100) : 0.0) / 1000000).toStringAsFixed(1)}M km²';
    } else if (region.category == 'sealevel') {
      statHeader = 'Sea Level Rise';
      pastStat = '${(regionData != null ? _interpolateMap(regionData.seaLevelMm, 1900) : 0.0).toStringAsFixed(0)} mm';
      nowStat = '${(regionData != null ? _interpolateMap(regionData.seaLevelMm, 2026) : 0.0).toStringAsFixed(0)} mm';
      activeStat = '${(regionData != null ? _interpolateMap(regionData.seaLevelMm, activeYear) : 0.0).toStringAsFixed(0)} mm';
      futureStat = '${(regionData != null ? _interpolateMap(regionData.seaLevelMm, 2100) : 0.0).toStringAsFixed(0)} mm';
    } else if (region.category == 'forest') {
      statHeader = 'Forest Cover';
      pastStat = '${(regionData != null ? _interpolateMap(regionData.forestCoverPct, 1900) : 100.0).toStringAsFixed(1)}%';
      nowStat = '${(regionData != null ? _interpolateMap(regionData.forestCoverPct, 2026) : 100.0).toStringAsFixed(1)}%';
      activeStat = '${(regionData != null ? _interpolateMap(regionData.forestCoverPct, activeYear) : 100.0).toStringAsFixed(1)}%';
      futureStat = '${(regionData != null ? _interpolateMap(regionData.forestCoverPct, 2100) : 100.0).toStringAsFixed(1)}%';
    } else if (region.category == 'heat') {
      statHeader = 'Heat Anomaly';
      pastStat = '+${pastTemp.toStringAsFixed(1)}°C';
      nowStat = '+${nowTemp.toStringAsFixed(1)}°C';
      activeStat = '+${activeTemp.toStringAsFixed(1)}°C';
      futureStat = '+${futureTemp.toStringAsFixed(1)}°C';
    } else if (region.category == 'aqi') {
      statHeader = 'Air Quality Index';
      pastStat = (regionData != null ? _interpolateMap(regionData.aqiIndex, 1900) : 0.0).toStringAsFixed(0);
      nowStat = (regionData != null ? _interpolateMap(regionData.aqiIndex, 2026) : 0.0).toStringAsFixed(0);
      activeStat = (regionData != null ? _interpolateMap(regionData.aqiIndex, activeYear) : 0.0).toStringAsFixed(0);
      futureStat = (regionData != null ? _interpolateMap(regionData.aqiIndex, 2100) : 0.0).toStringAsFixed(0);
    }

    final isSpecialYear = activeYear != 1900 && activeYear != 2026 && activeYear != 2100;
    final riskBadgeHtml = switch (activeYear) {
      <= 1950 => "<span style='background:#2ecc71;color:#ffffff;padding:5px 12px;border-radius:14px;font-size:14px;font-weight:bold;display:inline-block;'>🟢 BASELINE EQUILIBRIUM</span>",
      <= 1999 => "<span style='background:#f1c40f;color:#000000;padding:5px 12px;border-radius:14px;font-size:14px;font-weight:bold;display:inline-block;'>🟡 ELEVATED CLIMATE STRESS</span>",
      <= 2049 => "<span style='background:#e67e22;color:#ffffff;padding:5px 12px;border-radius:14px;font-size:14px;font-weight:bold;display:inline-block;'>🟧 ACTIVE TIPPING RISK</span>",
      _       => "<span style='background:#e74c3c;color:#ffffff;padding:5px 12px;border-radius:14px;font-size:14px;font-weight:bold;display:inline-block;'>🔴 CRITICAL TIPPING POINT BREACH</span>",
    };
    final actionGuideHtml = switch (region.category) {
      'glacier'  => 'Enforce Paris Agreement net-zero emissions targets; protect alpine watershed infrastructure; deploy early warning systems for glacial lake outburst floods.',
      'sealevel' => 'Construct nature-based living shorelines and sea walls; restore mangrove ecosystems; implement climate-managed retreat and aquifer protection plans.',
      'forest'   => 'Halt commercial deforestation; enforce indigenous land tenure rights; execute large-scale rainforest restoration & carbon sink preservation.',
      'heat'     => 'Expand urban green canopies and reflective roofs; establish cooling centers for outdoor workers; modernize power grids for extreme weather resilience.',
      'aqi'      => 'Transition rapidly to electric mobility & renewables; phase out crop stubble burning; enforce industrial emissions standards.',
      _          => 'Implement sustainable resource management and renewable energy transitions.',
    };

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
     xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>${LG3DVisuals.escapeXmlText(region.name)} — ${LG3DVisuals.escapeXmlText(era.label)}</name>
    <visibility>1</visibility>
    
    <!-- Timeline interval so Google Earth displays the Time Slider GUI on LG Master -->
    <TimeSpan>
      <begin>1850-01-01T00:00:00Z</begin>
      <end>2150-12-31T23:59:59Z</end>
    </TimeSpan>
    <gx:TimeStamp>
      <when>$activeYear-01-01T00:00:00Z</when>
    </gx:TimeStamp>

    <Style id="customBalloon">
      <BalloonStyle>
        <bgColor>ff0f172a</bgColor>
        <textColor>fff8fafc</textColor>
        <text><![CDATA[
          <font face="Helvetica, Arial, sans-serif" color="#f8fafc">
            \$[description]
          </font>
        ]]></text>
      </BalloonStyle>
    </Style>

    <!-- Camera position -->
    <LookAt>
      <longitude>${region.longitude}</longitude>
      <latitude>${region.latitude}</latitude>
      <altitude>0</altitude>
      <heading>$_default3DHeading</heading>
      <tilt>$_default3DTilt</tilt>
      <range>${region.altitude}</range>
      <altitudeMode>relativeToGround</altitudeMode>
      <gx:TimeStamp>
        <when>$activeYear-01-01T00:00:00Z</when>
      </gx:TimeStamp>
    </LookAt>


    <!-- Main Region Scientific Data Placemark -->
    <Placemark>
      <name>${LG3DVisuals.escapeXmlText(region.name)} — Scientific Profile</name>
      <visibility>1</visibility>
      <gx:balloonVisibility>1</gx:balloonVisibility>
      <styleUrl>#customBalloon</styleUrl>
      <description><![CDATA[
        <div style='font-family:Helvetica,Arial,sans-serif;max-width:580px;background:#0f172a;color:#f8fafc;padding:20px 24px;border-radius:12px;border:1px solid #334155;box-shadow:0 8px 30px rgba(0,0,0,0.6);'>
        <img src='http://$host:$port/kml/region_${region.id}.png' onerror="this.src='${region.imageUrl}';" style='width:100%;max-height:220px;object-fit:cover;border-radius:10px;margin-bottom:14px;border:1px solid #334155;' />
        
        <div style='display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;'>
          <h2 style='color:#38bdf8;margin:0;font-size:24px;font-weight:700;letter-spacing:-0.3px;'>${region.name}</h2>
        </div>
        <div style='margin-bottom:14px;'>$riskBadgeHtml</div>

        <p style='color:#94a3b8;font-size:16px;margin:0 0 14px;line-height:1.5;'><b>Active Era:</b> $activeYear (${era.label}) &bull; IPCC AR6 SSP3-7.0</p>
        
        <!-- Multi-Era Metrics Matrix -->
        <table style='border-collapse:collapse;width:100%;font-size:15px;margin-bottom:14px;'>
          <tr style='background:#1e293b;color:#e2e8f0;'>
            <th style='padding:8px 10px;text-align:left;font-size:15px;'>Era / Year</th>
            <th style='padding:8px 10px;text-align:center;font-size:15px;'>Temp &Delta;</th>
            <th style='padding:8px 10px;text-align:center;font-size:15px;'>$statHeader</th>
            <th style='padding:8px 10px;text-align:center;font-size:15px;'>Impact</th>
          </tr>
          <tr style='background:${activeYear == 1900 ? '#14532d' : '#0f172a'};color:#4ade80;'>
            <td style='padding:8px 10px;'>${activeYear == 1900 ? '&#9654; ' : ''}1900 (Baseline)</td>
            <td style='padding:8px 10px;text-align:center;'>+${pastTemp.toStringAsFixed(1)}&deg;C</td>
            <td style='padding:8px 10px;text-align:center;'>$pastStat</td>
            <td style='padding:8px 10px;text-align:center;'>Stable</td>
          </tr>
          ${isSpecialYear ? '''
          <tr style='background:#1e3a8a;color:#38bdf8;font-weight:bold;'>
            <td style='padding:8px 10px;'>&#9654; $activeYear (Active)</td>
            <td style='padding:8px 10px;text-align:center;'>+${activeTemp.toStringAsFixed(1)}&deg;C</td>
            <td style='padding:8px 10px;text-align:center;'>$activeStat</td>
            <td style='padding:8px 10px;text-align:center;'>&#9733; Active</td>
          </tr>
          ''' : ''}
          <tr style='background:${activeYear == 2026 ? '#365314' : '#0f172a'};color:#facc15;'>
            <td style='padding:8px 10px;'>${activeYear == 2026 ? '&#9654; ' : ''}<b>2026 (Present)</b></td>
            <td style='padding:8px 10px;text-align:center;'><b>+${nowTemp.toStringAsFixed(1)}&deg;C</b></td>
            <td style='padding:8px 10px;text-align:center;'><b>$nowStat</b></td>
            <td style='padding:8px 10px;text-align:center;'>${region.category == 'forest' || region.category == 'glacier' ? '&#8675; Declining' : '&#8673; Rising'}</td>
          </tr>
          <tr style='background:${activeYear == 2100 ? '#7f1d1d' : '#0f172a'};color:#f87171;'>
            <td style='padding:8px 10px;'>${activeYear == 2100 ? '&#9654; ' : ''}<b>2100 (Projected)</b></td>
            <td style='padding:8px 10px;text-align:center;'><b>+${futureTemp.toStringAsFixed(1)}&deg;C</b></td>
            <td style='padding:8px 10px;text-align:center;'><b>$futureStat</b></td>
            <td style='padding:8px 10px;text-align:center;'>${region.category == 'forest' || region.category == 'glacier' ? '&#8675;&#8675; Severe' : '&#8673;&#8673; Severe'}</td>
          </tr>
        </table>

        <!-- Narrative Context -->
        <div style='margin-bottom:12px;padding:12px 14px;background:#1e293b;border-left:5px solid #38bdf8;border-radius:6px;'>
          <b style='color:#38bdf8;font-size:16px;display:block;margin-bottom:4px;'>Scientific Narrative Analysis:</b>
          <span style='color:#cbd5e1;font-size:15px;line-height:1.5;'>$description</span>
        </div>

        <!-- Mitigation & Adaptation Plan -->
        <div style='margin-bottom:12px;padding:12px 14px;background:#142834;border-left:5px solid #22c55e;border-radius:6px;'>
          <b style='color:#22c55e;font-size:16px;display:block;margin-bottom:4px;'>Climate Resilience &amp; Mitigation Plan:</b>
          <span style='color:#cbd5e1;font-size:15px;line-height:1.5;'>$actionGuideHtml</span>
        </div>

        <p style='color:#64748b;font-size:12px;margin-top:10px;line-height:1.4;'>
          <i>Data Sources: ${region.category == 'aqi' ? 'OpenAQ / WHO (2026); IPCC AR6 Scenarios (2100)' : 'IPCC AR6 Working Group I/II (SSP3-7.0) &bull; NASA Earthdata GIBS &bull; NOAA CDO'}</i>
        </p>
        </div>
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

    <!-- Sub-Region Localized Monitoring Station Network -->
    ${_buildSubStationPlacemarks(region, era, activeYear)}

    <!-- Category Visual Geometry, 3D Data Bars & Floating Banners -->
    ${_buildCategoryLayer(region, era, stats, regionData)}

  </Document>
</kml>''';
  }

  /// Builds localized monitoring sub-station placemarks and 3D sensor beacons for each region.
  String _buildSubStationPlacemarks(ClimateRegion region, ClimateEra era, int activeYear) {
    final sb = StringBuffer();
    sb.writeln('<Folder><name>${LG3DVisuals.escapeXmlText(region.name)} Monitoring Network</name><visibility>1</visibility>');

    final stations = switch (region.id) {
      'arctic' => [
        {'name': 'Svalbard Atmospheric Observatory', 'dLat': 0.35, 'dLon': -0.40, 'type': 'Ice Core & Greenhouse Gas Station'},
        {'name': 'Greenland Summit Drill Camp', 'dLat': -0.30, 'dLon': 0.45, 'type': 'Glacier Thickness Monitor'},
        {'name': 'Beaufort Sea Ice Buoy Post', 'dLat': 0.25, 'dLon': 0.50, 'type': 'Ocean Heat & Ice Drift Buoy'},
      ],
      'himalaya' => [
        {'name': 'Everest Glacier Weather Post', 'dLat': 0.20, 'dLon': 0.25, 'type': 'High-Altitude Automated Weather Station'},
        {'name': 'Gangotri Melt Hydrology Post', 'dLat': -0.25, 'dLon': -0.35, 'type': 'Glacial Lake Outburst Sensor'},
        {'name': 'Karakoram Anomaly Research Camp', 'dLat': 0.35, 'dLon': -0.45, 'type': 'Mass Balance Monitoring Post'},
      ],
      'amazon' => [
        {'name': 'Manaus Canopy Research Tower', 'dLat': -0.15, 'dLon': 0.25, 'type': 'CO2 Flux & Canopy Photosynthesis Tower'},
        {'name': 'Deforestation Frontier Post', 'dLat': -0.35, 'dLon': -0.30, 'type': 'Satellite Loss Ground-Truth Station'},
        {'name': 'Tapajós Biodiversity Reserve', 'dLat': 0.25, 'dLon': -0.20, 'type': 'Tropical Forest Micro-Climate Sensor'},
      ],
      'pacific' => [
        {'name': 'Tarawa Atoll Tide Gauge Post', 'dLat': 0.20, 'dLon': -0.25, 'type': 'Continuous Sea Level & Wave Height Gauge'},
        {'name': 'Funafuti Aquifer Well Station', 'dLat': -0.25, 'dLon': 0.30, 'type': 'Freshwater Salinity Sensor'},
        {'name': 'Pacific Ocean Deep Buoy Array', 'dLat': -0.15, 'dLon': -0.35, 'type': 'Marine Heatwave & Coral Bleaching Monitor'},
      ],
      'maldives' => [
        {'name': 'Malé Island Tide Gauge Station', 'dLat': 0.15, 'dLon': -0.15, 'type': 'High-Precision Tsunami & Sea Level Gauge'},
        {'name': 'Hulhumalé Reclamation Monitor', 'dLat': 0.25, 'dLon': 0.20, 'type': 'Coastal Erosion & Wall Sensor'},
        {'name': 'Ari Atoll Coral Bleaching Post', 'dLat': -0.20, 'dLon': -0.25, 'type': 'Sub-Surface Ocean Temperature Array'},
      ],
      'sahara' => [
        {'name': 'Ahaggar Thermal Weather Center', 'dLat': 0.30, 'dLon': -0.35, 'type': 'Extreme Heatwave & Solar Radiation Station'},
        {'name': 'Sahel Desertification Frontier Post', 'dLat': -0.35, 'dLon': 0.25, 'type': 'Soil Moisture & Dune Encroachment Sensor'},
        {'name': 'Tuat Aquifer Oasis Monitor', 'dLat': 0.15, 'dLon': 0.35, 'type': 'Underground Water Table Depletion Sensor'},
      ],
      'delhi' => [
        {'name': 'Anand Vihar AQI Monitoring Post', 'dLat': 0.15, 'dLon': 0.20, 'type': 'PM2.5 / PM10 / NO2 Real-Time Sensor'},
        {'name': 'Yamuna Basin Water Quality Post', 'dLat': -0.15, 'dLon': -0.15, 'type': 'Hydrology & River Thermal Sensor'},
        {'name': 'IGI Weather & Urban Heat Post', 'dLat': -0.20, 'dLon': -0.25, 'type': 'Urban Heat Island Micro-Climate Station'},
      ],
      _ => [
        {'name': 'Regional Monitoring Station Alpha', 'dLat': 0.20, 'dLon': -0.20, 'type': 'Regional Climate Sensor'},
        {'name': 'Regional Monitoring Station Beta', 'dLat': -0.20, 'dLon': 0.20, 'type': 'Environmental Observation Post'},
      ],
    };

    for (int idx = 0; idx < stations.length; idx++) {
      final st = stations[idx];
      final stLat = region.latitude + (st['dLat'] as double);
      final stLon = region.longitude + (st['dLon'] as double);
      final stName = st['name'] as String;
      final stType = st['type'] as String;
      sb.writeln(LG3DVisuals.build3DSensorBeacon(
        centerLat: stLat,
        centerLon: stLon,
        radiusDeg: 0.018,
        heightMeters: 15000.0,
        beaconColorAbgr: 'c000e5ff',
        name: '$stName 3D Beacon',
        description: '3D Environmental Sensor Node',
      ));
      sb.writeln(LG3DVisuals.build3DConnectingCorridor(
        fromLat: stLat,
        fromLon: stLon,
        toLat: region.latitude,
        toLon: region.longitude,
        altitudeMeters: 9000.0,
        lineColorAbgr: 'aa00e5ff',
        lineWidth: 3.0,
        name: 'Telemetry Link: $stName -> ${region.name}',
      ));
      sb.writeln('''
      <Placemark>
        <name>${LG3DVisuals.escapeXmlText(stName)}</name>
        <visibility>1</visibility>
        <Style>
          <IconStyle>
            <scale>0.95</scale>
            <Icon><href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href></Icon>
            <color>ff00e5ff</color>
          </IconStyle>
          <LabelStyle>
            <color>ff00e5ff</color>
            <scale>1.1</scale>
          </LabelStyle>
        </Style>
        <description><![CDATA[
          <div style='font-family:Helvetica,Arial,sans-serif;max-width:380px;background:#0f172a;color:#f8fafc;padding:16px 20px;border-radius:10px;border:1px solid #334155;'>
            <h4 style='color:#00e5ff;margin:0 0 6px;font-size:18px;font-weight:700;'>$stName</h4>
            <p style='color:#94a3b8;font-size:15px;margin:0 0 10px;'><b>Station Type:</b> $stType</p>
            <div style='background:#1e293b;padding:10px 12px;border-radius:6px;font-size:14px;color:#cbd5e1;line-height:1.5;'>
              &bull; <b>Active Year:</b> $activeYear<br/>
              &bull; <b>Coordinates:</b> ${stLat.toStringAsFixed(4)}&deg;, ${stLon.toStringAsFixed(4)}&deg;<br/>
              &bull; <b>Status:</b> Telemetry Operational (Real-Time Synchronized)
            </div>
          </div>
        ]]></description>
        <Point>
          <coordinates>$stLon,$stLat,15000</coordinates>
        </Point>
      </Placemark>''');
    }

    sb.writeln('</Folder>');
    return sb.toString();
  }



  String _buildCategoryLayer(
    ClimateRegion region,
    ClimateEra era,
    Map<String, String> stats,
    IpccRegionData? regionData,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('<Folder><name>${LG3DVisuals.escapeXmlText(region.name)} 3D Geometric Progression</name>');
    buffer.writeln('<visibility>1</visibility><open>1</open>');
    for (final e in ClimateEra.values) {
      final eraStats = _getEraStats(regionData, region.category, int.parse(e.label));

      buffer.writeln('<Folder>');
      buffer.writeln('<name>${LG3DVisuals.escapeXmlText(region.name)} \u2014 ${e.label}</name>');
      buffer.writeln('<visibility>1</visibility>');
      buffer.writeln(_timeSpanKml(e));
      switch (region.category) {
        case 'glacier':
          buffer.writeln(_glacier3DShape(region, e, eraStats));
          break;
        case 'sealevel':
          buffer.writeln(_seaLevel3DShape(region, e, eraStats));
          break;
        case 'forest':
          buffer.writeln(_forest3DShape(region, e, eraStats));
          break;
        case 'heat':
          buffer.writeln(_heat3DShape(region, e, eraStats));
          break;
        case 'aqi':
          buffer.writeln(_aqi3DShape(region, e, eraStats));
          break;
      }

      buffer.writeln('</Folder>');
    }

    buffer.writeln('</Folder>');
    return buffer.toString();
  }

  String _heat3DShape(ClimateRegion region, ClimateEra era, Map<String, String> eraStats) {
    final sb = StringBuffer();

    final domeHeight = switch (era) {
      ClimateEra.preindustrial1900 => 16000.0,
      ClimateEra.midCentury1950    => 24000.0,
      ClimateEra.lateCentury1980   => 32000.0,
      ClimateEra.present2026       => 40000.0,
      ClimateEra.midProjection2060 => 48000.0,
      ClimateEra.projected2100     => 56000.0,
    };
    final domeRadius = switch (era) {
      ClimateEra.preindustrial1900 => 0.25,
      ClimateEra.midCentury1950    => 0.35,
      ClimateEra.lateCentury1980   => 0.45,
      ClimateEra.present2026       => 0.55,
      ClimateEra.midProjection2060 => 0.65,
      ClimateEra.projected2100     => 0.75,
    };

    final colors = switch (era) {
      ClimateEra.preindustrial1900 => ['9933cc44', '9955ddaa', '9933cc44', '9955ddaa'],
      ClimateEra.midCentury1950    => ['aa84cc16', 'aaa3e635', 'aa84cc16', 'aaa3e635'],
      ClimateEra.lateCentury1980   => ['bbfacc15', 'bbfde047', 'bbfacc15', 'bbfde047'],
      ClimateEra.present2026       => ['ccf97316', 'ccfb923c', 'ccf97316', 'ccfb923c'],
      ClimateEra.midProjection2060 => ['ddf97316', 'ddef4444', 'ddf97316', 'ddef4444'],
      ClimateEra.projected2100     => ['eeb91c1c', 'eeef4444', 'eeb91c1c', 'eeef4444'],
    };
    sb.writeln(LG3DVisuals.build3DGeodesicDome(
      centerLat: region.latitude,
      centerLon: region.longitude,
      radiusDeg: domeRadius,
      heightMeters: domeHeight,
      segments: 14,
      faceColorsAbgr: colors,
      wireColorAbgr: 'ffffaa00',
      name: '3D Atmospheric Heat Dome — ${era.label}',
      description: 'Thermal Anomaly Geodesic Structure (${era.label})',
    ));

    return sb.toString();
  }

  String _glacier3DShape(ClimateRegion region, ClimateEra era, Map<String, String> eraStats) {
    final sb = StringBuffer();
    final spires = [
      {'name': 'Lower Valley Terminus Tongue', 'dLat': -0.45, 'dLon': 0.30, 'meltEra': ClimateEra.midCentury1950},
      {'name': 'Glacial Lake Outflow Apron', 'dLat': -0.50, 'dLon': -0.35, 'meltEra': ClimateEra.midCentury1950},
      {'name': 'Southern Foothill Moraine Spire', 'dLat': -0.38, 'dLon': 0.45, 'meltEra': ClimateEra.midCentury1950},
      {'name': 'Southwest Valley Glacial Toe', 'dLat': -0.32, 'dLon': -0.48, 'meltEra': ClimateEra.midCentury1950},
      {'name': 'South Face Ice Apron Spire', 'dLat': -0.22, 'dLon': 0.38, 'meltEra': ClimateEra.lateCentury1980},
      {'name': 'Western Tributary Glacial Finger', 'dLat': 0.15, 'dLon': -0.46, 'meltEra': ClimateEra.lateCentury1980},
      {'name': 'Lower Cirque Firn Spire', 'dLat': -0.28, 'dLon': -0.44, 'meltEra': ClimateEra.lateCentury1980},
      {'name': 'Southeast Cirque Serac Spire', 'dLat': -0.12, 'dLon': 0.28, 'meltEra': ClimateEra.lateCentury1980},
      {'name': 'Eastern Cirque Glacial Spire', 'dLat': 0.24, 'dLon': 0.40, 'meltEra': ClimateEra.present2026},
      {'name': 'North Ridge Icefall Spire', 'dLat': 0.36, 'dLon': 0.20, 'meltEra': ClimateEra.present2026},
      {'name': 'Central Glacial Pass Spire', 'dLat': -0.10, 'dLon': -0.20, 'meltEra': ClimateEra.present2026},
      {'name': 'Upper Firn Basin Ice Shard', 'dLat': 0.30, 'dLon': -0.24, 'meltEra': ClimateEra.midProjection2060},
      {'name': 'Northwestern Serac Wall Spire', 'dLat': 0.40, 'dLon': -0.34, 'meltEra': ClimateEra.midProjection2060},
      {'name': 'Northeast High Ridge Spire', 'dLat': 0.44, 'dLon': 0.10, 'meltEra': ClimateEra.midProjection2060},
      {'name': 'High Alpine Nunatak Spire', 'dLat': 0.16, 'dLon': 0.12, 'meltEra': ClimateEra.projected2100},
      {'name': 'Summit Diamond Horn Peak', 'dLat': 0.0, 'dLon': 0.0, 'meltEra': ClimateEra.projected2100},
    ];

    const baseHeight = 44000.0;
    const span = 0.105;

    for (final s in spires) {
      final sLat = region.latitude + (s['dLat'] as double);
      final sLon = region.longitude + (s['dLon'] as double);
      final sName = s['name'] as String;
      final meltEra = s['meltEra'] as ClimateEra;
      if (era.index <= meltEra.index) {
        sb.writeln(LG3DVisuals.build3DGlacialSpire(
          centerLat: sLat,
          centerLon: sLon,
          spanDeg: span,
          heightMeters: baseHeight,
          face1ColorAbgr: 'cceedd00',
          face2ColorAbgr: 'ccffffcc',
          face3ColorAbgr: 'cc00f0ff',
          face4ColorAbgr: 'ccd0e0ff',
          wireColorAbgr: 'ffffffff',
          name: '$sName — Intact Ice Spire',
          description: 'Glacial Ice Volume (${era.label})',
        ));
      }
    }

    return sb.toString();
  }

  String _seaLevel3DShape(ClimateRegion region, ClimateEra era, Map<String, String> eraStats) {
    final sb = StringBuffer();

    if (region.id == 'pacific') {
      final aquifers = [
        {'name': 'Outer Fongafale Atoll Lens', 'dLat': -0.45, 'dLon': 0.30, 'dryEra': ClimateEra.midCentury1950},
        {'name': 'South Nanumea Aquifer Well', 'dLat': -0.50, 'dLon': -0.34, 'dryEra': ClimateEra.midCentury1950},
        {'name': 'Eastern Tarawa Lagoon Well', 'dLat': -0.36, 'dLon': 0.46, 'dryEra': ClimateEra.midCentury1950},
        {'name': 'Southwest Coral Cay Lens', 'dLat': -0.30, 'dLon': -0.48, 'dryEra': ClimateEra.midCentury1950},
        {'name': 'Betio Groundwater Basin', 'dLat': 0.20, 'dLon': -0.38, 'dryEra': ClimateEra.lateCentury1980},
        {'name': 'Funafuti Northern Aquifer', 'dLat': 0.16, 'dLon': 0.42, 'dryEra': ClimateEra.lateCentury1980},
        {'name': 'Majuro Western Lens Reserve', 'dLat': 0.35, 'dLon': 0.12, 'dryEra': ClimateEra.lateCentury1980},
        {'name': 'Southern Atoll Wellfield', 'dLat': -0.18, 'dLon': -0.28, 'dryEra': ClimateEra.lateCentury1980},
        {'name': 'Central Laura Freshwater Lens', 'dLat': -0.10, 'dLon': -0.30, 'dryEra': ClimateEra.present2026},
        {'name': 'Bonriki Aquifer Sanctuary', 'dLat': 0.26, 'dLon': 0.22, 'dryEra': ClimateEra.present2026},
        {'name': 'Kiritimati North Water Well', 'dLat': -0.22, 'dLon': 0.15, 'dryEra': ClimateEra.present2026},
        {'name': 'Main Island Elevated Water Table', 'dLat': 0.08, 'dLon': 0.14, 'dryEra': ClimateEra.midProjection2060},
        {'name': 'Abaiang Protected Lens Reserve', 'dLat': 0.28, 'dLon': -0.16, 'dryEra': ClimateEra.midProjection2060},
        {'name': 'Tuvalu Deep Groundwater Hub', 'dLat': -0.24, 'dLon': 0.05, 'dryEra': ClimateEra.midProjection2060},
        {'name': 'Inner Causeway Aquifer Pocket', 'dLat': 0.12, 'dLon': -0.06, 'dryEra': ClimateEra.projected2100},
        {'name': 'Central Fortified Aquifer Vault', 'dLat': 0.0, 'dLon': 0.0, 'dryEra': ClimateEra.projected2100},
      ];

      const baseHeight = 30000.0;
      const radius = 0.090;

      for (final a in aquifers) {
        final aLat = region.latitude + (a['dLat'] as double);
        final aLon = region.longitude + (a['dLon'] as double);
        final aName = a['name'] as String;
        final dryEra = a['dryEra'] as ClimateEra;
        if (era.index <= dryEra.index) {
          sb.writeln(LG3DVisuals.build3DHexagonalPrism(
            centerLat: aLat,
            centerLon: aLon,
            radiusDeg: radius,
            heightMeters: baseHeight,
            topColorAbgr: 'ee10b981',
            sideColorAbgr: 'cc00e5ff',
            wireColorAbgr: 'ff00f0ff',
            name: '$aName — Freshwater Aquifer Lens',
            description: 'Potable Freshwater Groundwater Lens (${era.label})',
          ));
        }
      }
    } else {
      final tiers = switch (era) {
        ClimateEra.preindustrial1900 => [3000.0],
        ClimateEra.midCentury1950    => [4000.0, 8000.0],
        ClimateEra.lateCentury1980   => [5000.0, 10000.0, 15000.0],
        ClimateEra.present2026       => [6000.0, 12000.0, 18000.0, 24000.0],
        ClimateEra.midProjection2060 => [7000.0, 14000.0, 21000.0, 28000.0, 35000.0],
        ClimateEra.projected2100     => [8000.0, 16000.0, 24000.0, 32000.0, 40000.0, 48000.0],
      };

      final radius = switch (era) {
        ClimateEra.preindustrial1900 => 0.18,
        ClimateEra.midCentury1950    => 0.24,
        ClimateEra.lateCentury1980   => 0.30,
        ClimateEra.present2026       => 0.38,
        ClimateEra.midProjection2060 => 0.46,
        ClimateEra.projected2100     => 0.55,
      };

      sb.writeln(LG3DVisuals.build3DSteppedWaterPlanes(
        centerLat: region.latitude,
        centerLon: region.longitude,
        radiusDeg: radius,
        tierAltitudes: tiers,
        waterColorAbgr: 'aa0284c7',
        crestColorAbgr: 'ff38bdf8',
        name: '3D Sea Level Inundation Slices — ${era.label}',
        description: 'Progressive Bathymetric Flood Levels (${era.label})',
      ));
    }

    return sb.toString();
  }

  String _forest3DShape(ClimateRegion region, ClimateEra era, Map<String, String> eraStats) {
    final sb = StringBuffer();
    final sectors = [
      {'name': 'Rondônia South Frontier', 'dLat': -0.45, 'dLon': -0.40, 'deathEra': ClimateEra.midCentury1950},
      {'name': 'Mato Grosso Southern Edge', 'dLat': -0.50, 'dLon': 0.35, 'deathEra': ClimateEra.midCentury1950},
      {'name': 'Pará Southeastern Timber Belt', 'dLat': -0.38, 'dLon': 0.48, 'deathEra': ClimateEra.midCentury1950},
      {'name': 'Guaporé Basin Clearing Arc', 'dLat': -0.32, 'dLon': -0.50, 'deathEra': ClimateEra.midCentury1950},
      {'name': 'BR-163 Highway Logging Arc', 'dLat': -0.22, 'dLon': 0.20, 'deathEra': ClimateEra.lateCentury1980},
      {'name': 'Eastern Pará Timber Sector', 'dLat': 0.20, 'dLon': 0.44, 'deathEra': ClimateEra.lateCentury1980},
      {'name': 'Acre Western Agricultural Frontier', 'dLat': -0.26, 'dLon': -0.42, 'deathEra': ClimateEra.lateCentury1980},
      {'name': 'Purus River Clearance Belt', 'dLat': -0.14, 'dLon': -0.25, 'deathEra': ClimateEra.lateCentury1980},
      {'name': 'Tapajós River Logging Sector', 'dLat': 0.26, 'dLon': 0.24, 'deathEra': ClimateEra.present2026},
      {'name': 'Xingu Basin Deforestation Sector', 'dLat': -0.16, 'dLon': 0.36, 'deathEra': ClimateEra.present2026},
      {'name': 'Madeira River Valley Canopy', 'dLat': 0.06, 'dLon': -0.20, 'deathEra': ClimateEra.present2026},
      {'name': 'Amapá Coastal Forest Transition', 'dLat': 0.40, 'dLon': 0.30, 'deathEra': ClimateEra.midProjection2060},
      {'name': 'Roraima Northern Savanna Boundary', 'dLat': 0.44, 'dLon': -0.16, 'deathEra': ClimateEra.midProjection2060},
      {'name': 'Negro River Rainforest Preserve', 'dLat': 0.24, 'dLon': -0.06, 'deathEra': ClimateEra.midProjection2060},
      {'name': 'Juruá Deep Wilderness Sector', 'dLat': 0.16, 'dLon': -0.34, 'deathEra': ClimateEra.projected2100},
      {'name': 'Central Manaus Primary Sanctuary', 'dLat': 0.0, 'dLon': 0.0, 'deathEra': ClimateEra.projected2100},
    ];

    const baseHeight = 38000.0;
    const radius = 0.095;

    for (final s in sectors) {
      final sLat = region.latitude + (s['dLat'] as double);
      final sLon = region.longitude + (s['dLon'] as double);
      final sName = s['name'] as String;
      final deathEra = s['deathEra'] as ClimateEra;
      if (era.index <= deathEra.index) {
        sb.writeln(LG3DVisuals.build3DHexagonalPrism(
          centerLat: sLat,
          centerLon: sLon,
          radiusDeg: radius,
          heightMeters: baseHeight,
          topColorAbgr: 'ee16a34a',
          sideColorAbgr: 'cc22c55e',
          wireColorAbgr: 'ff4ade80',
          name: '$sName — Intact Canopy Cell',
          description: 'Living Forest Canopy Structure (${era.label})',
        ));
      }
    }

    return sb.toString();
  }

  String _aqi3DShape(ClimateRegion region, ClimateEra era, Map<String, String> eraStats) {
    final sb = StringBuffer();

    final color = switch (era) {
      ClimateEra.preindustrial1900 => 'aa33cc44',
      ClimateEra.midCentury1950    => 'aa55ddaa',
      ClimateEra.lateCentury1980   => 'aafacc15',
      ClimateEra.present2026       => 'ccf97316',
      ClimateEra.midProjection2060 => 'dd0000ff',
      ClimateEra.projected2100     => 'ee990099',
    };

    final h = switch (era) {
      ClimateEra.preindustrial1900 => 14000.0,
      ClimateEra.midCentury1950    => 22000.0,
      ClimateEra.lateCentury1980   => 30000.0,
      ClimateEra.present2026       => 40000.0,
      ClimateEra.midProjection2060 => 50000.0,
      ClimateEra.projected2100     => 60000.0,
    };

    final baseRadius = switch (era) {
      ClimateEra.preindustrial1900 => 0.03,
      ClimateEra.midCentury1950    => 0.05,
      ClimateEra.lateCentury1980   => 0.07,
      ClimateEra.present2026       => 0.09,
      ClimateEra.midProjection2060 => 0.11,
      ClimateEra.projected2100     => 0.14,
    };

    final topRadius = switch (era) {
      ClimateEra.preindustrial1900 => 0.08,
      ClimateEra.midCentury1950    => 0.12,
      ClimateEra.lateCentury1980   => 0.18,
      ClimateEra.present2026       => 0.24,
      ClimateEra.midProjection2060 => 0.30,
      ClimateEra.projected2100     => 0.38,
    };
    sb.writeln(LG3DVisuals.build3DInvertedSmogFunnel(
      centerLat: region.latitude,
      centerLon: region.longitude,
      baseRadiusDeg: baseRadius,
      topRadiusDeg: topRadius,
      heightMeters: h,
      funnelColorAbgr: color,
      topRimColorAbgr: 'ffff8800',
      name: '3D Atmospheric Inversion Funnel — ${era.label}',
      description: 'Particulate Accumulation & Smog Column (${era.label})',
    ));

    return sb.toString();
  }

  /// Returns a KML <TimeSpan> element so Google Earth's timeline slider
  /// toggles visibility of each era's geometry, labels, and data bars.
  String _timeSpanKml(ClimateEra era) => switch (era) {
    ClimateEra.preindustrial1900 => '<TimeSpan><begin>1850-01-01T00:00:00Z</begin><end>1924-12-31T23:59:59Z</end></TimeSpan>',
    ClimateEra.midCentury1950    => '<TimeSpan><begin>1925-01-01T00:00:00Z</begin><end>1964-12-31T23:59:59Z</end></TimeSpan>',
    ClimateEra.lateCentury1980   => '<TimeSpan><begin>1965-01-01T00:00:00Z</begin><end>1999-12-31T23:59:59Z</end></TimeSpan>',
    ClimateEra.present2026       => '<TimeSpan><begin>2000-01-01T00:00:00Z</begin><end>2049-12-31T23:59:59Z</end></TimeSpan>',
    ClimateEra.midProjection2060 => '<TimeSpan><begin>2050-01-01T00:00:00Z</begin><end>2084-12-31T23:59:59Z</end></TimeSpan>',
    ClimateEra.projected2100     => '<TimeSpan><begin>2085-01-01T00:00:00Z</begin><end>2150-12-31T23:59:59Z</end></TimeSpan>',
  };





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
    try {
      final uname = await execute('uname -a');
      sb.writeln('🐧 OS Info: ${uname.trim()}');
    } catch (e) {
      sb.writeln('🐧 OS Info Check Failed: $e');
    }
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
      print(extra);
    } catch (e) {
      sb.writeln('Failed to execute process check: $e');
    }
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

  /// Quick targeted verification of the KML delivery pipeline.
  /// Returns a map with 'ok' (bool) and 'details' (String) for each step.
  Future<Map<String, String>> verifyKmlDelivery() async {
    if (_client == null) return {'error': 'Not connected'};

    final results = <String, String>{};
    final port = _state.webPort;
    try {
      final ls = await execute('ls -la $_kmlDir/ 2>&1');
      results['1_kml_dir'] = ls.trim().isEmpty ? '❌ EMPTY' : '✅ Files exist:\n$ls';
    } catch (e) {
      results['1_kml_dir'] = '❌ ERROR: $e';
    }
    try {
      final content = await execute('cat $_kmlSyncFile 2>&1 | head -c 500');
      if (content.contains('<?xml') || content.contains('<kml')) {
        results['2_kmls_txt'] = '✅ Valid KML content (${content.length} chars):\n${content.substring(0, content.length.clamp(0, 200))}...';
      } else if (content.trim().isEmpty) {
        results['2_kmls_txt'] = '❌ FILE IS EMPTY — GE has nothing to render';
      } else {
        results['2_kmls_txt'] = '⚠️ Non-KML content:\n${content.substring(0, content.length.clamp(0, 200))}';
      }
    } catch (e) {
      results['2_kmls_txt'] = '❌ ERROR reading: $e';
    }
    try {
      final curlResult = await execute('curl -s -w "\\nHTTP_CODE:%{http_code}" http://localhost:$port/kmls.txt 2>&1 | tail -5');
      if (curlResult.contains('HTTP_CODE:200')) {
        results['3_web_server'] = '✅ Web server serves kmls.txt on port $port';
      } else if (curlResult.contains('HTTP_CODE:404')) {
        results['3_web_server'] = '❌ 404 NOT FOUND — file missing from web root';
      } else if (curlResult.contains('HTTP_CODE:403')) {
        results['3_web_server'] = '❌ 403 FORBIDDEN — permission issue';
      } else {
        results['3_web_server'] = '⚠️ Unexpected response:\n$curlResult';
      }
    } catch (e) {
      results['3_web_server'] = '❌ curl failed: $e';
    }
    try {
      final places = await execute(
        'cat /home/lg/.googleearth/myplaces.kml 2>/dev/null || '
        'cat /home/lg/.googleearth/MyPlaces.kml 2>/dev/null || '
        'cat /home/lg/.local/share/Google/GoogleEarth/myplaces.kml 2>/dev/null || '
        'cat /home/lg/.local/share/Google/GoogleEarth/MyPlaces.kml 2>/dev/null || '
        'echo "NOT_FOUND"'
      );
      if (places.contains('NOT_FOUND')) {
        results['4_myplaces'] = '❌ MyPlaces.kml NOT FOUND at any known path';
      } else if (places.contains('kmls.txt')) {
        results['4_myplaces'] = '✅ NetworkLink pointing to kmls.txt found';
      } else if (places.contains('NetworkLink')) {
        results['4_myplaces'] = '⚠️ NetworkLink exists but does NOT point to kmls.txt:\n${places.substring(0, places.length.clamp(0, 300))}';
      } else {
        results['4_myplaces'] = '❌ NO NetworkLink in MyPlaces.kml — GE never polls for KML';
      }
    } catch (e) {
      results['4_myplaces'] = '❌ ERROR: $e';
    }
    try {
      final ps = await execute('ps -eo user,pid,cmd | grep -E "google-earth|googleearth-bin" | grep -v grep || echo "NOT_RUNNING"');
      final whoami = await execute('whoami');
      final homeDir = await execute('echo \$HOME');
      if (ps.contains('NOT_RUNNING')) {
        results['5_ge_running'] = '❌ Google Earth is NOT running (SSH User: ${whoami.trim()})';
      } else {
        results['5_ge_running'] = '✅ Google Earth is running:\n${ps.trim()}\nSSH User: ${whoami.trim()}\nSSH Home: ${homeDir.trim()}';
      }
    } catch (e) {
      results['5_ge_running'] = '⚠️ Check failed: $e';
    }
    try {
      final fetch = await execute('curl -s http://localhost:$port/kmls.txt 2>&1 | head -c 200');
      results['6_ge_would_see'] = 'What GE polls every 2s:\n$fetch';
    } catch (e) {
      results['6_ge_would_see'] = 'Could not fetch: $e';
    }

    return results;
  }

  void _update(LGRigState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  void dispose() {
    _keepaliveTimer?.cancel();
    _sftp?.close();
    _sftp = null;
    _stateCtrl.close();
  }
}







class LG3DVisuals {
  static String escapeXmlText(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  LG3DVisuals._();

  /// Builds a multi-tiered 3D cylindrical tower with illuminated top cap,
  /// translucent side wall facets, and horizontal glowing wireframe rings
  /// (styled directly after Liquid Galaxy multi-tier cylindrical biomes).
  static String build3DCylinderTower({
    required double centerLat,
    required double centerLon,
    required double radiusDeg,
    required double heightMeters,
    int segments = 16,
    int tiers = 4,
    required String baseColorAbgr,
    required String topColorAbgr,
    required String wireColorAbgr,
    String name = '3D Cylindrical Tower',
    String description = '',
  }) {
    final sb = StringBuffer();
    sb.writeln('<Folder>');
    sb.writeln('  <name>${escapeXmlText(name)}</name>');
    sb.writeln('  <visibility>1</visibility>');
    sb.writeln('  <open>0</open>');
    if (description.isNotEmpty) {
      sb.writeln('  <description><![CDATA[$description]]></description>');
    }

    final tierHeight = heightMeters / tiers;
    final tierPoints = <List<String>>[];
    for (int t = 0; t <= tiers; t++) {
      final h = (t * tierHeight).toStringAsFixed(1);
      final ring = <String>[];
      for (int i = 0; i < segments; i++) {
        final angle = i * (math.pi * 2) / segments;
        final lat = centerLat + radiusDeg * math.sin(angle);
        final lon = centerLon + radiusDeg * math.cos(angle) / math.cos(centerLat * math.pi / 180);
        ring.add('${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)},$h');
      }
      tierPoints.add(ring);
    }
    for (int t = 0; t < tiers; t++) {
      final bottomRing = tierPoints[t];
      final topRing = tierPoints[t + 1];
      final tierColor = t == tiers - 1 ? topColorAbgr : baseColorAbgr;

      for (int i = 0; i < segments; i++) {
        final next = (i + 1) % segments;
        sb.writeln('''
      <Placemark>
        <name>Tower Tier ${t + 1} - Facet ${i + 1}</name>
        <Style>
          <PolyStyle><color>$tierColor</color><outline>1</outline></PolyStyle>
          <LineStyle><color>$wireColorAbgr</color><width>2.0</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            ${bottomRing[i]}
            ${bottomRing[next]}
            ${topRing[next]}
            ${topRing[i]}
            ${bottomRing[i]}
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>''');
      }
      final ringCoordinates = '${topRing.join(' ')} ${topRing[0]}';
      sb.writeln('''
      <Placemark>
        <name>Tier ${t + 1} Level Ring</name>
        <Style>
          <LineStyle><color>$wireColorAbgr</color><width>3.0</width></LineStyle>
        </Style>
        <LineString>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <coordinates>$ringCoordinates</coordinates>
        </LineString>
      </Placemark>''');
    }
    final topRing = tierPoints.last;
    final topCoordinates = '${topRing.join(' ')} ${topRing[0]}';
    sb.writeln('''
    <Placemark>
      <name>Tower Top Cap</name>
      <Style>
        <PolyStyle><color>$topColorAbgr</color><outline>1</outline></PolyStyle>
        <LineStyle><color>$wireColorAbgr</color><width>2.5</width></LineStyle>
      </Style>
      <Polygon>
        <tessellate>0</tessellate>
        <altitudeMode>relativeToGround</altitudeMode>
        <outerBoundaryIs><LinearRing><coordinates>$topCoordinates</coordinates></LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>''');

    sb.writeln('</Folder>');
    return sb.toString();
  }

  /// Builds a multi-faceted 3D crystalline / glacial pyramid with directional sunlight face shading.
  static String build3DGlacialSpire({
    required double centerLat,
    required double centerLon,
    required double spanDeg,
    required double heightMeters,
    required String face1ColorAbgr,
    required String face2ColorAbgr,
    required String face3ColorAbgr,
    required String face4ColorAbgr,
    String wireColorAbgr = 'ffffffff',
    String name = '3D Glacial Spire',
    String description = '',
  }) {
    final half = spanDeg / 2;
    final sw = '${(centerLon - half).toStringAsFixed(6)},${(centerLat - half).toStringAsFixed(6)},0';
    final se = '${(centerLon + half).toStringAsFixed(6)},${(centerLat - half).toStringAsFixed(6)},0';
    final ne = '${(centerLon + half).toStringAsFixed(6)},${(centerLat + half).toStringAsFixed(6)},0';
    final nw = '${(centerLon - half).toStringAsFixed(6)},${(centerLat + half).toStringAsFixed(6)},0';

    final h = heightMeters.toStringAsFixed(1);
    final peak = '${centerLon.toStringAsFixed(6)},${centerLat.toStringAsFixed(6)},$h';

    return '''
    <Folder>
      <name>${escapeXmlText(name)}</name>
      <visibility>1</visibility>
      <open>0</open>
      ${description.isNotEmpty ? '<description><![CDATA[$description]]></description>' : ''}

      <!-- South Face -->
      <Placemark>
        <name>Glacial Peak South Face</name>
        <Style>
          <PolyStyle><color>$face1ColorAbgr</color><outline>1</outline></PolyStyle>
          <LineStyle><color>$wireColorAbgr</color><width>2.5</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $sw $se $peak $sw
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>

      <!-- East Face -->
      <Placemark>
        <name>Glacial Peak East Face</name>
        <Style>
          <PolyStyle><color>$face2ColorAbgr</color><outline>1</outline></PolyStyle>
          <LineStyle><color>$wireColorAbgr</color><width>2.5</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $se $ne $peak $se
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>

      <!-- North Face -->
      <Placemark>
        <name>Glacial Peak North Face</name>
        <Style>
          <PolyStyle><color>$face3ColorAbgr</color><outline>1</outline></PolyStyle>
          <LineStyle><color>$wireColorAbgr</color><width>2.5</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $ne $nw $peak $ne
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>

      <!-- West Face -->
      <Placemark>
        <name>Glacial Peak West Face</name>
        <Style>
          <PolyStyle><color>$face4ColorAbgr</color><outline>1</outline></PolyStyle>
          <LineStyle><color>$wireColorAbgr</color><width>2.5</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $nw $sw $peak $nw
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>
    </Folder>''';
  }

  /// Builds a multi-faceted 3D geodesic thermal dome / cone with expanding radiation tiers.
  static String build3DGeodesicDome({
    required double centerLat,
    required double centerLon,
    required double radiusDeg,
    required double heightMeters,
    int segments = 12,
    required List<String> faceColorsAbgr,
    String wireColorAbgr = 'ffffaa00',
    String name = '3D Thermal Dome',
    String description = '',
  }) {
    final pointsG = <String>[];
    final h = heightMeters.toStringAsFixed(1);
    final peak = '${centerLon.toStringAsFixed(6)},${centerLat.toStringAsFixed(6)},$h';

    for (int i = 0; i < segments; i++) {
      final angle = i * (math.pi * 2) / segments;
      final lat = centerLat + radiusDeg * math.sin(angle);
      final lon = centerLon + radiusDeg * math.cos(angle) / math.cos(centerLat * math.pi / 180);
      pointsG.add('${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)},0');
    }

    final sb = StringBuffer();
    sb.writeln('<Folder>');
    sb.writeln('  <name>${escapeXmlText(name)}</name>');
    sb.writeln('  <visibility>1</visibility>');
    sb.writeln('  <open>0</open>');
    if (description.isNotEmpty) {
      sb.writeln('  <description><![CDATA[$description]]></description>');
    }

    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      final color = faceColorsAbgr[i % faceColorsAbgr.length];
      sb.writeln('''
      <Placemark>
        <name>Dome Panel ${i + 1}</name>
        <Style>
          <PolyStyle><color>$color</color><outline>1</outline></PolyStyle>
          <LineStyle><color>$wireColorAbgr</color><width>2.5</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            ${pointsG[i]}
            ${pointsG[next]}
            $peak
            ${pointsG[i]}
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>''');
    }

    sb.writeln('</Folder>');
    return sb.toString();
  }

  /// 1. Builds a true 6-sided 3D Hexagonal Prism (Rainforest Canopy Cell).
  static String build3DHexagonalPrism({
    required double centerLat,
    required double centerLon,
    required double radiusDeg,
    required double heightMeters,
    required String topColorAbgr,
    required String sideColorAbgr,
    required String wireColorAbgr,
    String name = '3D Hexagonal Canopy Prism',
    String description = '',
  }) {
    final sb = StringBuffer();
    sb.writeln('<Folder>');
    sb.writeln('  <name>${escapeXmlText(name)}</name>');
    sb.writeln('  <visibility>1</visibility>');
    sb.writeln('  <open>0</open>');
    if (description.isNotEmpty) {
      sb.writeln('  <description><![CDATA[$description]]></description>');
    }

    final h = heightMeters.toStringAsFixed(1);
    final bottomPoints = <String>[];
    final topPoints = <String>[];
    const sides = 6;

    for (int i = 0; i < sides; i++) {
      final angle = i * (math.pi / 3);
      final lat = centerLat + radiusDeg * math.sin(angle);
      final lon = centerLon + radiusDeg * math.cos(angle) / math.cos(centerLat * math.pi / 180);
      bottomPoints.add('${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)},0');
      topPoints.add('${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)},$h');
    }
    for (int i = 0; i < sides; i++) {
      final next = (i + 1) % sides;
      sb.writeln('''
      <Placemark>
        <name>Hex Facet ${i + 1}</name>
        <Style>
          <PolyStyle><color>$sideColorAbgr</color><outline>1</outline></PolyStyle>
          <LineStyle><color>$wireColorAbgr</color><width>2.0</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            ${bottomPoints[i]}
            ${bottomPoints[next]}
            ${topPoints[next]}
            ${topPoints[i]}
            ${bottomPoints[i]}
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>''');
    }
    final topCoords = '${topPoints.join(' ')} ${topPoints[0]}';
    sb.writeln('''
    <Placemark>
      <name>Hexagonal Canopy Roof</name>
      <Style>
        <PolyStyle><color>$topColorAbgr</color><outline>1</outline></PolyStyle>
        <LineStyle><color>$wireColorAbgr</color><width>3.0</width></LineStyle>
      </Style>
      <Polygon>
        <tessellate>0</tessellate>
        <altitudeMode>relativeToGround</altitudeMode>
        <outerBoundaryIs><LinearRing><coordinates>$topCoords</coordinates></LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>''');

    sb.writeln('</Folder>');
    return sb.toString();
  }

  /// 2. Builds multi-level horizontal stepped water planes / bathymetric flood slabs (NO cylinders!).
  static String build3DSteppedWaterPlanes({
    required double centerLat,
    required double centerLon,
    required double radiusDeg,
    required List<double> tierAltitudes,
    required String waterColorAbgr,
    required String crestColorAbgr,
    String name = '3D Stepped Water Inundation Slices',
    String description = '',
  }) {
    final sb = StringBuffer();
    sb.writeln('<Folder>');
    sb.writeln('  <name>${escapeXmlText(name)}</name>');
    sb.writeln('  <visibility>1</visibility>');
    sb.writeln('  <open>0</open>');
    if (description.isNotEmpty) {
      sb.writeln('  <description><![CDATA[$description]]></description>');
    }

    const segments = 24;
    for (int t = 0; t < tierAltitudes.length; t++) {
      final alt = tierAltitudes[t];
      final r = radiusDeg * (1.0 + t * 0.25);
      final altStr = alt.toStringAsFixed(1);
      final ring = <String>[];

      for (int i = 0; i < segments; i++) {
        final angle = i * (math.pi * 2) / segments;
        final lat = centerLat + r * math.sin(angle);
        final lon = centerLon + r * math.cos(angle) / math.cos(centerLat * math.pi / 180);
        ring.add('${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)},$altStr');
      }
      final planeCoords = '${ring.join(' ')} ${ring[0]}';

      sb.writeln('''
      <Placemark>
        <name>Inundation Surge Slab ${t + 1} (+${(alt / 1000).toStringAsFixed(1)}km surge)</name>
        <Style>
          <PolyStyle><color>$waterColorAbgr</color><outline>1</outline></PolyStyle>
          <LineStyle><color>$crestColorAbgr</color><width>3.0</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>$planeCoords</coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>''');
    }

    sb.writeln('</Folder>');
    return sb.toString();
  }

  /// 3. Builds an inverted 3D Smog Funnel / Tornado (narrow at base, flared at ceiling).
  static String build3DInvertedSmogFunnel({
    required double centerLat,
    required double centerLon,
    required double baseRadiusDeg,
    required double topRadiusDeg,
    required double heightMeters,
    required String funnelColorAbgr,
    required String topRimColorAbgr,
    int segments = 12,
    String name = '3D Atmospheric Smog Funnel',
    String description = '',
  }) {
    final sb = StringBuffer();
    sb.writeln('<Folder>');
    sb.writeln('  <name>${escapeXmlText(name)}</name>');
    sb.writeln('  <visibility>1</visibility>');
    sb.writeln('  <open>0</open>');
    if (description.isNotEmpty) {
      sb.writeln('  <description><![CDATA[$description]]></description>');
    }

    final h = heightMeters.toStringAsFixed(1);
    final basePoints = <String>[];
    final topPoints = <String>[];

    for (int i = 0; i < segments; i++) {
      final angle = i * (math.pi * 2) / segments;
      final bLat = centerLat + baseRadiusDeg * math.sin(angle);
      final bLon = centerLon + baseRadiusDeg * math.cos(angle) / math.cos(centerLat * math.pi / 180);
      final tLat = centerLat + topRadiusDeg * math.sin(angle);
      final tLon = centerLon + topRadiusDeg * math.cos(angle) / math.cos(centerLat * math.pi / 180);
      basePoints.add('${bLon.toStringAsFixed(6)},${bLat.toStringAsFixed(6)},0');
      topPoints.add('${tLon.toStringAsFixed(6)},${tLat.toStringAsFixed(6)},$h');
    }
    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      sb.writeln('''
      <Placemark>
        <name>Smog Funnel Wall ${i + 1}</name>
        <Style>
          <PolyStyle><color>$funnelColorAbgr</color><outline>1</outline></PolyStyle>
          <LineStyle><color>$topRimColorAbgr</color><width>1.5</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            ${basePoints[i]}
            ${basePoints[next]}
            ${topPoints[next]}
            ${topPoints[i]}
            ${basePoints[i]}
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>''');
    }
    final topCoords = '${topPoints.join(' ')} ${topPoints[0]}';
    sb.writeln('''
    <Placemark>
      <name>Thermal Inversion Ceiling</name>
      <Style>
        <PolyStyle><color>$funnelColorAbgr</color><outline>1</outline></PolyStyle>
        <LineStyle><color>$topRimColorAbgr</color><width>3.0</width></LineStyle>
      </Style>
      <Polygon>
        <tessellate>0</tessellate>
        <altitudeMode>relativeToGround</altitudeMode>
        <outerBoundaryIs><LinearRing><coordinates>$topCoords</coordinates></LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>''');

    sb.writeln('</Folder>');
    return sb.toString();
  }

  /// Builds a stepped 3D marine inundation slice collection (replaces round cylinders).
  static String build3DMarineSubmergenceColumn({
    required double centerLat,
    required double centerLon,
    required double radiusDeg,
    required double heightMeters,
    int tiers = 3,
    required String waterColorAbgr,
    required String crestColorAbgr,
    String name = '3D Marine Inundation Slices',
    String description = '',
  }) {
    final altitudes = <double>[];
    for (int t = 1; t <= tiers; t++) {
      altitudes.add(heightMeters * (t / tiers));
    }
    return build3DSteppedWaterPlanes(
      centerLat: centerLat,
      centerLon: centerLon,
      radiusDeg: radiusDeg,
      tierAltitudes: altitudes,
      waterColorAbgr: waterColorAbgr,
      crestColorAbgr: crestColorAbgr,
      name: name,
      description: description,
    );
  }

  /// Builds an inverted 3D AQI smog funnel / tornado (replaces straight round cylinders).
  static String build3DAqiSmogPillar({
    required double centerLat,
    required double centerLon,
    required double radiusDeg,
    required double heightMeters,
    required double pm25,
    required String severityColorAbgr,
    String name = '3D AQI Smog Funnel',
    String description = '',
  }) {
    return build3DInvertedSmogFunnel(
      centerLat: centerLat,
      centerLon: centerLon,
      baseRadiusDeg: radiusDeg * 0.35,
      topRadiusDeg: radiusDeg * 1.3,
      heightMeters: heightMeters,
      funnelColorAbgr: severityColorAbgr,
      topRimColorAbgr: 'ffff8800',
      name: name,
      description: description,
    );
  }

  /// Builds an elevated 3D sensor beacon spire for localized sub-stations.
  static String build3DSensorBeacon({
    required double centerLat,
    required double centerLon,
    required double radiusDeg,
    required double heightMeters,
    required String beaconColorAbgr,
    String name = '3D Sensor Beacon',
    String description = '',
  }) {
    final h = heightMeters.toStringAsFixed(1);
    final halfH = (heightMeters * 0.55).toStringAsFixed(1);
    final topPeak = '${centerLon.toStringAsFixed(6)},${centerLat.toStringAsFixed(6)},$h';
    final groundBase = '${centerLon.toStringAsFixed(6)},${centerLat.toStringAsFixed(6)},0';

    final ringPoints = <String>[];
    const segments = 6;
    for (int i = 0; i < segments; i++) {
      final angle = i * (math.pi * 2) / segments;
      final lat = centerLat + radiusDeg * math.sin(angle);
      final lon = centerLon + radiusDeg * math.cos(angle) / math.cos(centerLat * math.pi / 180);
      ringPoints.add('${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)},$halfH');
    }

    final sb = StringBuffer();
    sb.writeln('<Folder>');
    sb.writeln('  <name>${escapeXmlText(name)}</name>');
    sb.writeln('  <visibility>1</visibility>');
    sb.writeln('  <open>0</open>');
    if (description.isNotEmpty) {
      sb.writeln('  <description><![CDATA[$description]]></description>');
    }
    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      sb.writeln('''
      <Placemark>
        <name>Beacon Diamond Upper ${i + 1}</name>
        <Style>
          <PolyStyle><color>$beaconColorAbgr</color><outline>1</outline></PolyStyle>
          <LineStyle><color>ffffffff</color><width>1.8</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            ${ringPoints[i]}
            ${ringPoints[next]}
            $topPeak
            ${ringPoints[i]}
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>''');
      sb.writeln('''
      <Placemark>
        <name>Beacon Diamond Lower ${i + 1}</name>
        <Style>
          <PolyStyle><color>$beaconColorAbgr</color><outline>1</outline></PolyStyle>
          <LineStyle><color>ffffffff</color><width>1.8</width></LineStyle>
        </Style>
        <Polygon>
          <tessellate>0</tessellate>
          <altitudeMode>relativeToGround</altitudeMode>
          <outerBoundaryIs><LinearRing><coordinates>
            $groundBase
            ${ringPoints[next]}
            ${ringPoints[i]}
            $groundBase
          </coordinates></LinearRing></outerBoundaryIs>
        </Polygon>
      </Placemark>''');
    }

    sb.writeln('</Folder>');
    return sb.toString();
  }

  /// Builds an elevated 3D connecting data telemetry / flight / migration corridor.
  static String build3DConnectingCorridor({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required double altitudeMeters,
    required String lineColorAbgr,
    double lineWidth = 3.5,
    String name = '3D Data Corridor',
    String description = '',
  }) {
    final altStr = altitudeMeters.toStringAsFixed(1);
    final coords = '${fromLon.toStringAsFixed(6)},${fromLat.toStringAsFixed(6)},$altStr ${toLon.toStringAsFixed(6)},${toLat.toStringAsFixed(6)},$altStr';

    return '''
    <Placemark>
      <name>${escapeXmlText(name)}</name>
      <visibility>1</visibility>
      ${description.isNotEmpty ? '<description><![CDATA[$description]]></description>' : ''}
      <Style>
        <LineStyle>
          <color>$lineColorAbgr</color>
          <width>$lineWidth</width>
        </LineStyle>
      </Style>
      <LineString>
        <extrude>1</extrude>
        <tessellate>1</tessellate>
        <altitudeMode>relativeToGround</altitudeMode>
        <coordinates>$coords</coordinates>
      </LineString>
    </Placemark>''';
  }

  /// Builds a 3D extruded polygonal territory zone with wall extrusion.
  static String build3DExtrudedTerritory({
    required String coordinates,
    required String fillColorAbgr,
    required String boundaryColorAbgr,
    double altitudeMeters = 5000.0,
    double lineWidth = 3.0,
    String name = '3D Extruded Territory',
    String description = '',
  }) {
    return '''
    <Placemark>
      <name>${escapeXmlText(name)}</name>
      <visibility>1</visibility>
      ${description.isNotEmpty ? '<description><![CDATA[$description]]></description>' : ''}
      <Style>
        <PolyStyle>
          <color>$fillColorAbgr</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>$boundaryColorAbgr</color>
          <width>$lineWidth</width>
        </LineStyle>
      </Style>
      <Polygon>
        <extrude>1</extrude>
        <tessellate>1</tessellate>
        <altitudeMode>relativeToGround</altitudeMode>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>$coordinates</coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  static String build3DMeshAndSpikes({
    required double centerLat,
    required double centerLon,
    required double spanDeg,
    required String category,
    required double severityFactor,
    String name = '3D Mesh & Hotspot Spikes',
  }) {
    final sb = StringBuffer();
    sb.writeln('<Folder><name>${escapeXmlText(name)}</name><visibility>1</visibility><open>1</open>');

    const rows = 4;
    const cols = 4;
    final cellLatSpan = spanDeg / rows;
    final cellLonSpan = spanDeg / cols;
    final startLat = centerLat - spanDeg / 2;
    final startLon = centerLon - spanDeg / 2;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final w = startLon + c * cellLonSpan;
        final e = w + cellLonSpan;
        final s = startLat + r * cellLatSpan;
        final n = s + cellLatSpan;

        final cellCenterLat = (s + n) / 2;
        final cellCenterLon = (w + e) / 2;

        final dist = math.sqrt(
          math.pow((cellCenterLat - centerLat) / spanDeg, 2) +
          math.pow((cellCenterLon - centerLon) / spanDeg, 2),
        );
        final cellSeverity = (severityFactor * (1.0 - dist * 0.6) + 0.12 * math.sin(r * 2.5 + c * 1.8)).clamp(0.08, 0.95);

        final polyColor = _getMeshColorAbgr(category, cellSeverity);
        final wireColor = _getWireframeColorAbgr(category, cellSeverity);
        final height = 8000.0 + cellSeverity * 115000.0;

        final hStr = height.toStringAsFixed(1);
        final swStr = '${w.toStringAsFixed(6)},${s.toStringAsFixed(6)},$hStr';
        final seStr = '${e.toStringAsFixed(6)},${s.toStringAsFixed(6)},$hStr';
        final neStr = '${e.toStringAsFixed(6)},${n.toStringAsFixed(6)},$hStr';
        final nwStr = '${w.toStringAsFixed(6)},${n.toStringAsFixed(6)},$hStr';

        sb.writeln('''
        <Placemark>
          <name>Mesh Zone (${r + 1},${c + 1})</name>
          <Style>
            <PolyStyle>
              <color>$polyColor</color>
              <outline>1</outline>
            </PolyStyle>
            <LineStyle>
              <color>$wireColor</color>
              <width>2.5</width>
            </LineStyle>
          </Style>
          <Polygon>
            <extrude>1</extrude>
            <tessellate>1</tessellate>
            <altitudeMode>relativeToGround</altitudeMode>
            <outerBoundaryIs>
              <LinearRing>
                <coordinates>
                  $swStr
                  $seStr
                  $neStr
                  $nwStr
                  $swStr
                </coordinates>
              </LinearRing>
            </outerBoundaryIs>
          </Polygon>
        </Placemark>
        ''');
      }
    }
    final hotspotOffsets = [
      {'dLat': 0.12,  'dLon': -0.12, 'scale': 1.0},
      {'dLat': -0.20, 'dLon': 0.18,  'scale': 0.85},
      {'dLat': 0.25,  'dLon': 0.15,  'scale': 0.72},
      {'dLat': -0.15, 'dLon': -0.22, 'scale': 0.65},
    ];

    for (int i = 0; i < hotspotOffsets.length; i++) {
      final hs = hotspotOffsets[i];
      final hsLat = centerLat + hs['dLat']! * spanDeg;
      final hsLon = centerLon + hs['dLon']! * spanDeg;
      final pSpan = cellLonSpan * 0.40;
      final peakHeight = 40000.0 + severityFactor * hs['scale']! * 130000.0;

      sb.writeln(build3DPyramid(
        centerLat: hsLat,
        centerLon: hsLon,
        spanDeg: pSpan,
        heightMeters: peakHeight,
        face1ColorAbgr: 'ff202020',
        face2ColorAbgr: 'ff383838',
        face3ColorAbgr: 'ff151515',
        face4ColorAbgr: 'ff484848',
        name: 'Hotspot Node ${i + 1}',
        description: '3D Environmental Sensor Spike Node',
      ));
    }

    sb.writeln('</Folder>');
    return sb.toString();
  }

  static String _getMeshColorAbgr(String category, double severity) {
    if (severity < 0.25) return '8833cc44';
    if (severity < 0.45) return '8855ddaa';
    if (severity < 0.65) return '8800ddee';
    if (severity < 0.82) return '880088ff';
    return '880000ff';
  }

  static String _getWireframeColorAbgr(String category, double severity) {
    if (severity < 0.25) return 'ffaaffaa';
    if (severity < 0.45) return 'ffffffaa';
    if (severity < 0.65) return 'ffffdd66';
    if (severity < 0.82) return 'ffff8800';
    return 'ffff0000';
  }

  static String wrapDocument({
    required String name,
    required String body,
    String description = '',
  }) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>${escapeXmlText(name)}</name>
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
    required List<String> faceColorsAbgr,
    String name = '3D Box',
    String description = '',
  }) {
    final half = spanDeg / 2;
    final swG = '${centerLon - half},${centerLat - half},0';
    final seG = '${centerLon + half},${centerLat - half},0';
    final neG = '${centerLon + half},${centerLat + half},0';
    final nwG = '${centerLon - half},${centerLat + half},0';

    final h = heightMeters.toStringAsFixed(1);
    final swT = '${centerLon - half},${centerLat - half},$h';
    final seT = '${centerLon + half},${centerLat - half},$h';
    final neT = '${centerLon + half},${centerLat + half},$h';
    final nwT = '${centerLon - half},${centerLat + half},$h';

    return '''
    <Folder>
      <name>${escapeXmlText(name)}</name>
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
    required List<String> sideColorsAbgr,
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
    sb.writeln('  <name>${escapeXmlText(name)}</name>');
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
    required List<String> faceColorsAbgr,
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
    sb.writeln('  <name>${escapeXmlText(name)}</name>');
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
    final sw = '${centerLon - half},${centerLat - half},0';
    final se = '${centerLon + half},${centerLat - half},0';
    final ne = '${centerLon + half},${centerLat + half},0';
    final nw = '${centerLon - half},${centerLat + half},0';
    final h = heightMeters.toStringAsFixed(1);
    final peak = '$centerLon,$centerLat,$h';

    return '''
    <Folder>
      <name>${escapeXmlText(name)}</name>
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