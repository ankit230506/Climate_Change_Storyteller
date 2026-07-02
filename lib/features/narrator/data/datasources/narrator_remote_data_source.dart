import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../explore/domain/entities/climate_region.dart';
import '../../../explore/domain/entities/climate_era.dart';
import '../../../climate_data/domain/entities/climate_stats.dart';
import '../../domain/entities/narration_result.dart';

abstract class NarratorRemoteDataSource {
  Future<String> callGemini(String apiKey, String prompt);
  String buildPrompt({
    required ClimateRegion region,
    required ClimateEra era,
    required VoiceStyle style,
    required String seedText,
    ClimateStats? stats,
  });
}

class NarratorRemoteDataSourceImpl implements NarratorRemoteDataSource {
  static const _geminiModel = 'gemini-1.5-flash';
  static const _geminiBase  =
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent';

  @override
  Future<String> callGemini(String apiKey, String prompt) async {
    final uri = Uri.parse('$_geminiBase?key=$apiKey');

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {'parts': [{'text': prompt}]}
        ],
        'generationConfig': {
          'temperature':     0.8,
          'maxOutputTokens': 500,
          'topP':            0.9,
        },
      }),
    ).timeout(const Duration(seconds: 30));

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final text = json['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      if (text != null && text.isNotEmpty) return text;
      throw Exception('Empty response from Gemini');
    }

    if (res.statusCode == 400) {
      throw Exception('Bad request — check API key format');
    }
    if (res.statusCode == 401) {
      throw Exception('Invalid Gemini API key — go to Settings → API Setup');
    }
    if (res.statusCode == 403) {
      throw Exception('API key not authorized for Gemini — enable it at aistudio.google.com');
    }
    if (res.statusCode == 404) {
      throw Exception('Model not found — check internet connection');
    }
    if (res.statusCode == 429) {
      throw Exception('Rate limit reached — wait 1 minute and try again');
    }

    throw Exception('Gemini error ${res.statusCode}: ${res.body}');
  }

  @override
  String buildPrompt({
    required ClimateRegion region,
    required ClimateEra era,
    required VoiceStyle style,
    required String seedText,
    ClimateStats? stats,
  }) {
    final styleGuide = switch (style) {
      VoiceStyle.natural    => 'Warm, conversational. Like a knowledgeable friend.',
      VoiceStyle.poetic     => 'Lyrical, evocative. Like a nature documentary narrator.',
      VoiceStyle.scientific => 'Precise, data-focused. Cite specific numbers.',
    };

    final statsText = stats != null
        ? 'Temp anomaly: ${stats.tempLabel}, Sea level: ${stats.seaLabel}, '
          'Ice extent: ${stats.iceLabel}, Forest loss: ${stats.forestLabel}'
        : '';

    return '''You are a climate narrator for a Liquid Galaxy museum display.

Region: ${region.name}
Era: ${era.label} (${era.subtitle})
Category: ${region.category}

Background context: $seedText

Live climate data: $statsText

Style instruction: $styleGuide

Write exactly 3 short paragraphs (2-3 sentences each, ~150 words total).
No bullet points, no headers, no markdown.
Written for speaking aloud to museum visitors.''';
  }
}
