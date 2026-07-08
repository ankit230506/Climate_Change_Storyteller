class AqiReading {
  final String parameter; // pm25, pm10, no2, o3
  final double value;
  final String unit;
  final String city;

  const AqiReading({
    required this.parameter,
    required this.value,
    required this.unit,
    required this.city,
  });

  factory AqiReading.fromJson(Map<String, dynamic> j) => AqiReading(
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

enum AqiLevel {
  good, moderate, unhealthySensitive, unhealthy, veryUnhealthy, hazardous;

  String get label => switch (this) {
    AqiLevel.good               => 'Good',
    AqiLevel.moderate           => 'Moderate',
    AqiLevel.unhealthySensitive => 'Unhealthy (Sensitive)',
    AqiLevel.unhealthy          => 'Unhealthy',
    AqiLevel.veryUnhealthy      => 'Very Unhealthy',
    AqiLevel.hazardous          => 'Hazardous',
  };
}
