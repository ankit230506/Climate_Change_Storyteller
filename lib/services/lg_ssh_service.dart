import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/app_models.dart';
import 'secure_storage_service.dart';

/// SSH service for Liquid Galaxy rig communication.
/// Connection pattern taken from working LG Flutter reference implementation.
class LGSSHService {
  LGSSHService._();
  static final LGSSHService instance = LGSSHService._();

  // ── Static SSH client (matches reference implementation pattern) ──────────
  static SSHClient? _client;
  static String?    _host;
  static int?       _port;
  static String?    _username;
  static String?    _password;

  // ── State stream for UI ───────────────────────────────────────────────────
  LGRigState _state = const LGRigState();
  final _stateCtrl  = StreamController<LGRigState>.broadcast();
  Timer? _keepaliveTimer;

  Stream<LGRigState> get stateStream => _stateCtrl.stream;
  LGRigState         get state       => _state;

  // ── LG rig paths ──────────────────────────────────────────────────────────
  static const _kmlDir     = '/var/www/html/kmls';
  static const _balloonDir = '/var/www/html/kml';

  // ════════════════════════════════════════════════════════════════════════
  // CONNECTION  (using reference implementation pattern exactly)
  // ════════════════════════════════════════════════════════════════════════

  Future<bool> connect({
    required String ipAddress,
    int    port     = 22,
    String username = 'lg',
    String password = 'lq',
  }) async {
    try {
      // Disconnect any existing session first (from reference impl)
      await disconnect();

      // Store credentials for reconnect
      _host     = ipAddress;
      _port     = port;
      _username = username;
      _password = password;

      _update(_state.copyWith(status: LGConnectionStatus.connecting));

      // ── Core connection — exactly as in reference implementation ──
      final socket = await SSHSocket.connect(ipAddress, port);
      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );
      // ─────────────────────────────────────────────────────────────

      // Detect screen count + measure latency after connecting
      final screens = await _detectScreenCount();
      final latency = await _measureLatency();

      // Save credentials for auto-reconnect
      await SecureStorageService.instance.saveLgCredentials(
        ip: ipAddress, port: port,
        username: username, password: password,
      );

      _update(_state.copyWith(
        status:      LGConnectionStatus.connected,
        ipAddress:   ipAddress,
        port:        port,
        screenCount: screens,
        latencyMs:   latency,
      ));

      _startKeepalive();
      _log('✅ Connected to $ipAddress:$port  screens:$screens  latency:${latency}ms');
      return true;

    } catch (e) {
      _log('❌ Connection error: $e');
      _client = null;
      _update(_state.copyWith(
        status:       LGConnectionStatus.error,
        errorMessage: e.toString(),
      ));
      return false;
    }
  }

  Future<void> disconnect() async {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    if (_client != null) {
      _client!.close();
      _client = null;
    }
    _update(const LGRigState());
    _log('Disconnected');
  }

  Future<bool> isConnected() async => _client != null;

  Future<bool> reconnect() async {
    final creds = await SecureStorageService.instance.getLgCredentials();
    final ip    = creds['ip'];
    if (ip == null || ip.isEmpty) return false;
    return connect(
      ipAddress: ip,
      port:      int.tryParse(creds['port'] ?? '22') ?? 22,
      username:  creds['username'] ?? 'lg',
      password:  creds['password'] ?? 'lq',
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // EXECUTE  (from reference implementation — String.fromCharCodes pattern)
  // ════════════════════════════════════════════════════════════════════════

  /// Run any shell command on the LG rig master.
  /// Uses String.fromCharCodes — exactly as reference implementation.
  Future<String> execute(String command) async {
    if (_client == null) {
      throw Exception('Not connected to LG. Please connect first.');
    }
    try {
      final result = await _client!.run(command);
      return String.fromCharCodes(result);
    } catch (e) {
      throw Exception('Command execution failed: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // KML COMMANDS
  // ════════════════════════════════════════════════════════════════════════

  /// Send KML content to the rig and display on all screens.
  Future<void> sendKml(String kmlFilename, {String? kmlContent}) async {
    if (_client == null) throw Exception('Not connected to LG.');

    if (kmlContent != null) {
      // Write KML to master via SSH echo (same pattern as reference sendlogo)
      final escaped = kmlContent.replaceAll("'", "'\\''");
      await execute("echo '$escaped' > $_kmlDir/$kmlFilename");
    }

    // Push network link to each slave screen
    final masterIp = _host!;
    final netLink  = _networkLinkKml('http://$masterIp/kmls/$kmlFilename');
    final escaped  = netLink.replaceAll("'", "'\\''");

    for (int i = 2; i <= _state.screenCount; i++) {
      await execute(
        "sshpass -p $_password ssh -o StrictHostKeyChecking=no "
        "lg@lg$i \"echo '$escaped' > $_balloonDir/slave_$i.kml\"",
      );
    }

    await _forceRefresh();
    _update(_state.copyWith(currentKml: kmlFilename));
    _log('Sent KML: $kmlFilename');
  }

  /// Show logo on the left screen (from reference implementation pattern).
  Future<void> sendLogo(String kmlContent) async {
    const logoScreen = 3;
    final escaped = kmlContent.replaceAll("'", "'\\''");
    await execute(
      "echo '$escaped' > $_balloonDir/slave_${logoScreen}.kml",
    );
    await _forceRefresh();
  }

  /// Fly Google Earth camera to coordinates.
  Future<void> flyTo({
    required double latitude,
    required double longitude,
    required double altitude,
    double tilt    = 0,
    double heading = 0,
  }) async {
    if (_client == null) throw Exception('Not connected to LG.');

    final kml = _flyToKml(
      lat: latitude, lon: longitude,
      alt: altitude, tilt: tilt, heading: heading,
    );
    final escaped = kml.replaceAll("'", "'\\''");
    await execute("echo '$escaped' > /tmp/query.kml");
    _log('FlyTo: lat=$latitude lon=$longitude alt=$altitude');
  }

  /// Clear all KML from all screens.
  Future<void> clearKml() async {
    if (_client == null) throw Exception('Not connected to LG.');
    await execute('echo "" > $_kmlDir/active.kml');
    for (int i = 2; i <= _state.screenCount; i++) {
      await execute(
        'sshpass -p $_password ssh -o StrictHostKeyChecking=no '
        'lg@lg$i "echo \'\' > $_balloonDir/slave_$i.kml"',
      );
    }
    await _forceRefresh();
    _update(_state.copyWith(currentKml: null));
    _log('KML cleared');
  }

  /// Show a balloon / info panel on the right screen.
  Future<void> showBalloon(String htmlContent) async {
    if (_client == null) throw Exception('Not connected to LG.');
    final screen  = _state.screenCount;
    final kml     = _balloonKml(htmlContent);
    final escaped = kml.replaceAll("'", "'\\''");
    await execute(
      "sshpass -p $_password ssh -o StrictHostKeyChecking=no "
      "lg@lg$screen \"echo '$escaped' > $_balloonDir/slave_${screen}.kml\"",
    );
    _log('Balloon shown on screen $screen');
  }

  /// Relaunch Google Earth on all screens.
  Future<void> relaunchGoogleEarth() async {
    if (_client == null) throw Exception('Not connected to LG.');
    for (int i = _state.screenCount; i >= 1; i--) {
      await execute(
        'sshpass -p $_password ssh -o StrictHostKeyChecking=no lg@lg$i '
        '"DISPLAY=:0 /home/lg/target/lg$i/run.sh >> /home/lg/log.txt 2>&1 &"',
      );
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _log('Google Earth relaunched');
  }

  // ════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════════════════════════════════════

  /// Force refresh — from reference implementation
  Future<void> _forceRefresh() async {
    await execute("echo 'refresh=true' > /tmp/query.txt");
  }

  Future<int> _measureLatency() async {
    final sw = Stopwatch()..start();
    await execute('echo ping');
    return sw.elapsedMilliseconds;
  }

  Future<int> _detectScreenCount() async {
    try {
      final result = await execute(
        'for i in 2 3 4 5 6 7; do '
        'sshpass -p $_password ssh -o StrictHostKeyChecking=no '
        '-o ConnectTimeout=2 lg@lg\$i "echo ok" 2>/dev/null '
        '&& echo "screen\$i"; done',
      );
      final count = 'screen'.allMatches(result).length + 1;
      return count.clamp(1, 7);
    } catch (_) {
      return 3; // safe default
    }
  }

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        await execute('echo keepalive');
      } catch (_) {
        _log('Keepalive failed — disconnecting');
        await disconnect();
      }
    });
  }

  // ── KML templates ─────────────────────────────────────────────────────────

  String _networkLinkKml(String href) =>
'''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <NetworkLink>
    <name>Climate Storyteller</name>
    <Link>
      <href>$href</href>
      <refreshMode>onInterval</refreshMode>
      <refreshInterval>2</refreshInterval>
    </Link>
  </NetworkLink>
</kml>''';

  String _flyToKml({
    required double lat, required double lon,
    required double alt, required double tilt,
    required double heading,
  }) =>
'''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <LookAt>
      <longitude>$lon</longitude>
      <latitude>$lat</latitude>
      <altitude>0</altitude>
      <heading>$heading</heading>
      <tilt>$tilt</tilt>
      <range>$alt</range>
      <altitudeMode>relativeToGround</altitudeMode>
    </LookAt>
  </Document>
</kml>''';

  String _balloonKml(String html) =>
'''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <description><![CDATA[$html]]></description>
      <Point><coordinates>0,0,0</coordinates></Point>
    </Placemark>
  </Document>
</kml>''';

  void _update(LGRigState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  void _log(String msg) {
    // ignore: avoid_print
    print('[LGSSHService] $msg');
  }

  void dispose() {
    _keepaliveTimer?.cancel();
    _stateCtrl.close();
  }
}