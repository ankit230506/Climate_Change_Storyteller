enum VoiceStyle { natural, poetic, scientific }

class NarrationResult {
  final String? text, region, era, errorMessage;
  final VoiceStyle? style;

  bool get hasError => errorMessage != null;
  bool get isValid  => text != null && text!.isNotEmpty;

  const NarrationResult({
    required this.text,
    required this.region,
    required this.era,
    required this.style,
  }) : errorMessage = null;

  const NarrationResult.error(this.errorMessage)
      : text = null,
        region = null,
        era = null,
        style = null;
}
