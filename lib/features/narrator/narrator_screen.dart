import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/core/storage/secure_storage_service.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';
import 'package:climate_storyteller/features/explore/climate_region.dart';
import 'package:climate_storyteller/features/explore/climate_era.dart';
import 'package:climate_storyteller/features/narrator/narration_result.dart';
import 'package:climate_storyteller/core/localization/language_service.dart';
import 'package:climate_storyteller/features/explore/api_setup_screen.dart';

class NarratorScreen extends StatefulWidget {
  const NarratorScreen({super.key});
  @override
  State<NarratorScreen> createState() => _NarratorScreenState();
}

class _NarratorScreenState extends State<NarratorScreen>
    with TickerProviderStateMixin {

  // ── State ─────────────────────────────────────────────────────────────────
  ClimateRegion _region    = kDefaultRegions.first; // Arctic
  ClimateEra    _era       = ClimateEra.present2026;
  VoiceStyle    _style     = VoiceStyle.natural;
  bool          _isPlaying = false;
  bool          _isLoading = false;
  String?       _narrationText;
  String?       _errorMsg;
  bool          _hasApiKey = false;

  // ── Waveform animation ────────────────────────────────────────────────────
  late final AnimationController _waveCtrl;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _checkApiKey();
  }

  Future<void> _checkApiKey() async {
    final has = await SecureStorageService.instance.hasGeminiKey();
    if (mounted) setState(() => _hasApiKey = has);
  }

  Future<void> _openApiSetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ApiSetupScreen()),
    );
    await _checkApiKey();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    DI.narratorService.stop();
    super.dispose();
  }

  Future<void> _generateAndPlay() async {
    await _checkApiKey();

    if (!_hasApiKey) {
      _showNoKeyDialog();
      return;
    }

    setState(() {
      _isLoading    = true;
      _errorMsg     = null;
      _narrationText = null;
    });

    try {
      // Step 1: Generate narration text via Gemini Service
      final result = await DI.narratorService.generateNarration(
        region: _region,
        era:    _era,
        style:  _style,
      );

      if (!mounted) return;

      if (result.hasError) {
        setState(() { _errorMsg = result.errorMessage; _isLoading = false; });
        return;
      }

      setState(() => _narrationText = result.text);

      final narrationText = result.text ?? '';
      if (narrationText.isEmpty) {
        setState(() {
          _errorMsg = 'No narration text generated';
          _isLoading = false;
        });
        return;
      }

      // Step 2: Speak using flutter_tts
      setState(() { _isPlaying = true; _isLoading = false; });
      _waveCtrl.repeat();

      await DI.narratorService.speak(narrationText, style: _style);

      // TTS completed
      if (mounted) {
        setState(() { _isPlaying = false; });
        _waveCtrl.stop();
        _waveCtrl.reset();
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Error: $e';
          _isLoading = false;
          _isPlaying = false;
        });
        _waveCtrl.stop();
        _waveCtrl.reset();
      }
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isLoading) return;

    if (_narrationText == null) {
      await _generateAndPlay();
      return;
    }

    if (_isPlaying) {
      await DI.narratorService.pause();
      _waveCtrl.stop();
      setState(() => _isPlaying = false);
    } else {
      // Re-speak the narration text from beginning
      setState(() => _isPlaying = true);
      _waveCtrl.repeat();

      try {
        await DI.narratorService.speak(_narrationText!, style: _style);
        if (mounted) {
          setState(() => _isPlaying = false);
          _waveCtrl.stop();
          _waveCtrl.reset();
        }
      } catch (e) {
        if (mounted) {
          setState(() { _isPlaying = false; _errorMsg = 'TTS error: $e'; });
          _waveCtrl.stop();
          _waveCtrl.reset();
        }
      }
    }
  }

  Future<void> _stopPlayback() async {
    await DI.narratorService.stop();
    if (mounted) {
      setState(() => _isPlaying = false);
      _waveCtrl.stop();
      _waveCtrl.reset();
    }
  }

  void _showNoKeyDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: const Text('Gemini API Key Required',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Add your free Gemini key in API Setup.\n\n'
          'Get a free key at aistudio.google.com',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openApiSetup();
            },
            child: const Text('API Setup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppLanguage>(
      stream: DI.languageService.languageStream,
      initialData: DI.languageService.currentLanguage,
      builder: (context, langSnap) {
        final colors = AppColors.of(context);
        return Scaffold(
          backgroundColor: colors.bg0,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),

                  // ── Header ──────────────────────────────────────────────────
                  Text(
                    DI.languageService.translate('narrator_title'),
                    style: AppTypography.heading1,
                  ),
                  Text(
                    DI.languageService.translate('narrator_subtitle'),
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: 20),

                  // ── No API key warning ───────────────────────────────────────
                  if (!_hasApiKey)
                    GestureDetector(
                      onTap: _openApiSetup,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.4)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: AppColors.warning, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              DI.languageService.translate('txt_no_gemini_key'),
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.warning),
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: AppColors.warning, size: 18),
                        ]),
                      ),
                    ),

                  // ── Playback card ────────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colors.bg2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.cardBorder),
                      ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Now playing badge
                        if (_isPlaying || _narrationText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(width: 6, height: 6,
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.primary)),
                              const SizedBox(width: 6),
                              Text(
                                  _isPlaying
                                      ? DI.languageService.translate('badge_now_playing')
                                      : DI.languageService.translate('badge_ready'),
                                  style: AppTypography.caption.copyWith(
                                      color: AppColors.primary,
                                      letterSpacing: 1.2)),
                            ]),
                          ),
                        const SizedBox(height: 12),

                        Text(
                          '${_region.name} · ${_era.label}',
                          style: AppTypography.heading3,
                        ),
                        Text(
                          _styleLabel(_style),
                          style: AppTypography.bodySmall,
                        ),
                        const SizedBox(height: 16),

                        // Waveform
                        AnimatedBuilder(
                          animation: _waveCtrl,
                          builder: (_, __) => SizedBox(
                            height: 48,
                            child: CustomPaint(
                              size: const Size(double.infinity, 48),
                              painter: _WavePainter(
                                progress: _waveCtrl.value,
                                isPlaying: _isPlaying,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Play / Pause / Stop buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Stop button
                            if (_isPlaying || _narrationText != null)
                              GestureDetector(
                                onTap: _stopPlayback,
                                child: Container(
                                  width: 44, height: 44,
                                  margin: const EdgeInsets.only(right: 16),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.bg3,
                                    border: Border.all(
                                      color: AppColors.textMuted.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: const Icon(Icons.stop_rounded,
                                      size: 22, color: AppColors.textSecondary),
                                ),
                              ),

                            // Play/Pause button
                            GestureDetector(
                              onTap: _togglePlayPause,
                              child: Container(
                                width: 64, height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isLoading
                                      ? AppColors.bg3 : AppColors.primary,
                                  boxShadow: _isLoading ? null : [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: _isLoading
                                    ? const Padding(
                                        padding: EdgeInsets.all(18),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: AppColors.primary))
                                    : Icon(
                                        _isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        size: 32,
                                        color: AppColors.bg0,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Error message ────────────────────────────────────────────
                  if (_errorMsg != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.critical.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.critical.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.critical, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_errorMsg!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.critical))),
                      ]),
                    ),

                  // ── Generated text preview ───────────────────────────────────
                  if (_narrationText != null) ...[
                    const SizedBox(height: 16),
                    SectionHeader(title: DI.languageService.translate('sec_generated_narration')),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.bg2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.cardBorder),
                      ),
                      child: Text(
                        _narrationText!,
                        style: AppTypography.bodySmall.copyWith(
                          height: 1.7,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // ── Region selector ──────────────────────────────────────────
                  SectionHeader(title: DI.languageService.translate('sec_region')),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: kDefaultRegions.map((r) {
                        final active = r.id == _region.id;
                        return GestureDetector(
                          onTap: () {
                            _stopPlayback();
                            setState(() {
                              _region = r;
                              _narrationText = null;
                              _errorMsg = null;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.primary.withValues(alpha: 0.15)
                                  : colors.bg3,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: active
                                    ? AppColors.primary
                                    : colors.cardBorder,
                              ),
                            ),
                            child: Text(r.name.split(' ').first,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: active
                                    ? FontWeight.w700 : FontWeight.w400,
                                color: active
                                    ? AppColors.primary
                                    : colors.textSecondary,
                              )),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Era selector ─────────────────────────────────────────────
                  SectionHeader(title: DI.languageService.translate('sec_era')),
                  Row(
                    children: ClimateEra.values.map((e) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: e != ClimateEra.values.last ? 8 : 0),
                        child: EraChip(
                          era: e,
                          isSelected: e == _era,
                          onTap: () {
                            _stopPlayback();
                            setState(() {
                              _era = e;
                              _narrationText = null;
                              _errorMsg = null;
                            });
                          },
                        ),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 20),

                  // ── Voice style selector ─────────────────────────────────────
                  SectionHeader(title: DI.languageService.translate('sec_voice_style')),
                  Row(
                    children: VoiceStyle.values.map((s) {
                      final active = s == _style;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              right: s != VoiceStyle.values.last ? 8 : 0),
                          child: GestureDetector(
                            onTap: () {
                              _stopPlayback();
                              setState(() {
                                _style = s;
                                _narrationText = null;
                                _errorMsg = null;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.primary.withValues(alpha: 0.15)
                                    : colors.bg3,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: active
                                      ? AppColors.primary
                                      : colors.cardBorder,
                                ),
                              ),
                              child: Text(
                                _styleName(s),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: active
                                      ? FontWeight.w700 : FontWeight.w400,
                                  color: active
                                      ? AppColors.primary
                                      : colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),

                  // ── Generate button ──────────────────────────────────────────
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _generateAndPlay,
                    icon: _isLoading
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome,
                            size: 18, color: Colors.white),
                    label: Text(
                      _isLoading
                          ? DI.languageService.translate('btn_generating')
                          : DI.languageService.translate('btn_generate_play'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _styleName(VoiceStyle s) => switch (s) {
    VoiceStyle.natural    => 'Natural',
    VoiceStyle.poetic     => 'Poetic',
    VoiceStyle.scientific => 'Scientific',
  };

  String _styleLabel(VoiceStyle s) => switch (s) {
    VoiceStyle.natural    => 'Natural voice · Conversational',
    VoiceStyle.poetic     => 'Poetic voice · Lyrical',
    VoiceStyle.scientific => 'Scientific voice · Data-focused',
  };
}

class _WavePainter extends CustomPainter {
  final double progress;
  final bool   isPlaying;
  _WavePainter({required this.progress, required this.isPlaying});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const bars   = 36;
    final spacing = size.width / bars;
    final rng    = math.Random(42);

    for (int i = 0; i < bars; i++) {
      final x      = i * spacing + spacing / 2;
      final baseH  = rng.nextDouble() * size.height * 0.6 + size.height * 0.1;
      final h      = isPlaying
          ? baseH * (0.5 + 0.5 * math.sin(
              progress * math.pi * 2 + i * 0.5))
          : baseH * 0.25;
      final y1 = (size.height - h) / 2;
      final y2 = y1 + h;
      paint.color = AppColors.primary.withValues(
          alpha: isPlaying ? 0.8 : 0.3);
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.isPlaying != isPlaying;
}
