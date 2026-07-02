import '../entities/aqi_reading.dart';

abstract class AqiRepository {
  Future<List<AqiReading>> getCityAqi(String city);
  Future<Map<String, List<AqiReading>>> getAllCitiesAqi();
  String buildAqiKml(Map<String, List<AqiReading>> cityData, String era);
}
