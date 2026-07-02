import '../entities/aqi_reading.dart';
import '../repositories/aqi_repository.dart';

class GetAqiData {
  final AqiRepository repository;
  GetAqiData(this.repository);

  Future<List<AqiReading>> getCityAqi(String city) {
    return repository.getCityAqi(city);
  }

  Future<Map<String, List<AqiReading>>> getAllCitiesAqi() {
    return repository.getAllCitiesAqi();
  }

  String buildAqiKml(Map<String, List<AqiReading>> cityData, String era) {
    return repository.buildAqiKml(cityData, era);
  }
}
