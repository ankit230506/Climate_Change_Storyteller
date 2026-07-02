import '../repositories/lg_repository.dart';

class FlyToLg {
  final LgRepository repository;
  FlyToLg(this.repository);

  Future<void> call({
    required double latitude,
    required double longitude,
    required double altitude,
    double tilt = 0,
    double heading = 0,
  }) {
    return repository.flyTo(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      tilt: tilt,
      heading: heading,
    );
  }
}
