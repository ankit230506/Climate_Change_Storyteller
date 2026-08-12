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
  if (screenCount % 2 == 1) return screenCount; // 3 -> lg3, 5 -> lg5, 7 -> lg7
  return screenCount - 1;
}

/// Returns the 1-based physical screen number of the Right-Most screen
/// on a Liquid Galaxy rig with [screenCount] screens.
int getRightMostScreenNumber(int screenCount) {
  if (screenCount <= 1) return 1;
  if (screenCount == 2) return 1;
  if (screenCount % 2 == 1) return screenCount - 1; // 3 -> lg2, 5 -> lg4, 7 -> lg6
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

  static const _gibsBase = 'https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi';
  static const _noaaBase = 'https://www.ncei.noaa.gov/cdo-web/api/v2';
  static const String kLgLogoUrl =
      'https://blogger.googleusercontent.com/img/b/R29vZ2xl/AVvXsEgXmdNgBTXup6bdWew5RzgCmC9pPb7rK487CpiscWB2S8OlhwFHmeeACHIIjx4B5-Iv-t95mNUx0JhB_oATG3-Tq1gs8Uj0-Xb9Njye6rHtKKsnJQJlzZqJxMDnj_2TXX3eA5x6VSgc8aw/s320-rw/LOGO+LIQUID+GALAXY-sq1000-+OKnoline.png';

  // Oblique camera tilt so extruded/3D geometry is visible on screens
  static const double _default3DTilt = 60.0;
  static const double _default3DHeading = 30.0;

  static const Map<String, String> _gibsLayers = {
    'glacier':  'MODIS_Terra_NDSI_Snow_Cover',
    'sealevel': 'VIIRS_NOAA20_CorrectedReflectance_TrueColor',
    'forest':   'MODIS_Terra_NDVI_8Day',
    'heat':     'MODIS_Terra_Land_Surface_Temp_Day',
    'aqi':      'MODIS_Terra_Aerosol',
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

      // Open a persistent SFTP session for file uploads
      try {
        _sftp = await client.sftp();
      } catch (_) {
        // SFTP may fail on some setups; fall back to shell commands
        _sftp = null;
      }

      // Verify kml folder exists and is writable, create if not
      await execute('mkdir -p $_kmlDir');

      // Do the same for slave screens
      for (int i = 2; i <= screenCount; i++) {
        try {
          await execute(
            'sshpass -p $password ssh -o StrictHostKeyChecking=no '
            '$username@lg$i "mkdir -p $_kmlDir" 2>&1'
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

      // Set permissions on the KML directory
      await execute('sudo chown -R lg:lg $_kmlDir 2>/dev/null; '
          'chmod -R 755 $_kmlDir 2>/dev/null; '
          'chmod 755 /var/www/html 2>/dev/null');

      // Configure the NetworkLink in Google Earth's MyPlaces.kml
      try {
        await setupNetworkLink();
        await _sendInitialConnectionOverlays();
      } catch (e) {
        // ignore: avoid_print
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

  int? _pendingTimeQueryYear;
  double? _pendingTimeQueryLat;
  double? _pendingTimeQueryLon;
  double? _pendingTimeQueryAlt;
  bool _isSendingTimeQuery = false;

  /// Immediately sends a time command to Liquid Galaxy query.txt
  /// moving Google Earth's time slider clock in real-time (0ms latency).
  Future<void> sendTimeQuery(
    int year, {
    double? latitude,
    double? longitude,
    double? altitude,
  }) async {
    if (_client == null || !_state.isConnected) return;

    _pendingTimeQueryYear = year;
    _pendingTimeQueryLat = latitude;
    _pendingTimeQueryLon = longitude;
    _pendingTimeQueryAlt = altitude;

    if (_isSendingTimeQuery) return;
    _isSendingTimeQuery = true;

    try {
      while (_pendingTimeQueryYear != null) {
        final targetYear = _pendingTimeQueryYear!;
        final lat = _pendingTimeQueryLat ?? _lastFlyToLat ?? 28.6139;
        final lon = _pendingTimeQueryLon ?? _lastFlyToLon ?? 77.2090;
        final alt = _pendingTimeQueryAlt ?? _lastFlyToAlt ?? 45000.0;
        _pendingTimeQueryYear = null;

        final timeStr = '$targetYear-01-01T00:00:00Z';
        final endStr = '$targetYear-12-31T23:59:59Z';

        final flyStr =
            'flytoview=<LookAt xmlns:gx="http://www.google.com/kml/ext/2.2">'
            '<longitude>$lon</longitude>'
            '<latitude>$lat</latitude>'
            '<altitude>0</altitude>'
            '<heading>$_default3DHeading</heading>'
            '<tilt>$_default3DTilt</tilt>'
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

  // ── Bi-directional LG viewpoint synchronization stream ──────────────────
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
      // 1. Try XML tag format: <latitude>-3.4653</latitude>, <longitude>-62.2159</longitude>
      var latMatch = RegExp(r'<latitude>\s*([0-9.-]+)\s*</latitude>').firstMatch(queryText);
      var lonMatch = RegExp(r'<longitude>\s*([0-9.-]+)\s*</longitude>').firstMatch(queryText);
      var rangeMatch = RegExp(r'<range>\s*([0-9.-]+)\s*</range>').firstMatch(queryText);

      // 2. Try query param format: latitude=-3.4653, longitude=-62.2159
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

    // Automatically upload logo overlay asset to the LG web server
    final category = _extractCategoryFromFilename(kmlFilename);
    await _uploadOverlayAssets(category);

    final host = _state.ipAddress ?? 'localhost';
    final masterKmlFilename = 'master_$kmlFilename';
    final slaveKmlFilename = 'slave_$kmlFilename';

    if (kmlContent != null && kmlContent.isNotEmpty) {
      final masterContent = _stripBalloonVisibility(kmlContent);
      final slaveContent = _stripTimeSpans(kmlContent);

      await _sftpUpload('$_kmlDir/$kmlFilename', utf8.encode(masterContent));
      await _sftpUpload('$_kmlDir/$masterKmlFilename', utf8.encode(masterContent));
      await _sftpUpload('$_kmlDir/$slaveKmlFilename', utf8.encode(slaveContent));
    }

    final masterNetLinkKml = _buildNetworkLinkKml('http://$host:${_state.webPort}/kml/$masterKmlFilename');
    final slaveNetLinkKml = _buildNetworkLinkKml('http://$host:${_state.webPort}/kml/$slaveKmlFilename');

    final leftScreenIndex = getLeftMostScreenNumber(_state.screenCount);
    final masterScreenIndex = getMasterScreenNumber(_state.screenCount);
    final rightScreenIndex = getRightMostScreenNumber(_state.screenCount);

    for (int i = 1; i <= _state.screenCount; i++) {
      if (i == masterScreenIndex) {
        await _sftpUpload('$_kmlDir/kml_$i.kml', utf8.encode(masterNetLinkKml));
        await _sftpUpload('$_kmlDir/master.kml', utf8.encode(masterNetLinkKml));
      } else {
        await _sftpUpload('$_kmlDir/kml_$i.kml', utf8.encode(slaveNetLinkKml));
        await _sftpUpload('$_kmlDir/slave_$i.kml', utf8.encode(slaveNetLinkKml));
      }
    }

    if (kmlContent != null && kmlContent.isNotEmpty) {
      final sceneOnly = _stripScreenOverlays(kmlContent);
      final logoBlock = _extractScreenOverlay(kmlContent, 'lg_logo.png');

      final webPort = _state.webPort;
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

      for (int i = 1; i <= _state.screenCount; i++) {
        var screenKml = sceneOnly;

        if (i == masterScreenIndex) {
          // Master screen (Screen 1): Retains TimeSpan & gx:TimeStamp so the Time Slider GUI renders ONLY on LG Master!
          screenKml = _stripBalloonVisibility(screenKml);
        } else {
          // All slave screens (Screens 2+): Explicitly strip ALL TimeSpan and TimeStamp tags so no slider is ever rendered on slaves!
          screenKml = _stripTimeSpans(screenKml);
          if (i == leftScreenIndex) {
            screenKml = _stripPlacemarks(screenKml);
            screenKml = screenKml.replaceFirst('</Document>', '$effectiveLogoBlock</Document>');
          } else if (i == rightScreenIndex) {
            screenKml = _ensureBalloonVisibility(screenKml);
          } else {
            screenKml = _stripBalloonVisibility(screenKml);
          }
        }

        final screenBytes = utf8.encode(screenKml);
        await _sftpUpload('/var/www/html/kmls_$i.txt', screenBytes);
      }

      // Also upload a slave-sanitized version (without TimeSpans) to the legacy shared /var/www/html/kmls.txt
      // so if any slave node polls kmls.txt, it will NEVER display a time slider on the slave screen!
      final sharedSlaveKml = _stripTimeSpans(sceneOnly);
      await _sftpUpload(_kmlSyncFile, utf8.encode(sharedSlaveKml));
    } else {
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
        );
  }

  String _stripPlacemarks(String kml) {
    return kml.replaceAll(
      RegExp(r'<Placemark>.*?</Placemark>', dotAll: true),
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

  Future<void> _uploadOverlayAssets(String category) async {
    if (_client == null) return;
    try {
      final logoPng = await _fetchOrGenerateLgLogoPng();
      await _sftpUpload('$_kmlDir/lg_logo.png', logoPng);

      final legendPng = LGOverlays.createLegendPng(category);
      await _sftpUpload('$_kmlDir/legend_$category.png', legendPng);

      await execute("chmod 644 $_kmlDir/*.png 2>/dev/null");
    } catch (_) {}
  }

  // Uploads data to remotePath via SFTP or falls back to a base64 shell pipe.
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
        await execute('chmod 644 $remotePath 2>/dev/null');
        return;
      } catch (e) {
        // ignore: avoid_print
        print('SFTP upload failed for $remotePath: $e — falling back to shell');
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

    await execute('chmod 644 $remotePath 2>/dev/null');
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
    final targetAlt = altitude ?? _lastFlyToAlt ?? 45000.0;

    _lastFlyToLat = targetLat;
    _lastFlyToLon = targetLon;
    _lastFlyToAlt = targetAlt;

    _update(_state.copyWith(isOrbiting: true));

    // First fly to the target KML coordinate so Google Earth travels to destination
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

    // Wait until Google Earth's camera flight reaches the target KML coordinate
    if (flightDelay > Duration.zero) {
      await Future.delayed(flightDelay);
    }

    // Abort if orbit was stopped or disconnected while flying to coordinate
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

    // A minimal valid-but-empty KML document.  Writing an empty string or
    // blank line to the sync file causes Google Earth to reject it as
    // invalid XML and stop polling, so we use this instead.
    const emptyKml =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<kml xmlns="http://www.opengis.net/kml/2.2">'
        '<Document><name>Empty</name></Document></kml>';
    final emptyBytes = utf8.encode(emptyKml);

    // Clear KML files on master
    await execute("rm -f $_kmlDir/*.kml 2>&1");

    // Write empty-but-valid KML to sync files so GE keeps polling
    await _sftpUpload(_kmlSyncFile, emptyBytes);
    for (int i = 1; i <= _state.screenCount; i++) {
      await _sftpUpload('/var/www/html/kmls_$i.txt', emptyBytes);
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

    // 2. Set up Master Node (Screen 1) pointing to its OWN sync file,
    //    kmls_1.txt — not the shared kmls.txt. Every screen used to poll
    //    the exact same file, so every screen showed identical content
    //    (including the logo AND legend overlays stacked on every screen).
    //    Each screen now gets a distinct file so we can vary content
    //    per-screen (logo only on screen 1, legend only on the last screen).
    final masterLinkKml = _buildSyncPlacesKml('http://localhost:$port/kmls_1.txt');
    final masterBytes = utf8.encode(masterLinkKml);

    await execute('mkdir -p /home/lg/.googleearth /home/lg/.local/share/Google/GoogleEarth');

    // Use SFTP to write MyPlaces.kml on master — no shell escaping issues
    for (final path in [
      '/home/lg/.googleearth/MyPlaces.kml',
      '/home/lg/.googleearth/myplaces.kml',
      '/home/lg/.local/share/Google/GoogleEarth/MyPlaces.kml',
      '/home/lg/.local/share/Google/GoogleEarth/myplaces.kml',
    ]) {
      await _sftpUpload(path, masterBytes);
    }

    // 3. Set up Slave Nodes (Screen 2 to screenCount), each pointing to its
    //    OWN sync file http://$ip:$port/kmls_$i.txt (not the shared
    //    kmls.txt) so different screens can show different content.
    //    Strategy: write a slave KML per screen index to a temp file on the
    //    master, then scp it to each corresponding slave — this avoids all
    //    nested quoting issues.
    const slaveTmp = '/tmp/_cs_slave_myplaces.kml';

    for (int i = 2; i <= _state.screenCount; i++) {
      try {
        final slaveLinkKml = _buildSyncPlacesKml('http://$ip:$port/kmls_$i.txt');
        await _sftpUpload(slaveTmp, utf8.encode(slaveLinkKml));

        // Create target directories on slave
        await execute(
          'sshpass -p lg ssh -o StrictHostKeyChecking=no lg@lg$i '
          '"mkdir -p /home/lg/.googleearth /home/lg/.local/share/Google/GoogleEarth"'
        );

        // Copy the KML file from master to each slave via scp
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

    // Clean up temp file
    await execute('rm -f $slaveTmp 2>/dev/null');

    // Wait for the files to write completely
    await Future.delayed(const Duration(milliseconds: 300));

    // 4. Seed the sync file with a valid-but-empty KML document so that
    //    Google Earth has something to parse on its very first poll.
    //    Without this, GE may encounter a missing or empty file and stop
    //    polling kmls.txt entirely.
    const seedKml =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<kml xmlns="http://www.opengis.net/kml/2.2">'
        '<Document><name>Climate Storyteller</name></Document></kml>';
    final seedBytes = utf8.encode(seedKml);
    await _sftpUpload(_kmlSyncFile, seedBytes);
    for (int i = 1; i <= _state.screenCount; i++) {
      await _sftpUpload('/var/www/html/kmls_$i.txt', seedBytes);
    }

    // 5. Relaunch Google Earth on all screens to apply changes
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

  // Increment to invalidate cached KML files when generator logic changes
  static const int _kmlCacheVersion = 15;

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

  // Size of regional box in degrees
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
    // Ampersands must be escaped as &amp; in KML
    return url.replaceAll('&', '&amp;');
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

    // Determine Tipping Point & Severity Badge for active era
    final riskBadgeHtml = switch (activeYear) {
      <= 1950 => "<span style='background:#2ecc71;color:#ffffff;padding:3px 8px;border-radius:12px;font-size:11px;font-weight:bold;'>🟢 BASELINE EQUILIBRIUM</span>",
      <= 1999 => "<span style='background:#f1c40f;color:#000000;padding:3px 8px;border-radius:12px;font-size:11px;font-weight:bold;'>🟡 ELEVATED CLIMATE STRESS</span>",
      <= 2049 => "<span style='background:#e67e22;color:#ffffff;padding:3px 8px;border-radius:12px;font-size:11px;font-weight:bold;'>🟧 ACTIVE TIPPING RISK</span>",
      _       => "<span style='background:#e74c3c;color:#ffffff;padding:3px 8px;border-radius:12px;font-size:11px;font-weight:bold;'>🔴 CRITICAL TIPPING POINT BREACH</span>",
    };

    // Regional Action & Mitigation Guide
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
        <text><![CDATA[
          <font face="Helvetica, Arial, sans-serif">
            <h3>\$[name]</h3>
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

    <!-- Screen 1 Overlay: Liquid Galaxy Logo -->
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

    <!-- Main Region Scientific Data Placemark -->
    <Placemark>
      <name>${LG3DVisuals.escapeXmlText(region.name)} — Scientific Profile</name>
      <visibility>1</visibility>
      <gx:balloonVisibility>1</gx:balloonVisibility>
      <styleUrl>#customBalloon</styleUrl>
      <description><![CDATA[
        <div style='font-family:Helvetica,Arial,sans-serif;max-width:460px;background:#0f172a;color:#f8fafc;padding:12px;border-radius:10px;box-shadow:0 4px 15px rgba(0,0,0,0.5);'>
        <img src='${region.imageUrl}' style='width:100%;max-height:200px;object-fit:cover;border-radius:8px;margin-bottom:12px;border:1px solid #334155;' />
        
        <div style='display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;'>
          <h2 style='color:#38bdf8;margin:0;font-size:18px;'>${region.name}</h2>
        </div>
        <div style='margin-bottom:12px;'>$riskBadgeHtml</div>

        <p style='color:#94a3b8;font-size:12px;margin:0 0 12px;line-height:1.4;'><b>Active Era:</b> $activeYear (${era.label}) &bull; Scientific projection under IPCC AR6 SSP3-7.0</p>
        
        <!-- Multi-Era Metrics Matrix -->
        <table style='border-collapse:collapse;width:100%;font-size:12px;margin-bottom:12px;'>
          <tr style='background:#1e293b;color:#e2e8f0;'>
            <th style='padding:7px 8px;text-align:left;'>Era / Year</th>
            <th style='padding:7px 8px;text-align:center;'>Temp &Delta;</th>
            <th style='padding:7px 8px;text-align:center;'>$statHeader</th>
            <th style='padding:7px 8px;text-align:center;'>Impact</th>
          </tr>
          <tr style='background:${activeYear == 1900 ? '#14532d' : '#0f172a'};color:#4ade80;'>
            <td style='padding:6px 8px;'>${activeYear == 1900 ? '&#9654; ' : ''}1900 (Baseline)</td>
            <td style='padding:6px 8px;text-align:center;'>+${pastTemp.toStringAsFixed(1)}&deg;C</td>
            <td style='padding:6px 8px;text-align:center;'>$pastStat</td>
            <td style='padding:6px 8px;text-align:center;'>Stable</td>
          </tr>
          ${isSpecialYear ? '''
          <tr style='background:#1e3a8a;color:#38bdf8;font-weight:bold;'>
            <td style='padding:6px 8px;'>&#9654; $activeYear (Active)</td>
            <td style='padding:6px 8px;text-align:center;'>+${activeTemp.toStringAsFixed(1)}&deg;C</td>
            <td style='padding:6px 8px;text-align:center;'>$activeStat</td>
            <td style='padding:6px 8px;text-align:center;'>&#9733; Active</td>
          </tr>
          ''' : ''}
          <tr style='background:${activeYear == 2026 ? '#365314' : '#0f172a'};color:#facc15;'>
            <td style='padding:6px 8px;'>${activeYear == 2026 ? '&#9654; ' : ''}<b>2026 (Present)</b></td>
            <td style='padding:6px 8px;text-align:center;'><b>+${nowTemp.toStringAsFixed(1)}&deg;C</b></td>
            <td style='padding:6px 8px;text-align:center;'><b>$nowStat</b></td>
            <td style='padding:6px 8px;text-align:center;'>${region.category == 'forest' || region.category == 'glacier' ? '&#8675; Declining' : '&#8673; Rising'}</td>
          </tr>
          <tr style='background:${activeYear == 2100 ? '#7f1d1d' : '#0f172a'};color:#f87171;'>
            <td style='padding:6px 8px;'>${activeYear == 2100 ? '&#9654; ' : ''}<b>2100 (Projected)</b></td>
            <td style='padding:6px 8px;text-align:center;'><b>+${futureTemp.toStringAsFixed(1)}&deg;C</b></td>
            <td style='padding:6px 8px;text-align:center;'><b>$futureStat</b></td>
            <td style='padding:6px 8px;text-align:center;'>${region.category == 'forest' || region.category == 'glacier' ? '&#8675;&#8675; Severe' : '&#8673;&#8673; Severe'}</td>
          </tr>
        </table>

        <!-- Narrative Context -->
        <div style='margin-bottom:10px;padding:10px;background:#1e293b;border-left:4px solid #38bdf8;border-radius:4px;'>
          <b style='color:#38bdf8;font-size:13px;'>Scientific Narrative Analysis:</b><br/>
          <span style='color:#cbd5e1;font-size:12px;line-height:1.4;'>$description</span>
        </div>

        <!-- Mitigation & Adaptation Plan -->
        <div style='margin-bottom:10px;padding:10px;background:#142834;border-left:4px solid #22c55e;border-radius:4px;'>
          <b style='color:#22c55e;font-size:13px;'>Climate Resilience & Mitigation Plan:</b><br/>
          <span style='color:#cbd5e1;font-size:12px;line-height:1.4;'>$actionGuideHtml</span>
        </div>

        <p style='color:#64748b;font-size:10px;margin-top:8px;line-height:1.3;'>
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

  /// Builds localized monitoring sub-station placemarks for each region.
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

    for (final st in stations) {
      final stLat = region.latitude + (st['dLat'] as double);
      final stLon = region.longitude + (st['dLon'] as double);
      final stName = st['name'] as String;
      final stType = st['type'] as String;

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
          <div style='font-family:Helvetica,Arial,sans-serif;max-width:320px;background:#0f172a;color:#f8fafc;padding:10px;border-radius:8px;'>
            <h4 style='color:#00e5ff;margin:0 0 4px;'>$stName</h4>
            <p style='color:#94a3b8;font-size:11px;margin:0 0 8px;'><b>Station Type:</b> $stType</p>
            <div style='background:#1e293b;padding:8px;border-radius:4px;font-size:11px;color:#cbd5e1;'>
              &bull; <b>Active Year:</b> $activeYear<br/>
              &bull; <b>Coordinates:</b> ${stLat.toStringAsFixed(4)}&deg;, ${stLon.toStringAsFixed(4)}&deg;<br/>
              &bull; <b>Status:</b> Telemetry Operational (Real-Time Synchronized)
            </div>
          </div>
        ]]></description>
        <Point>
          <coordinates>$stLon,$stLat,0</coordinates>
        </Point>
      </Placemark>''');
    }

    sb.writeln('</Folder>');
    return sb.toString();
  }

  // 6-color spectrum across timeline eras
  String _severityColorRgb(ClimateEra era) => switch (era) {
    ClimateEra.preindustrial1900 => '22c55e', // Green
    ClimateEra.midCentury1950    => '84cc16', // Light Green
    ClimateEra.lateCentury1980   => 'eab308', // Light Yellow
    ClimateEra.present2026       => 'facc15', // Yellow
    ClimateEra.midProjection2060 => 'f97316', // Orange
    ClimateEra.projected2100     => 'ef4444', // Red
  };

  // Converts alpha + RRGGBB into KML's required AABBGGRR ordering
  String _kmlColorAbgr(String alphaHex, String rrggbb) {
    final rr = rrggbb.substring(0, 2);
    final gg = rrggbb.substring(2, 4);
    final bb = rrggbb.substring(4, 6);
    return '$alphaHex$bb$gg$rr';
  }

  // Returns a description blurb for a polygon's info balloon
  String _severityBlurb(String category, ClimateEra era, Map<String, String> eraStats) {
    final trend = switch (era) {
      ClimateEra.preindustrial1900 => 'Pre-industrial baseline — before major human-driven warming.',
      ClimateEra.midCentury1950    => 'Mid 20th Century — post-WWII global industrial acceleration.',
      ClimateEra.lateCentury1980   => 'Late 20th Century — rapid growth in greenhouse gas emissions.',
      ClimateEra.present2026       => 'Current conditions — actively worsening global climate impact.',
      ClimateEra.midProjection2060 => 'Mid 21st Century — projected severe impacts under continued emissions.',
      ClimateEra.projected2100     => 'Late 21st Century — projected extreme end-of-century scenario.',
    };
    final metric = switch (category) {
      'glacier'  => 'Ice extent: ${eraStats['ice_extent']}',
      'sealevel' => 'Sea level rise: ${eraStats['sea_level']}',
      'forest'   => 'Forest cover loss: ${eraStats['forest_loss']}',
      'heat'     => 'Temperature anomaly: ${eraStats['temp_anomaly']}',
      'aqi'      => 'Haze/particulate levels shown via NASA MODIS Aerosol Optical Depth — check the region\'s live AQI reading for current conditions.',
      _ => '',
    };
    return '$trend $metric';
  }

  String _buildCategoryLayer(
    ClimateRegion region,
    ClimateEra era,
    Map<String, String> stats,
    IpccRegionData? regionData,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('<Folder><name>${LG3DVisuals.escapeXmlText(region.name)} Progression</name>');
    buffer.writeln('<visibility>1</visibility><open>1</open>');

    // Build sub-folders per era with TimeSpan for timeline control
    for (final e in ClimateEra.values) {
      final eraStats = _getEraStats(regionData, region.category, int.parse(e.label));

      buffer.writeln('<Folder>');
      buffer.writeln('<name>${LG3DVisuals.escapeXmlText(region.name)} \u2014 ${e.label}</name>');
      buffer.writeln('<visibility>1</visibility>');
      buffer.writeln(_timeSpanKml(e));

      // Category-specific zone polygon (shape/coordinates unchanged)
      switch (region.category) {
        case 'glacier':
          buffer.writeln(_glacierPolygon(region, e, eraStats));
          break;
        case 'sealevel':
          buffer.writeln(_seaLevelPolygon(region, e, eraStats));
          break;
        case 'forest':
          buffer.writeln(_forestPolygon(region, e, eraStats));
          break;
        case 'heat':
          buffer.writeln(_heatPolygon(region, e, eraStats));
          break;
        case 'aqi':
          buffer.writeln(_aqiPolygon(region, e, eraStats));
          break;
      }

      // Always-visible floating data label with key metric for this era
      buffer.writeln(_buildDataLabel(region, e, eraStats, regionData));

      // 3D extruded bar whose height encodes metric severity
      buffer.writeln(_buildDataBar(region, e, eraStats, regionData));

      buffer.writeln('</Folder>');
    }

    buffer.writeln('</Folder>');
    return buffer.toString();
  }

  String _generateIrregularPolygon(double lat, double lon, double radius, double noise, int seed) {
    final points = <String>[];
    final phase = seed * 0.37;
    for (int i = 0; i <= 32; i++) {
      final angle = i * (math.pi * 2) / 32;
      final wobble = (math.sin(angle * 3 + phase) * 0.6 +
                      math.sin(angle * 5 + phase * 1.3) * 0.4) * noise;
      final r = (radius + wobble).clamp(radius * 0.4, radius * 1.4);

      final pLat = lat + r * math.sin(angle);
      final pLon = lon + r * math.cos(angle) / math.cos(lat * math.pi / 180);
      points.add('${pLon.toStringAsFixed(5)},${pLat.toStringAsFixed(5)},0');
    }
    return points.join(' ');
  }

  String _heatPolygon(ClimateRegion region, ClimateEra era, Map<String, String> eraStats) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => '44',
      ClimateEra.midCentury1950    => '66',
      ClimateEra.lateCentury1980   => '88',
      ClimateEra.present2026       => 'aa',
      ClimateEra.midProjection2060 => 'cc',
      ClimateEra.projected2100     => 'ee',
    };
    final color = _kmlColorAbgr(opacity, _severityColorRgb(era));
    final outlineColor = _kmlColorAbgr('ff', _severityColorRgb(era));
    final glowColor = _kmlColorAbgr('22', _severityColorRgb(era));
    // Heat zone expands
    final radius = switch (era) {
      ClimateEra.preindustrial1900 => 0.3,
      ClimateEra.midCentury1950    => 0.5,
      ClimateEra.lateCentury1980   => 0.7,
      ClimateEra.present2026       => 0.9,
      ClimateEra.midProjection2060 => 1.2,
      ClimateEra.projected2100     => 1.5,
    };
    
    final coords = _generateIrregularPolygon(region.latitude, region.longitude, radius, 0.2, 42);
    final glowCoords = _generateIrregularPolygon(region.latitude, region.longitude, radius * 1.2, radius * 0.12, 42);
    final blurb = _severityBlurb('heat', era, eraStats);

    return '''
    <Placemark>
      <name>Heat Glow \u2014 ${LG3DVisuals.escapeXmlText(era.label)}</name>
      <visibility>1</visibility>
      <Style>
        <PolyStyle><color>$glowColor</color><outline>0</outline></PolyStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs><LinearRing><coordinates>$glowCoords</coordinates></LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>
    <Placemark>
      <name>Extreme Heat Area \u2014 ${LG3DVisuals.escapeXmlText(era.label)}</name>
      <visibility>1</visibility>
      <description><![CDATA[$blurb]]></description>
      <Style>
        <PolyStyle>
          <color>$color</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>$outlineColor</color>
          <width>3.5</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>$coords</coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  String _glacierPolygon(ClimateRegion region, ClimateEra era, Map<String, String> eraStats) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => 'bb',
      ClimateEra.midCentury1950    => '99',
      ClimateEra.lateCentury1980   => '77',
      ClimateEra.present2026       => '55',
      ClimateEra.midProjection2060 => '33',
      ClimateEra.projected2100     => '22',
    };
    final color = _kmlColorAbgr(opacity, _severityColorRgb(era));
    final outlineColor = _kmlColorAbgr('ff', _severityColorRgb(era));
    final glowColor = _kmlColorAbgr('22', _severityColorRgb(era));
    
    // Glacier shrinks over time
    final radius = switch (era) {
      ClimateEra.preindustrial1900 => 0.5,
      ClimateEra.midCentury1950    => 0.4,
      ClimateEra.lateCentury1980   => 0.3,
      ClimateEra.present2026       => 0.2,
      ClimateEra.midProjection2060 => 0.1,
      ClimateEra.projected2100     => 0.04,
    };
    
    final coords = _generateIrregularPolygon(region.latitude, region.longitude, radius, 0.1, 88);
    final glowCoords = _generateIrregularPolygon(region.latitude, region.longitude, radius * 1.3, radius * 0.08, 88);
    final blurb = _severityBlurb('glacier', era, eraStats);

    return '''
    <Placemark>
      <name>Glacier Glow \u2014 ${LG3DVisuals.escapeXmlText(era.label)}</name>
      <visibility>1</visibility>
      <Style>
        <PolyStyle><color>$glowColor</color><outline>0</outline></PolyStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs><LinearRing><coordinates>$glowCoords</coordinates></LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>
    <Placemark>
      <name>Glacier extent \u2014 ${LG3DVisuals.escapeXmlText(era.label)}</name>
      <visibility>1</visibility>
      <description><![CDATA[$blurb]]></description>
      <Style>
        <PolyStyle>
          <color>$color</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>$outlineColor</color>
          <width>3.5</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>$coords</coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  String _seaLevelPolygon(ClimateRegion region, ClimateEra era, Map<String, String> eraStats) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => '44',
      ClimateEra.midCentury1950    => '66',
      ClimateEra.lateCentury1980   => '88',
      ClimateEra.present2026       => 'aa',
      ClimateEra.midProjection2060 => 'cc',
      ClimateEra.projected2100     => 'ee',
    };
    final color = _kmlColorAbgr(opacity, _severityColorRgb(era));
    final outlineColor = _kmlColorAbgr('ff', _severityColorRgb(era));
    final glowColor = _kmlColorAbgr('22', _severityColorRgb(era));

    final (offsetDeg, radius) = switch (era) {
      ClimateEra.preindustrial1900 => (0.25, 0.05),
      ClimateEra.midCentury1950    => (0.20, 0.09),
      ClimateEra.lateCentury1980   => (0.15, 0.14),
      ClimateEra.present2026       => (0.10, 0.20),
      ClimateEra.midProjection2060 => (0.05, 0.28),
      ClimateEra.projected2100     => (0.00, 0.38),
    };
    const bearingRad = 2.356;
    final centerLat = region.latitude + offsetDeg * math.sin(bearingRad);
    final centerLon = region.longitude +
        offsetDeg * math.cos(bearingRad) / math.cos(region.latitude * math.pi / 180);

    final coords = _generateIrregularPolygon(centerLat, centerLon, radius, 0.05, 12);
    final glowCoords = _generateIrregularPolygon(centerLat, centerLon, radius * 1.25, radius * 0.06, 12);
    final blurb = _severityBlurb('sealevel', era, eraStats) +
        (era == ClimateEra.projected2100
            ? ' Flood zone now reaches the marked location.'
            : ' Flood zone is ${(offsetDeg * 111).toStringAsFixed(0)} km from the marked location.');

    return '''
    <Placemark>
      <name>Sea Level Glow \u2014 ${LG3DVisuals.escapeXmlText(era.label)}</name>
      <visibility>1</visibility>
      <Style>
        <PolyStyle><color>$glowColor</color><outline>0</outline></PolyStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs><LinearRing><coordinates>$glowCoords</coordinates></LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>
    <Placemark>
      <name>Sea level inundation \u2014 ${LG3DVisuals.escapeXmlText(era.label)}</name>
      <visibility>1</visibility>
      <description><![CDATA[$blurb]]></description>
      <Style>
        <PolyStyle>
          <color>$color</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>$outlineColor</color>
          <width>3.5</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>$coords</coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  String _forestPolygon(ClimateRegion region, ClimateEra era, Map<String, String> eraStats) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => 'bb',
      ClimateEra.midCentury1950    => '99',
      ClimateEra.lateCentury1980   => '77',
      ClimateEra.present2026       => '55',
      ClimateEra.midProjection2060 => '33',
      ClimateEra.projected2100     => '22',
    };
    final color = _kmlColorAbgr(opacity, _severityColorRgb(era));
    final outlineColor = _kmlColorAbgr('ff', _severityColorRgb(era));
    final glowColor = _kmlColorAbgr('22', _severityColorRgb(era));
    
    // Forest shrinks
    final radius = switch (era) {
      ClimateEra.preindustrial1900 => 0.9,
      ClimateEra.midCentury1950    => 0.75,
      ClimateEra.lateCentury1980   => 0.6,
      ClimateEra.present2026       => 0.45,
      ClimateEra.midProjection2060 => 0.3,
      ClimateEra.projected2100     => 0.15,
    };
    
    final coords = _generateIrregularPolygon(region.latitude, region.longitude, radius, 0.2, 55);
    final glowCoords = _generateIrregularPolygon(region.latitude, region.longitude, radius * 1.2, radius * 0.12, 55);
    final blurb = _severityBlurb('forest', era, eraStats);

    return '''
    <Placemark>
      <name>Forest Glow \u2014 ${LG3DVisuals.escapeXmlText(era.label)}</name>
      <visibility>1</visibility>
      <Style>
        <PolyStyle><color>$glowColor</color><outline>0</outline></PolyStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs><LinearRing><coordinates>$glowCoords</coordinates></LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>
    <Placemark>
      <name>Forest cover \u2014 ${LG3DVisuals.escapeXmlText(era.label)}</name>
      <visibility>1</visibility>
      <description><![CDATA[$blurb]]></description>
      <Style>
        <PolyStyle>
          <color>$color</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>$outlineColor</color>
          <width>3.5</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>$coords</coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  String _aqiPolygon(ClimateRegion region, ClimateEra era, Map<String, String> eraStats) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => '44',
      ClimateEra.midCentury1950    => '66',
      ClimateEra.lateCentury1980   => '88',
      ClimateEra.present2026       => 'aa',
      ClimateEra.midProjection2060 => 'cc',
      ClimateEra.projected2100     => 'ee',
    };
    final color = _kmlColorAbgr(opacity, _severityColorRgb(era));
    final outlineColor = _kmlColorAbgr('ff', _severityColorRgb(era));
    final glowColor = _kmlColorAbgr('22', _severityColorRgb(era));

    final radius = switch (era) {
      ClimateEra.preindustrial1900 => 0.25,
      ClimateEra.midCentury1950    => 0.4,
      ClimateEra.lateCentury1980   => 0.55,
      ClimateEra.present2026       => 0.7,
      ClimateEra.midProjection2060 => 0.85,
      ClimateEra.projected2100     => 1.0,
    };

    final coords = _generateIrregularPolygon(region.latitude, region.longitude, radius, 0.15, 71);
    final glowCoords = _generateIrregularPolygon(region.latitude, region.longitude, radius * 1.2, radius * 0.1, 71);
    final blurb = _severityBlurb('aqi', era, eraStats);

    return '''
    <Placemark>
      <name>AQI Zone Glow \u2014 ${LG3DVisuals.escapeXmlText(era.label)}</name>
      <visibility>1</visibility>
      <Style>
        <PolyStyle><color>$glowColor</color><outline>0</outline></PolyStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs><LinearRing><coordinates>$glowCoords</coordinates></LinearRing></outerBoundaryIs>
      </Polygon>
    </Placemark>
    <Placemark>
      <name>Air Quality Zone \u2014 ${LG3DVisuals.escapeXmlText(era.label)}</name>
      <visibility>1</visibility>
      <description><![CDATA[$blurb]]></description>
      <Style>
        <PolyStyle>
          <color>$color</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>$outlineColor</color>
          <width>3.5</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>$coords</coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  // ─────────────────────────────────────────────
  // Visual Enhancement Helpers
  // ─────────────────────────────────────────────

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

  /// Returns the primary display metric string for a category/era.
  String _getCategoryMetric(String category, ClimateEra era, IpccRegionData? regionData) {
    final year = int.parse(era.label);
    if (regionData == null) return '';
    final temp = _interpolateMap(regionData.localTempAnomaly, year);
    final ice = _interpolateMap(regionData.iceExtentKm2, year);
    final sea = _interpolateMap(regionData.seaLevelMm, year);
    final forest = _interpolateMap(regionData.forestCoverPct, year);
    final aqi = _interpolateMap(regionData.aqiIndex, year);

    return switch (category) {
      'glacier'  => '${(ice / 1000000.0).toStringAsFixed(1)}M km\u00B2',
      'sealevel' => '${sea.toStringAsFixed(0)} mm rise',
      'forest'   => '${forest.toStringAsFixed(1)}% cover',
      'heat'     => '+${temp.toStringAsFixed(1)}\u00B0C',
      'aqi'      => 'AQI ${aqi.toStringAsFixed(0)}',
      _          => '',
    };
  }

  /// Builds an always-visible data label Placemark showing the key metric
  /// for a given era, positioned near the region with era-based offsets
  /// so labels from different eras don't overlap.
  String _buildDataLabel(ClimateRegion region, ClimateEra era,
      Map<String, String> eraStats, IpccRegionData? regionData) {
    final metric = _getCategoryMetric(region.category, era, regionData);
    final color = _kmlColorAbgr('ff', _severityColorRgb(era));

    // Fan out labels so all 6 eras are readable simultaneously
    final (latOff, lonOff) = switch (era) {
      ClimateEra.preindustrial1900 => (-0.30, -0.40),
      ClimateEra.midCentury1950    => (-0.15, -0.20),
      ClimateEra.lateCentury1980   => (0.00,  -0.40),
      ClimateEra.present2026       => (0.00,   0.45),
      ClimateEra.midProjection2060 => (0.15,   0.25),
      ClimateEra.projected2100     => (0.30,  -0.35),
    };

    final labelLat = region.latitude + latOff;
    final labelLon = region.longitude + lonOff;
    final blurb = _severityBlurb(region.category, era, eraStats);

    return '''
    <Placemark>
      <name>${LG3DVisuals.escapeXmlText(era.label)}: $metric</name>
      <visibility>1</visibility>
      <description><![CDATA[$blurb]]></description>
      <Style>
        <IconStyle>
          <scale>0.7</scale>
          <Icon><href>http://maps.google.com/mapfiles/kml/shapes/info_circle.png</href></Icon>
          <color>$color</color>
        </IconStyle>
        <LabelStyle>
          <color>$color</color>
          <scale>1.4</scale>
        </LabelStyle>
      </Style>
      <Point>
        <coordinates>$labelLon,$labelLat,0</coordinates>
      </Point>
    </Placemark>''';
  }

  /// Builds a 3D extruded column (data bar) whose height represents the
  /// severity of the metric for this era — creating a 3D bar chart on
  /// the globe surface visible from the LG rig's tilted camera.
  String _buildDataBar(ClimateRegion region, ClimateEra era,
      Map<String, String> eraStats, IpccRegionData? regionData) {
    final year = int.parse(era.label);

    // Height proportional to metric severity (meters above ground)
    final height = switch (region.category) {
      'heat'     => (regionData?.localTempAnomaly[year] ?? 0.0) * 10000.0,
      'glacier'  => (1.0 - (regionData?.iceExtentKm2[year] ?? 12500000) / 12500000.0) * 50000.0,
      'sealevel' => (regionData?.seaLevelMm[year] ?? 0).toDouble() * 50.0,
      'forest'   => (100.0 - (regionData?.forestCoverPct[year] ?? 100)) / 100.0 * 50000.0,
      'aqi'      => (regionData?.aqiIndex[year] ?? 0) * 100.0,
      _          => 10000.0,
    };

    if (height < 500) return ''; // Too small to render visibly

    final fillColor = _kmlColorAbgr('cc', _severityColorRgb(era));
    final edgeColor = _kmlColorAbgr('ff', _severityColorRgb(era));
    final metric = _getCategoryMetric(region.category, era, regionData);

    // Place bars side by side so all 6 eras are visible together
    final lonOff = switch (era) {
      ClimateEra.preindustrial1900 => -0.25,
      ClimateEra.midCentury1950    => -0.15,
      ClimateEra.lateCentury1980   => -0.05,
      ClimateEra.present2026       =>  0.05,
      ClimateEra.midProjection2060 =>  0.15,
      ClimateEra.projected2100     =>  0.25,
    };

    final barLat = region.latitude - 0.4;
    final barLon = region.longitude + lonOff;
    const halfSpan = 0.04;
    final h = height.toStringAsFixed(0);

    final sw = '${barLon - halfSpan},${barLat - halfSpan},$h';
    final se = '${barLon + halfSpan},${barLat - halfSpan},$h';
    final ne = '${barLon + halfSpan},${barLat + halfSpan},$h';
    final nw = '${barLon - halfSpan},${barLat + halfSpan},$h';

    return '''
    <Placemark>
      <name>${LG3DVisuals.escapeXmlText(era.label)} \u2014 $metric</name>
      <visibility>1</visibility>
      <description><![CDATA[<b>${era.label}</b>: $metric<br/>${_severityBlurb(region.category, era, eraStats)}]]></description>
      <Style>
        <PolyStyle>
          <color>$fillColor</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>$edgeColor</color>
          <width>1.5</width>
        </LineStyle>
      </Style>
      <Polygon>
        <extrude>1</extrude>
        <tessellate>1</tessellate>
        <altitudeMode>relativeToGround</altitudeMode>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>$sw $se $ne $nw $sw</coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>
    <!-- Floating 3D Value Banner above Column -->
    <Placemark>
      <name>${LG3DVisuals.escapeXmlText(era.label)}: $metric</name>
      <visibility>1</visibility>
      <Style>
        <IconStyle>
          <scale>0.6</scale>
          <Icon><href>http://maps.google.com/mapfiles/kml/shapes/donut.png</href></Icon>
          <color>$edgeColor</color>
        </IconStyle>
        <LabelStyle>
          <color>$edgeColor</color>
          <scale>1.2</scale>
        </LabelStyle>
      </Style>
      <Point>
        <altitudeMode>relativeToGround</altitudeMode>
        <coordinates>$barLon,$barLat,$h</coordinates>
      </Point>
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

  /// Quick targeted verification of the KML delivery pipeline.
  /// Returns a map with 'ok' (bool) and 'details' (String) for each step.
  Future<Map<String, String>> verifyKmlDelivery() async {
    if (_client == null) return {'error': 'Not connected'};

    final results = <String, String>{};
    final port = _state.webPort;

    // 1. Check if the kml directory exists and has files
    try {
      final ls = await execute('ls -la $_kmlDir/ 2>&1');
      results['1_kml_dir'] = ls.trim().isEmpty ? '❌ EMPTY' : '✅ Files exist:\n$ls';
    } catch (e) {
      results['1_kml_dir'] = '❌ ERROR: $e';
    }

    // 2. Check if kmls.txt exists and has content
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

    // 3. Check if web server is serving kmls.txt
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

    // 4. Check Google Earth MyPlaces.kml for NetworkLink
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

    // 5. Check if Google Earth is running
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

    // 6. Test direct KML fetch that GE would do
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
  // Any free-text string (name, description) embedded directly into KML
  // (i.e. NOT wrapped in <![CDATA[ ]]>) must have XML special characters
  // escaped. A raw "&" — e.g. in "... Mesh & Hotspot Spikes" — breaks
  // parsing of the ENTIRE document, not just that one <name> tag, which is
  // why a single unescaped "&" in a Folder/Placemark name can make the
  // whole KML fail to render on the rig.
  static String escapeXmlText(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  LG3DVisuals._();

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

    // 3D Cones / Pyramids at Hotspot Nodes
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