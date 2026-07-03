import 'dart:async';
import 'dart:convert';
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
  static const _queryFile = '/tmp/query.txt';
  static const _kmlSyncFile = '/var/www/html/kmls.txt';

  @override
  Future<bool> connect({
    required String ipAddress,
    int port = 22,
    String username = 'lg',
    String password = 'lg',
    int screenCount = 5,
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

  @override
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

  @override
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

  @override
  Future<void> relaunchGoogleEarth() async {
    if (_client == null) throw Exception('Not connected');
    await execute('/home/lg/bin/lg-relaunch 2>&1 || DISPLAY=:0 /home/lg/earth/googleearth &');
  }

  /// Builds a NetworkLink KML that tells slave Google Earth instances to
  /// fetch the main KML from the master's web server.
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
