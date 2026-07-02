import 'dart:async';
import 'package:dartssh2/dartssh2.dart';
import '../../domain/entities/lg_rig_state.dart';
import '../../domain/repositories/lg_repository.dart';
import '../datasources/lg_ssh_data_source.dart';
import '../../../../core/storage/secure_storage_service.dart';

class LgRepositoryImpl implements LgRepository {
  final LgSshDataSource sshDataSource;
  
  SSHClient? _client;
  LGRigState _state = const LGRigState();
  final _stateCtrl = StreamController<LGRigState>.broadcast();
  Timer? _keepaliveTimer;

  LgRepositoryImpl({required this.sshDataSource});

  @override
  Stream<LGRigState> get stateStream => _stateCtrl.stream;

  @override
  LGRigState get state => _state;

  static const _kmlDir    = '/var/www/html/kml';
  static const _queryFile = '/var/www/html/query.txt';

  @override
  Future<bool> connect({
    required String ipAddress,
    int port = 22,
    String username = 'lg',
    String password = 'lq',
  }) async {
    _update(_state.copyWith(status: LGConnectionStatus.connecting));

    try {
      final client = await sshDataSource.connect(
        ipAddress: ipAddress,
        port: port,
        username: username,
        password: password,
      );
      _client = client;

      // Verify kml folder exists
      final check = await execute('test -d $_kmlDir && echo "yes" || echo "no"');

      final screens = await _detectScreenCount();
      final sw = Stopwatch()..start();
      await execute('echo ping');
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

  @override
  Future<void> disconnect() async {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    await sshDataSource.disconnect(_client);
    _client = null;
    _update(const LGRigState());
  }

  @override
  Future<String> execute(String command) async {
    final client = _client;
    if (client == null) throw Exception('Not connected to LG rig');
    return await sshDataSource.execute(client, command);
  }

  @override
  Future<void> sendKml(String kmlFilename, {String? kmlContent}) async {
    if (_client == null) throw Exception('Not connected');

    if (kmlContent != null) {
      final escaped = kmlContent
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "'\\''");

      await execute("echo '$escaped' > $_kmlDir/$kmlFilename");
    }

    final masterIp = _state.ipAddress!;
    final netLink  = _buildNetworkLinkKml('http://$masterIp/kml/$kmlFilename');
    final escaped  = netLink.replaceAll("'", "'\\''");

    for (int i = 2; i <= _state.screenCount; i++) {
      try {
        final cmd =
            'sshpass -p lq ssh -o StrictHostKeyChecking=no '
            'lg@lg$i "echo \'$escaped\' > $_kmlDir/kml_$i.kml" 2>&1';
        await execute(cmd);
      } catch (_) {}
    }

    await _triggerRefresh(kmlFilename);
    _update(_state.copyWith(currentKml: kmlFilename));
  }

  @override
  Future<void> flyTo({
    required double latitude,
    required double longitude,
    required double altitude,
    double tilt = 0,
    double heading = 0,
  }) async {
    if (_client == null) throw Exception('Not connected');
    final flytoCmd = 'flytoview=$longitude,$latitude,$altitude,$heading,$tilt,0';
    await execute("echo '$flytoCmd' > $_queryFile");
  }

  @override
  Future<void> clearKml() async {
    if (_client == null) throw Exception('Not connected');
    await execute("rm -f $_kmlDir/*.kml 2>&1");
    for (int i = 2; i <= _state.screenCount; i++) {
      try {
        await execute(
          'sshpass -p lq ssh -o StrictHostKeyChecking=no '
          'lg@lg$i "rm -f $_kmlDir/*.kml" 2>&1',
        );
      } catch (_) {}
    }
    _update(_state.copyWith(currentKml: null));
  }

  @override
  Future<void> relaunchGoogleEarth() async {
    if (_client == null) throw Exception('Not connected');
    await execute('/home/lg/bin/lg-relaunch 2>&1 || DISPLAY=:0 /home/lg/earth/googleearth &');
  }

  Future<int> _detectScreenCount() async {
    try {
      final result = await execute(
        'for i in 2 3 4 5 6 7; do '
        'sshpass -p lq ssh -o StrictHostKeyChecking=no '
        '-o ConnectTimeout=2 lg@lg\$i "echo ok" 2>/dev/null '
        '&& echo "ok\$i"; done',
      );
      final count = 'ok'.allMatches(result).length + 1;
      return count.clamp(1, 7);
    } catch (_) {
      return 1;
    }
  }

  String _buildNetworkLinkKml(String href) =>
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<kml xmlns="http://www.opengis.net/kml/2.2">'
      '<NetworkLink><name>Climate Storyteller</name>'
      '<Link><href>$href</href>'
      '<refreshMode>onInterval</refreshMode>'
      '<refreshInterval>2</refreshInterval>'
      '</Link></NetworkLink></kml>';

  Future<void> _triggerRefresh(String kmlFilename) async {
    try {
      await execute("echo '$kmlFilename' > $_queryFile");
    } catch (_) {}
  }

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
