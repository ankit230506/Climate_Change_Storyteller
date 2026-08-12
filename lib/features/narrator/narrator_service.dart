import 'dart:async';
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:climate_storyteller/features/explore/climate_region.dart';
import 'package:climate_storyteller/features/explore/climate_era.dart';
import 'package:climate_storyteller/features/climate_data/climate_stats.dart';
import 'package:climate_storyteller/features/narrator/narration_result.dart';
import 'package:climate_storyteller/core/storage/secure_storage_service.dart';
import 'package:climate_storyteller/features/climate_data/ipcc_data.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';

class NarratorService {
  static const _geminiModel = 'gemini-1.5-flash';
  static const _geminiBase =
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent';

  final FlutterTts _tts = FlutterTts();
  Completer<void>? _speakCompleter;

  final StreamController<double> _progressCtrl =
      StreamController<double>.broadcast();
  int _totalTextLength = 0;
  Timer? _progressTimer;
  int _speakStartTimeMs = 0;
  int _estimatedDurationMs = 0;

  int _currentOffset = 0;
  int _pausedOffset = 0;
  int _baseOffset = 0;
  String? _lastSpokenText;

  int get pausedOffset => _pausedOffset;
  String? get lastSpokenText => _lastSpokenText;

  void resetPauseState() {
    _pausedOffset = 0;
    _currentOffset = 0;
    _baseOffset = 0;
  }

  /// A stream of 0.0–1.0 values representing TTS playback progress.
  Stream<double> get progressStream => _progressCtrl.stream;

