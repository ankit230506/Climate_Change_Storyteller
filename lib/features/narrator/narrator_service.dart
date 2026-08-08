import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:climate_storyteller/features/explore/climate_region.dart';
import 'package:climate_storyteller/features/explore/climate_era.dart';
import 'package:climate_storyteller/features/climate_data/climate_stats.dart';
import 'package:climate_storyteller/features/narrator/narration_result.dart';
import 'package:climate_storyteller/core/storage/secure_storage_service.dart';
import 'package:climate_storyteller/features/climate_data/ipcc_data.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/core/localization/language_service.dart';

class NarratorService {
  static const _geminiModel = 'gemini-1.5-flash';
  static const _geminiBase =
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent';

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

    final prompt = _buildPrompt(
      region: region,
      era: era,
      style: style,
      seedText: seedText,
      stats: stats,
    );

    try {
      final text = await _callGemini(apiKey, prompt);
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

  Future<Uint8List?> synthesizeVoice(String text, {VoiceStyle style = VoiceStyle.natural}) async {
    final apiKey = await SecureStorageService.instance.getGeminiKey() ?? '';
    final AppLanguage currentLang = DI.languageService.currentLanguage;
    final voiceName = currentLang.cloudTtsVoices[style] ?? 'en-US-Neural2-F';
    final localeCode = currentLang.localeCode;

    final speakingRate = switch (style) {
      VoiceStyle.natural    => 1.0,
      VoiceStyle.poetic     => 0.85,
      VoiceStyle.scientific => 1.1,
    };

    if (apiKey.isEmpty) {
      return await _fallbackSynthesize(text);
    }

    try {
      final uri = Uri.parse('https://texttospeech.googleapis.com/v1/text:synthesize?key=$apiKey');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'input': {'text': text},
          'voice': {'languageCode': localeCode, 'name': voiceName},
          'audioConfig': {
            'audioEncoding': 'MP3',
            'speakingRate': speakingRate,
          },
        }),
      );

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final audioContent = json['audioContent'] as String?;
        if (audioContent != null) {
          return base64Decode(audioContent);
        }
      }
    } catch (_) {}

    // Fallback to unauthenticated Translate TTS API
    return await _fallbackSynthesize(text);
  }

  // ─────────────────────────────────────────────
  // Private Helper Methods
  // ─────────────────────────────────────────────

  Future<String> _callGemini(String apiKey, String prompt) async {
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

  String _buildPrompt({
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

    final langName = DI.languageService.currentLanguage.name;

    return '''You are a climate narrator for a Liquid Galaxy museum display.

Region: ${region.name}
Era: ${era.label} (${era.subtitle})
Category: ${region.category}

Background context: $seedText

Live climate data: $statsText

Style instruction: $styleGuide

Write exactly 3 short paragraphs (2-3 sentences each, ~150 words total).
No bullet points, no headers, no markdown.
Written for speaking aloud to museum visitors.

IMPORTANT: The narration MUST be written entirely in $langName. Under no circumstances should you output in English unless the requested language is English.''';
  }

  Future<Uint8List?> _fallbackSynthesize(String text) async {
    final chunks = _splitIntoChunks(text, 150);
    final List<int> allBytes = [];
    final langCode = DI.languageService.currentLanguage.code;
    for (final chunk in chunks) {
      if (chunk.trim().isEmpty) continue;
      try {
        final uri = Uri.parse(
          'https://translate.google.com/translate_tts'
          '?ie=UTF-8&tl=$langCode&client=tw-ob'
          '&q=${Uri.encodeComponent(chunk)}'
        );
        final res = await http.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        });
        if (res.statusCode == 200) {
          allBytes.addAll(res.bodyBytes);
        }
      } catch (_) {
        return null;
      }
    }
    return Uint8List.fromList(allBytes);
  }

  List<String> _splitIntoChunks(String text, int maxLength) {
    final List<String> chunks = [];
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    String currentChunk = '';
    for (final sentence in sentences) {
      if (currentChunk.length + sentence.length + 1 > maxLength) {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk);
          currentChunk = sentence;
        } else {
          chunks.add(sentence);
        }
      } else {
        if (currentChunk.isEmpty) {
          currentChunk = sentence;
        } else {
          currentChunk += ' $sentence';
        }
      }
    }
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk);
    }
    return chunks;
  }
}
