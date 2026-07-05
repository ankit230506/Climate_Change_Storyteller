import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../domain/entities/narration_result.dart';

abstract class TtsDataSource {
  Future<Uint8List?> synthesizeVoice(String text, String apiKey, {VoiceStyle style = VoiceStyle.natural});
}

class TtsDataSourceImpl implements TtsDataSource {
  @override
  Future<Uint8List?> synthesizeVoice(String text, String apiKey, {VoiceStyle style = VoiceStyle.natural}) async {
    final voiceName = switch (style) {
      VoiceStyle.natural    => 'en-US-Neural2-F',
      VoiceStyle.poetic     => 'en-US-News-K',
      VoiceStyle.scientific => 'en-US-Neural2-H',
    };

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
          'voice': {'languageCode': 'en-US', 'name': voiceName},
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

  Future<Uint8List?> _fallbackSynthesize(String text) async {
    final chunks = _splitIntoChunks(text, 150);
    final List<int> allBytes = [];
    for (final chunk in chunks) {
      if (chunk.trim().isEmpty) continue;
      try {
        final uri = Uri.parse(
          'https://translate.google.com/translate_tts'
          '?ie=UTF-8&tl=en&client=tw-ob'
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
          currentChunk += ' ' + sentence;
        }
      }
    }
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk);
    }
    return chunks;
  }
}
