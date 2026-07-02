import '../../domain/entities/climate_stats.dart';

class ClimateStatsModel extends ClimateStats {
  const ClimateStatsModel({
    required super.year,
    required super.tempAnomaly,
    required super.seaLevelMm,
    required super.iceExtentMkm2,
    required super.forestLossPct,
    required super.source,
  });

  factory ClimateStatsModel.fromJson(Map<String, dynamic> json) {
    return ClimateStatsModel(
      year: json['year'] as int,
      tempAnomaly: (json['tempAnomaly'] as num).toDouble(),
      seaLevelMm: (json['seaLevelMm'] as num).toDouble(),
      iceExtentMkm2: (json['iceExtentMkm2'] as num).toDouble(),
      forestLossPct: (json['forestLossPct'] as num).toDouble(),
      source: json['source'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'year': year,
      'tempAnomaly': tempAnomaly,
      'seaLevelMm': seaLevelMm,
      'iceExtentMkm2': iceExtentMkm2,
      'forestLossPct': forestLossPct,
      'source': source,
    };
  }
}