  /// Initialize TTS engine with language and speaking rate.
  Future<void> _ensureTtsInit({VoiceStyle style = VoiceStyle.natural}) async {
    final currentLang = DI.languageService.currentLanguage;

    await _tts.setLanguage(currentLang.localeCode);

    final speakingRate = switch (style) {
      VoiceStyle.natural    => 0.5,
      VoiceStyle.poetic     => 0.4,
      VoiceStyle.scientific => 0.55,
    };
    await _tts.setSpeechRate(speakingRate);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      _stopProgressTimer();
      _progressCtrl.add(1.0);
      _pausedOffset = 0;
      _currentOffset = 0;
      _baseOffset = 0;
      _speakCompleter?.complete();
      _speakCompleter = null;
    });

    _tts.setErrorHandler((msg) {
      _stopProgressTimer();
      _speakCompleter?.completeError(Exception('TTS error: $msg'));
      _speakCompleter = null;
    });

    _tts.setCancelHandler(() {
      _stopProgressTimer();
      _speakCompleter?.complete();
      _speakCompleter = null;
    });

    _tts.setProgressHandler(
        (String text, int startOffset, int endOffset, String word) {
      _currentOffset = _baseOffset + startOffset;
      if (_totalTextLength > 0 && (startOffset + endOffset) > 0) {
        final totalEnd = _baseOffset + endOffset;
        final progress = (totalEnd / _totalTextLength).clamp(0.0, 0.99);
        _progressCtrl.add(progress);
      }
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

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

    if (apiKey == null || apiKey.trim().isEmpty) {
      if (seedText.isNotEmpty) {
        return NarrationResult(
          text: seedText,
          region: region.name,
          era: era.label,
          style: style,
        );
      }
      return const NarrationResult.error('No Gemini API key set. Go to Settings → API Setup.');
    }

    final prompt = _buildPrompt(
      region: region,
      era: era,
      style: style,
      seedText: seedText,
      stats: stats,
    );

    try {
      final text = await _callGemini(apiKey.trim(), prompt);
      return NarrationResult(
        text: text,
        region: region.name,
        era: era.label,
        style: style,
      );
    } catch (e) {
      final cleanMsg = e.toString().replaceAll('Exception: ', '');
      if (seedText.isNotEmpty) {
        return NarrationResult(
          text: seedText,
          region: region.name,
          era: era.label,
          style: style,
        );
      }
      return NarrationResult.error('Gemini API Error: $cleanMsg');
    }
  }

  Future<void> speak(
    String text, {
    VoiceStyle style = VoiceStyle.natural,
    int startFromOffset = 0,
  }) async {
    await _ensureTtsInit(style: style);
    _stopProgressTimer();

    _lastSpokenText = text;
    if (startFromOffset > 0 && startFromOffset < text.length) {
      _baseOffset = startFromOffset;
    } else {
      _baseOffset = 0;
    }

    final textToSpeak = _baseOffset > 0 ? text.substring(_baseOffset) : text;
    _totalTextLength = text.length;
    _currentOffset = _baseOffset;
    _pausedOffset = 0;

    final initialProgress = _totalTextLength > 0 ? (_baseOffset / _totalTextLength) : 0.0;
    final remainingRatio = _totalTextLength > 0 ? ((_totalTextLength - _baseOffset) / _totalTextLength) : 1.0;
    _progressCtrl.add(initialProgress);

    // Calculate estimated speaking duration to drive progress smooth fallback
    final wordCount = textToSpeak.trim().split(RegExp(r'\s+')).length;
    final wordsPerSec = switch (style) {
      VoiceStyle.poetic     => 1.85,
      VoiceStyle.natural    => 2.3,
      VoiceStyle.scientific => 2.6,
    };
    _estimatedDurationMs = (wordCount / wordsPerSec * 1000).round();
    if (_estimatedDurationMs < 2000) _estimatedDurationMs = 2000;

    _speakStartTimeMs = DateTime.now().millisecondsSinceEpoch;

    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - _speakStartTimeMs;
      final p = (initialProgress + (elapsed / _estimatedDurationMs * remainingRatio)).clamp(0.0, 0.99);
      _progressCtrl.add(p);
    });

    _speakCompleter = Completer<void>();
    await _tts.speak(textToSpeak);

    return _speakCompleter!.future;
  }

  /// Stop speaking, recording current character offset so narration can resume from where it stopped.
  Future<void> stop() async {
    _stopProgressTimer();
    _pausedOffset = _currentOffset;
    await _tts.stop();
    _totalTextLength = 0;
    if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
      _speakCompleter!.complete();
      _speakCompleter = null;
    }
  }

  /// Pause speaking.
  Future<void> pause() async {
    _pausedOffset = _currentOffset;
    await _tts.stop();
  }

  /// Resume speaking (Android only — iOS does not support resume).
  /// On unsupported platforms this is a no-op.
  Future<void> resume() async {}

  /// Whether TTS is currently speaking.
  Future<bool> get isSpeaking async {
    return _speakCompleter != null && !_speakCompleter!.isCompleted;
  }

  /// Dispose TTS resources.
  Future<void> dispose() async {
    _stopProgressTimer();
    await _tts.stop();
    _speakCompleter = null;
    _totalTextLength = 0;
    await _progressCtrl.close();
  }



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
          'temperature':     0.95,
          'maxOutputTokens': 2000,
          'topP':            0.95,
        },
      }),
    ).timeout(const Duration(seconds: 60));

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final text = json['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      if (text != null && text.isNotEmpty) return text;
      throw Exception('Empty response from Gemini');
    }

    if (res.statusCode == 400) {
      throw Exception('Bad request');
    }
    if (res.statusCode == 401) {
      throw Exception('Invalid Gemini API key');
    }
    if (res.statusCode == 403) {
      throw Exception('API key not authorized for Gemini');
    }
    if (res.statusCode == 404) {
      throw Exception('Model not found');
    }
    if (res.statusCode == 429) {
      throw Exception('Rate limit reached');
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
    final variationSeed = DateTime.now().microsecondsSinceEpoch;

    final styleGuide = switch (style) {
      VoiceStyle.natural    => '''Warm, conversational, and deeply engaging — like a knowledgeable friend who has
travelled to this region and witnessed its changes first-hand. Use vivid sensory
details (sounds, smells, textures, temperatures) to make the listener feel they
are standing in this landscape. Weave in specific data points naturally within
the storytelling. Include human stories — how communities, wildlife, and
ecosystems are affected in their daily lives.''',
      VoiceStyle.poetic     => '''Lyrical, evocative, and deeply moving — like the narrator of a world-class
nature documentary. Use rich metaphors, flowing imagery, and an emotional arc
that builds from wonder to urgency. Paint word-pictures of landscapes, seasons,
and creatures. Let the language breathe with pauses and rhythm suitable for
spoken delivery. Create a sense of time passing — contrast what was with what
is and what may come.''',
      VoiceStyle.scientific => '''Precise, authoritative, and data-rich — like a lead IPCC scientist briefing
world leaders. Cite specific numbers, percentages, rates of change, and
scientific measurements throughout. Explain cause-and-effect chains clearly.
Reference peer-reviewed research and established climate models. Use technical
terminology but explain it for an educated general audience. Include projections
under different scenarios where relevant.''',
    };

    final statsText = stats != null
        ? 'Current climate data — Temperature anomaly: ${stats.tempLabel}, '
          'Sea level: ${stats.seaLabel}, Ice extent: ${stats.iceLabel}, '
          'Forest loss: ${stats.forestLabel}'
        : '';

    final langName = DI.languageService.currentLanguage.name;

    return '''You are a world-class climate narrator creating content for an immersive museum
exhibition displayed on a Liquid Galaxy panoramic screen system. Your narration
will be read aloud by a text-to-speech engine to museum visitors, so it must be
compelling, detailed, and paced nicely for listener attention.

═══ CONTEXT ═══
Region: ${region.name}
Era: ${era.label} (${era.subtitle})
Category: ${region.category}

Background research: $seedText

Live climate data: $statsText

═══ UNIQUE VARIATION ═══
Seed: $variationSeed
Ensure this narration is completely unique, with a fresh opening perspective, distinct vocabulary, and evocative imagery different from any previous narration for this region.

═══ VOICE & STYLE ═══
$styleGuide

═══ STRUCTURE (follow this arc) ═══
1. SCENE SETTING & CONTEXT — Set the scene and explain the climate situation in this region and era. (3-4 sentences)
2. IMPACTS & HUMAN STORIES — Describe how ecosystems, species, and human communities are affected. (4-5 sentences)
3. FUTURE OUTLOOK — Reflect on what lies ahead, what is at stake, and what choice remains. (3-4 sentences)

═══ REQUIREMENTS ═══
• Write exactly 3 paragraphs following the arc above.
• Total length: 150-200 words. This is critical — do NOT write less or more.
• No bullet points, no headers, no markdown formatting, no numbering.
• Write in flowing, connected prose suitable for speaking aloud.
• Each paragraph should flow naturally into the next.
• Use the background research and live climate data provided above.

IMPORTANT: The narration MUST be written entirely in $langName. Under no
circumstances should you output in English unless the requested language is
English.''';
  }
}
