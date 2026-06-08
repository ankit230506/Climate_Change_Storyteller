import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../data/ipcc_data.dart';
import '../models/app_models.dart';
import '../services/secure_storage_service.dart';
import '../services/climate_data_service.dart';

/// Handles AI narration using Gemini API + Google TTS.
/// WHY HERE: Narration has two steps — text generation (Gemini) and
/// voice synthesis (TTS) — kept together because they're always used
/// as a pair. The Narrator screen calls this service directly.
///
/// Flow:
///   1. Load Gemini key from SecureStorage
///   2. Build prompt from region + era + IPCC stats
///   3. Call Gemini → get narration text
///   4. Call Google TTS → get MP3 bytes
///   5. Return NarrationResult to Narrator screen for playback
class NarratorService {
  NarratorService._();
  static final NarratorService instance = NarratorService._();

  // ── Gemini API ────────────────────────────────────────────────────────────
  // User provides key via API Setup screen → stored in SecureStorage
  // Get a free key at: https://aistudio.google.com/app/apikey
  static const _geminiBase =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent';

  // ── Google TTS (gTTS) ─────────────────────────────────────────────────────
  // Free tier — no key needed for basic usage
  // Uses Google Translate TTS endpoint (same as gTTS Python library)
  static const _ttsBase =
      'https://translate.google.com/translate_tts'
      '?ie=UTF-8&tl=en&client=tw-ob&q=';

  // ════════════════════════════════════════════════════════════════════════
  // GENERATE NARRATION  (Gemini → text)
  // ════════════════════════════════════════════════════════════════════════

  /// Generates AI narration text for a region + era.
  /// Called by: NarratorScreen when user taps play or changes era.
  Future<NarrationResult> generateNarration({
    required ClimateRegion region,
    required ClimateEra    era,
    required VoiceStyle    style,
    ClimateStats?          stats,
  }) async {
    // 1. Get Gemini API key from secure storage
    final apiKey = await SecureStorageService.instance.getGeminiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return NarrationResult.error(
        'No Gemini API key set. Go to Settings → API Setup to add your key.'
      );
    }

    // 2. Get IPCC region data for the seed text
    final regionData  = getRegionData(region.id);
    final eraYear     = int.parse(era.label);
    final seedText    = regionData?.description[eraYear] ?? '';
    final currentStats = stats;

    // 3. Build the prompt
    final prompt = _buildPrompt(
      region:    region,
      era:       era,
      style:     style,
      seedText:  seedText,
      stats:     currentStats,
    );

