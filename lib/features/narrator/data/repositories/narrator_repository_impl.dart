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
    if (apiKey == null || apiKey.isEmpty) {
      return const NarrationResult.error('No Gemini API key. Go to Settings → API Setup.');
    }

    final regionData = getRegionData(region.id);
    final eraYear = int.parse(era.label);
    final seedText = regionData?.description[eraYear] ?? '';

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
      return NarrationResult.error('Gemini error: $e');
    }
  }

  @override
  Future<Uint8List?> synthesizeVoice(String text, {VoiceStyle style = VoiceStyle.natural}) async {
    final apiKey = await SecureStorageService.instance.getGeminiKey();
    if (apiKey == null || apiKey.isEmpty) return null;
    return await ttsDataSource.synthesizeVoice(text, apiKey, style: style);
  }
}
