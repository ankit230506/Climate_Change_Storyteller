import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import '/features/local data/ipcc_data.dart';
import '/models/app_models.dart';
import '/core/storage/secure_storage_service.dart';
import '/services/climate_data_service.dart';

class NarratorService {
  NarratorService._();
  static final NarratorService instance = NarratorService._();

  static const _geminiBase =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent';

  final FlutterTts _tts = FlutterTts();
  bool _ttsInitialized = false;
  bool _isSpeaking = false;

  VoidCallback? onSpeakStart;
  VoidCallback? onSpeakComplete;
  Function(String)? onSpeakError;
  Function(double)? onProgress;

  Future<void> initTts() async {
    if (_ttsInitialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _tts.setStartHandler(() { _isSpeaking = true; onSpeakStart?.call(); });
    _tts.setCompletionHandler(() { _isSpeaking = false; onSpeakComplete?.call(); });
    _tts.setErrorHandler((msg) { _isSpeaking = false; onSpeakError?.call(msg.toString()); });
    _tts.setProgressHandler((text, start, end, word) {
      if (text.isNotEmpty) onProgress?.call((end / text.length).clamp(0.0, 1.0));
    });
    _ttsInitialized = true;
  }

  Future<void> setVoiceStyle(VoiceStyle style) async {
    await initTts();
    switch (style) {
      case VoiceStyle.natural:
        await _tts.setSpeechRate(0.45); await _tts.setPitch(1.0); break;
      case VoiceStyle.poetic:
        await _tts.setSpeechRate(0.38); await _tts.setPitch(0.9); break;
      case VoiceStyle.scientific:
        await _tts.setSpeechRate(0.52); await _tts.setPitch(1.0); break;
    }
  }

  Future<NarrationResult> generateNarration({
    required ClimateRegion region,
    required ClimateEra era,
    required VoiceStyle style,
    ClimateStats? stats,
  }) async {
    final apiKey = await SecureStorageService.instance.getGeminiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return NarrationResult.error('No Gemini API key. Go to Settings → API Setup.');
    }
    final regionData = getRegionData(region.id);
    final eraYear = int.parse(era.label);
    final seedText = regionData?.description[eraYear] ?? '';
    final prompt = _buildPrompt(region: region, era: era, style: style,
        seedText: seedText, stats: stats);
    try {
      final text = await _callGemini(apiKey, prompt);
      return NarrationResult(text: text, region: region.name, era: era.label, style: style);
    } catch (e) {
      return NarrationResult.error('Gemini error: $e');
    }
  }

  Future<void> speak(String text, {VoiceStyle style = VoiceStyle.natural}) async {
    await initTts();
    await setVoiceStyle(style);
    if (_isSpeaking) await stop();
    await _tts.speak(text);
  }

  Future<void> stop() async { await _tts.stop(); _isSpeaking = false; }
  Future<void> pause() async { await _tts.pause(); _isSpeaking = false; }
  bool get isSpeaking => _isSpeaking;

  Future<String> _callGemini(String apiKey, String prompt) async {
    final uri = Uri.parse('$_geminiBase?key=$apiKey');
    final res = await http.post(uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [{'parts': [{'text': prompt}]}],
        'generationConfig': {'temperature': 0.8, 'maxOutputTokens': 400, 'topP': 0.9},
      }),
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final text = json['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      if (text != null && text.isNotEmpty) return text;
      throw Exception('Empty Gemini response');
    }
    if (res.statusCode == 401) throw Exception('Invalid Gemini API key');
    if (res.statusCode == 429) throw Exception('Gemini rate limit — wait a moment');
    throw Exception('Gemini error ${res.statusCode}');
  }

  String _buildPrompt({required ClimateRegion region, required ClimateEra era,
      required VoiceStyle style, required String seedText, ClimateStats? stats}) {
    final styleGuide = switch (style) {
      VoiceStyle.natural    => 'Warm, conversational. Like a knowledgeable friend.',
      VoiceStyle.poetic     => 'Lyrical, evocative. Like a nature documentary.',
      VoiceStyle.scientific => 'Precise, data-focused. Cite specific numbers.',
    };
    final statsText = stats != null
        ? 'Temp: ${stats.tempLabel}, Sea level: ${stats.seaLabel}, '
          'Ice: ${stats.iceLabel}, Forest loss: ${stats.forestLabel}'
        : '';
    return '''Climate narrator for Liquid Galaxy museum display.
Region: ${region.name}, Era: ${era.label} (${era.subtitle})
Background: $seedText
Data: $statsText
Style: $styleGuide
Write 3 short paragraphs (2-3 sentences each, ~150 words total).
No bullet points. Written for speaking aloud.''';
  }

  void dispose() {
    _tts.stop();
    _ttsInitialized = false;
  }
}

enum VoiceStyle { natural, poetic, scientific }


class NarrationResult {
  final String? text, region, era, errorMessage;
  final VoiceStyle? style;
  bool get hasError => errorMessage != null;
  bool get isValid  => text != null && text!.isNotEmpty;
  const NarrationResult({required this.text, required this.region,
      required this.era, required this.style}) : errorMessage = null;
  const NarrationResult.error(this.errorMessage)
      : text = null, region = null, era = null, style = null;
}