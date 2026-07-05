import 'dart:typed_data';
import '../../../explore/domain/entities/climate_region.dart';
import '../../../explore/domain/entities/climate_era.dart';
import '../../../climate_data/domain/entities/climate_stats.dart';
import '../../domain/entities/narration_result.dart';
import '../../domain/repositories/narrator_repository.dart';
import '../datasources/narrator_remote_data_source.dart';
import '../datasources/tts_data_source.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../../../features/climate_data/data/datasources/climate_local_data_source.dart';

class NarratorRepositoryImpl implements NarratorRepository {
  final NarratorRemoteDataSource remoteDataSource;
  final TtsDataSource ttsDataSource;

  NarratorRepositoryImpl({
    required this.remoteDataSource,
    required this.ttsDataSource,
  });

  @override
  Future<NarrationResult> generateNarration({
    required ClimateRegion region,
    required ClimateEra era,
    required VoiceStyle style,
    ClimateStats? stats,
  }) async {
    final apiKey = await SecureStorageService.instance.getGeminiKey();
    final regionData = getRegionData(region.id);
    final eraYear = int.parse(era.label);
    final seedText = regionData?.description[eraYear] ?? '';

    if (apiKey == null || apiKey.isEmpty) {
      return NarrationResult(
        text: seedText,
        region: region.name,
        era: era.label,
        style: style,
      );
    }

    final prompt = remoteDataSource.buildPrompt(
      region: region,
      era: era,
      style: style,
      seedText: seedText,
      stats: stats,
    );

    try {
      final text = await remoteDataSource.callGemini(apiKey, prompt);
      return NarrationResult(
        text: text,
        region: region.name,
        era: era.label,
        style: style,
      );
    } catch (e) {
      // Gracefully fallback to seedText when API call fails
      return NarrationResult(
        text: seedText,
        region: region.name,
        era: era.label,
        style: style,
      );
    }
  }

  @override
  Future<Uint8List?> synthesizeVoice(String text, {VoiceStyle style = VoiceStyle.natural}) async {
    final apiKey = await SecureStorageService.instance.getGeminiKey() ?? '';
    return await ttsDataSource.synthesizeVoice(text, apiKey, style: style);
  }
}