    // 4. Call Gemini API
    try {
      final text = await _callGemini(apiKey, prompt);
      return NarrationResult(
        text:     text,
        region:   region.name,
        era:      era.label,
        style:    style,
      );
    } catch (e) {
      return NarrationResult.error('Gemini error: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // SYNTHESIZE VOICE  (Google TTS → MP3 bytes)
  // ════════════════════════════════════════════════════════════════════════

  /// Converts narration text to MP3 audio bytes.
  /// Called by: NarratorScreen after generateNarration() succeeds.
  ///
  /// Returns Uint8List of MP3 bytes — play with just_audio or audioplayers.
  Future<Uint8List?> synthesizeVoice(String text) async {
    try {
      // Split into chunks (TTS URL has length limit)
      final chunks  = _splitIntoChunks(text, 200);
      final allBytes = <int>[];

      for (final chunk in chunks) {
        final encoded = Uri.encodeComponent(chunk);
        final uri     = Uri.parse('$_ttsBase$encoded');

        final res = await http.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0',  // Required by Google TTS endpoint
        }).timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          allBytes.addAll(res.bodyBytes);
        }
      }

      return Uint8List.fromList(allBytes);
    } catch (e) {
      print('[NarratorService] TTS synthesis failed: $e');
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // GEMINI API CALL
  // ════════════════════════════════════════════════════════════════════════

  Future<String> _callGemini(String apiKey, String prompt) async {
    final uri = Uri.parse('$_geminiBase?key=$apiKey');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature':     0.8,  // Creative but not wild
        'maxOutputTokens': 400,  // ~3 paragraphs spoken narration
        'topP':            0.9,
      },
      'safetySettings': [
        {
          'category':  'HARM_CATEGORY_DANGEROUS_CONTENT',
          'threshold': 'BLOCK_NONE',
        }
      ],
    });

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 20));

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      // Extract text from Gemini response structure:
      // {candidates: [{content: {parts: [{text: "..."}]}}]}
      final text = json['candidates']?[0]?['content']?['parts']?[0]?['text']
          as String?;
      if (text != null && text.isNotEmpty) return text;
      throw Exception('Empty response from Gemini');
    }

    if (res.statusCode == 401) {
      throw Exception('Invalid Gemini API key. Check Settings → API Setup.');
    }
    if (res.statusCode == 429) {
      throw Exception('Gemini rate limit reached. Wait a moment and try again.');
    }

    throw Exception('Gemini API error ${res.statusCode}: ${res.body}');
  }

  // ════════════════════════════════════════════════════════════════════════
  // PROMPT BUILDER
  // ════════════════════════════════════════════════════════════════════════

  String _buildPrompt({
    required ClimateRegion region,
    required ClimateEra    era,
    required VoiceStyle    style,
    required String        seedText,
    ClimateStats?          stats,
  }) {
    final styleGuide = switch (style) {
      VoiceStyle.natural    =>
        'Write in a warm, conversational tone like a knowledgeable friend '
        'telling a story. Accessible to all ages.',
      VoiceStyle.poetic     =>
        'Write in a lyrical, evocative style with vivid imagery. '
        'Use metaphors and emotional language like a nature documentary narrator.',
      VoiceStyle.scientific =>
        'Write in a precise, data-focused style citing specific numbers. '
        'Like a scientist explaining findings to an informed audience.',
    };

    final statsText = stats != null ? '''
Current data:
- Temperature anomaly: ${stats.tempLabel} above 1900 baseline
- Sea level rise: ${stats.seaLabel}
- Arctic ice extent: ${stats.iceLabel}
- Forest cover lost: ${stats.forestLabel}
Data source: ${stats.source}''' : '';

    return '''You are a climate storyteller narrating an immersive experience 
on a Liquid Galaxy multi-screen display for museum visitors.

Region: ${region.name}
Year/Era: ${era.label} (${era.subtitle})
Category: ${region.category}

Context (use this as a foundation, expand on it):
$seedText

$statsText

Style instruction: $styleGuide

Write exactly 3 paragraphs of spoken narration for this region in ${era.label}.
- Paragraph 1: Set the scene — what does this place look and feel like in ${era.label}?
- Paragraph 2: What has changed or will change? Use the data above.
- Paragraph 3: Why does this matter to people watching right now?

Keep each paragraph 3-4 sentences. 
Write for SPEAKING aloud — no bullet points, no headers, no markdown.
Total length: approximately 200-250 words.''';
  }

  // ════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════════════

  List<String> _splitIntoChunks(String text, int maxLen) {
    final words  = text.split(' ');
    final chunks = <String>[];
    var   current = '';

    for (final word in words) {
      if ((current + word).length > maxLen) {
        if (current.isNotEmpty) chunks.add(current.trim());
        current = '$word ';
      } else {
        current += '$word ';
      }
    }
    if (current.isNotEmpty) chunks.add(current.trim());
    return chunks;
  }
}

// ── Result models ─────────────────────────────────────────────────────────────

enum VoiceStyle { natural, poetic, scientific }

class NarrationResult {
  final String?    text;
  final String?    region;
  final String?    era;
  final VoiceStyle? style;
  final String?    errorMessage;

  bool get hasError => errorMessage != null;
  bool get isValid  => text != null && text!.isNotEmpty;

  const NarrationResult({
    required this.text,
    required this.region,
    required this.era,
    required this.style,
  }) : errorMessage = null;

  const NarrationResult.error(this.errorMessage)
      : text = null, region = null, era = null, style = null;
}