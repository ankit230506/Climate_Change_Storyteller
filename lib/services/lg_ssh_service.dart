import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import '../models/app_models.dart';
import 'secure_storage_service.dart';

class LGSSHService {
  LGSSHService._();
  static final LGSSHService instance = LGSSHService._();

  SSHClient? _client;
  String _password = 'lg';
  LGRigState _state = const LGRigState();
  final _stateCtrl = StreamController<LGRigState>.broadcast();
  Timer? _keepaliveTimer;

  Stream<LGRigState> get stateStream => _stateCtrl.stream;
  LGRigState get state => _state;

  // ── CONNECT ────────────────────────────────────────────────────────────────
  // Uses the EXACT pattern confirmed working from PowerShell:
  // ssh lg@192.168.56.101 (port 22, password lq)
  Future<bool> connect({
    required String ipAddress,
    int port = 22,
    String username = 'lg',
    String password = 'lg',
  }) async {
    _password = password;
    _update(_state.copyWith(status: LGConnectionStatus.connecting));

    try {
      print('[SSH] Connecting to $ipAddress:$port as $username...');

      final socket = await SSHSocket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 10),
      );
      print('[SSH] Socket opened');

      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () {
          print('[SSH] Password requested');
          return password;
        },
      );

      // Wait for authentication to complete
      await _client!.authenticated;
      print('[SSH] Authenticated successfully');

      // Quick test command
      final result = await _client!.run('echo connected');
      final output = utf8.decode(result).trim();
      print('[SSH] Test command result: $output');

      // Detect screens
      final screens = await _detectScreenCount();

      // Measure latency
      final sw = Stopwatch()..start();
      await _client!.run('echo ping');
      final latency = sw.elapsedMilliseconds;

      await SecureStorageService.instance.saveLgCredentials(
        ip: ipAddress,
        port: port,
        username: username,
        password: password,
      );

      _update(_state.copyWith(
        status: LGConnectionStatus.connected,
        ipAddress: ipAddress,
        port: port,
        screenCount: screens,
        latencyMs: latency,
      ));

      _startKeepalive();
      print('[SSH] ✅ Connected! $screens screens, ${latency}ms');
      return true;

    } catch (e, stack) {
      print('[SSH] ❌ Failed: $e');
      print('[SSH] Stack: $stack');
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
    print('[SSH] Disconnected');
  }

  // ── EXECUTE ────────────────────────────────────────────────────────────────
  Future<String> execute(String command) async {
    if (_client == null) {
      throw Exception('Not connected to LG rig');
    }
    final result = await _client!.run(command);
    return utf8.decode(result);
  }

  // ── KML ────────────────────────────────────────────────────────────────────
  Future<void> sendKml(String kmlFilename, {String? kmlContent}) async {
    if (_client == null) throw Exception('Not connected');

    if (kmlContent != null) {
      final escaped = kmlContent
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "'\\''");
      await execute(
          "echo '$escaped' > /var/www/html/kmls/$kmlFilename");
    }

    // Push to all slave screens via network link
    final masterIp = _state.ipAddress!;
    final netLink  = _networkLinkKml(
        'http://$masterIp/kmls/$kmlFilename');
    final escaped  = netLink.replaceAll("'", "'\\''");

    for (int i = 2; i <= _state.screenCount; i++) {
      await execute(
        'sshpass -p $_password ssh -o StrictHostKeyChecking=no '
        'lg@lg$i "echo \'$escaped\' > '
        '/var/www/html/kml/slave_$i.kml"',
      );
    }

    await execute("echo 'refresh=true' > /tmp/query.txt");
    _update(_state.copyWith(currentKml: kmlFilename));
    print('[SSH] KML sent: $kmlFilename');
  }

  Future<void> flyTo({
    required double latitude,
    required double longitude,
    required double altitude,
    double tilt = 0,
    double heading = 0,
  }) async {
    if (_client == null) throw Exception('Not connected');

    final kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document><LookAt>
    <longitude>$longitude</longitude>
    <latitude>$latitude</latitude>
    <altitude>0</altitude>
    <heading>$heading</heading>
    <tilt>$tilt</tilt>
    <range>$altitude</range>
    <altitudeMode>relativeToGround</altitudeMode>
  </LookAt></Document>
</kml>''';

    final escaped = kml.replaceAll("'", "'\\''");
    await execute("echo '$escaped' > /tmp/query.kml");
    print('[SSH] FlyTo: $latitude, $longitude');
  }

  Future<void> clearKml() async {
    if (_client == null) throw Exception('Not connected');
    await execute("echo '' > /var/www/html/kmls/active.kml");
    for (int i = 2; i <= _state.screenCount; i++) {
      await execute(
        'sshpass -p $_password ssh -o StrictHostKeyChecking=no '
        'lg@lg$i "echo \'\' > /var/www/html/kml/slave_$i.kml"',
      );
    }
    await execute("echo 'refresh=true' > /tmp/query.txt");
    _update(_state.copyWith(currentKml: null));
  }

  Future<void> relaunchGoogleEarth() async {
    if (_client == null) throw Exception('Not connected');
    for (int i = _state.screenCount; i >= 1; i--) {
      await execute(
        'sshpass -p $_password ssh -o StrictHostKeyChecking=no lg@lg$i '
        '"DISPLAY=:0 /home/lg/target/lg$i/run.sh '
        '>> /home/lg/log.txt 2>&1 &"',
      );
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────
  Future<int> _detectScreenCount() async {
    try {
      final result = await execute(
        'for i in 2 3 4 5 6 7; do '
        'sshpass -p $_password ssh -o StrictHostKeyChecking=no '
        '-o ConnectTimeout=2 lg@lg\$i '
        '"echo ok" 2>/dev/null && echo "ok\$i"; done',
      );
      final count = 'ok'.allMatches(result).length + 1;
      return count.clamp(1, 7);
    } catch (_) {
      return 3;
    }
  }

  String _networkLinkKml(String href) => '''<?xml version="1.0" encoding="UTF-8"?>
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

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) async {
        try {
          await execute('echo keepalive');
        } catch (_) {
          await disconnect();
        }
      },
    );
  }

  void _update(LGRigState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  void dispose() {
    _client?.close();
    _client = null;
  }
}