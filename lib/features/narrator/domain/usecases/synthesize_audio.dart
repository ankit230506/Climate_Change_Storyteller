import 'dart:typed_data';
import '../entities/narration_result.dart';
import '../repositories/narrator_repository.dart';

class SynthesizeAudio {
  final NarratorRepository repository;
  SynthesizeAudio(this.repository);

  Future<Uint8List?> call(String text, {VoiceStyle style = VoiceStyle.natural}) {
    return repository.synthesizeVoice(text, style: style);
  }
}
