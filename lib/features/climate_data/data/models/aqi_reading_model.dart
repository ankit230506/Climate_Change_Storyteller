import '../../domain/entities/aqi_reading.dart';

class AqiReadingModel extends AqiReading {
  const AqiReadingModel({
    required super.parameter,
    required super.value,
    required super.unit,
    required super.city,
  });

  factory AqiReadingModel.fromJson(Map<String, dynamic> j) => AqiReadingModel(
    parameter: j['parameter'] ?? '',
    value:     (j['value'] as num?)?.toDouble() ?? 0.0,
    unit:      j['unit'] ?? 'µg/m³',
    city:      j['city'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'parameter': parameter,
    'value': value,
    'unit': unit,
    'city': city,
  };
}
