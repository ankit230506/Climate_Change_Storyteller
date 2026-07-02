import '../../../explore/domain/entities/climate_region.dart';
import '../../../explore/domain/entities/climate_era.dart';
import '../../../climate_data/domain/entities/climate_stats.dart';
import '../entities/narration_result.dart';
import '../repositories/narrator_repository.dart';

class GetNarration {
  final NarratorRepository repository;
  GetNarration(this.repository);

  Future<NarrationResult> call({
    required ClimateRegion region,
    required ClimateEra era,
    required VoiceStyle style,
    ClimateStats? stats,
  }) {
    return repository.generateNarration(
      region: region,
      era: era,
      style: style,
      stats: stats,
    );
  }
}
