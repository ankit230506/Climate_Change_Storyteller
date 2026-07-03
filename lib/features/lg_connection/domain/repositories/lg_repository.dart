import '../entities/lg_rig_state.dart';

abstract class LgRepository {
  Stream<LGRigState> get stateStream;
  LGRigState get state;

  Future<bool> connect({
    required String ipAddress,
    int port = 22,
    String username = 'lg',
    String password = 'lg',
    int screenCount = 5,
  });

  Future<void> disconnect();
  Future<String> execute(String command);
  Future<void> sendKml(String kmlFilename, {String? kmlContent});
  Future<void> flyTo({
    required double latitude,
    required double longitude,
    required double altitude,
    double tilt = 0,
    double heading = 0,
  });
  Future<void> clearKml();
  Future<void> relaunchGoogleEarth();
}
