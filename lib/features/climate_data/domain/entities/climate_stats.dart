/// All climate stats for one era.
class ClimateStats {
  final int    year;
  final double tempAnomaly;    // °C above 1900 baseline
  final double seaLevelMm;     // mm above 1900 baseline
  final double iceExtentMkm2;  // million km²
  final double forestLossPct;  // % of 1900 cover lost
  final String source;         // data attribution string

  const ClimateStats({
    required this.year,
    required this.tempAnomaly,
    required this.seaLevelMm,
    required this.iceExtentMkm2,
    required this.forestLossPct,
    required this.source,
  });

  String get tempLabel    => '${tempAnomaly >= 0 ? '+' : ''}${tempAnomaly.toStringAsFixed(1)}°C';
  String get seaLabel     => '${seaLevelMm.toStringAsFixed(0)} mm';
  String get iceLabel     => '${iceExtentMkm2.toStringAsFixed(1)} M km²';
  String get forestLabel  => '${forestLossPct.toStringAsFixed(1)}% lost';
}
