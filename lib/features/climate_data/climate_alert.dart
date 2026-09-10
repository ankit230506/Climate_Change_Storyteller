/// Model representing a real-time climate alert (wildfire, extreme weather, AQI spike).
class ClimateAlert {
  final String id;
  final String title;
  final String description;
  final AlertType type;
  final AlertSeverity severity;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? source;

  const ClimateAlert({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.severity,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.source,
  });
}

enum AlertType {
  wildfire(label: 'Wildfire', emoji: '🔥'),
  extremeWeather(label: 'Extreme Weather', emoji: '⛈️'),
  aqiSpike(label: 'AQI Spike', emoji: '💨'),
  flood(label: 'Flood', emoji: '🌊'),
  heatwave(label: 'Heatwave', emoji: '🌡️');

  const AlertType({required this.label, required this.emoji});
  final String label;
  final String emoji;
}

enum AlertSeverity {
  low(label: 'Low', priority: 0),
  moderate(label: 'Moderate', priority: 1),
  high(label: 'High', priority: 2),
  extreme(label: 'Extreme', priority: 3);

  const AlertSeverity({required this.label, required this.priority});
  final String label;
  final int priority;
}
