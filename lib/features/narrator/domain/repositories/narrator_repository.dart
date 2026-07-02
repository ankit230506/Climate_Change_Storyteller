import 'dart:typed_data';
import '../../../explore/domain/entities/climate_region.dart';
import '../../../explore/domain/entities/climate_era.dart';
import '../../../climate_data/domain/entities/climate_stats.dart';
import '../entities/narration_result.dart';

abstract class NarratorRepository {
  Future<NarrationResult> generateNarration({
    required ClimateRegion region,
    required ClimateEra era,
    required VoiceStyle style,
    ClimateStats? stats,
  });

  Future<Uint8List?> synthesizeVoice(String text, {VoiceStyle style = VoiceStyle.natural});
}
