import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

enum VoiceStyle { natural, poetic, scientific }

enum PlaybackSpeed { slow, normal, fast }

class NarratorScreen extends StatefulWidget {
  const NarratorScreen({super.key});

  @override
  State<NarratorScreen> createState() => _NarratorScreenState();
}

class _NarratorScreenState extends State<NarratorScreen>
    with TickerProviderStateMixin {
  VoiceStyle _voiceStyle = VoiceStyle.natural;
  PlaybackSpeed _speed = PlaybackSpeed.normal;
  bool _isPlaying = false;
  double _progress = 0.48; // 0.0 – 1.0
  int _currentChapter = 1;

  late final AnimationController _waveCtrl;

  static const _chapters = [
    _Chapter(index: 0, title: 'The World Before', era: '1900', done: true),
    _Chapter(index: 1, title: 'The Great Melt', era: '1900–2026', done: false),
    _Chapter(
        index: 2, title: 'A World Without Ice', era: '2100', done: false),
  ];

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text('AI Narrator', style: AppTypography.heading1),
              Text('Gemini · Google TTS', style: AppTypography.bodySmall),
              const SizedBox(height: 24),

              // ── Playback card ───────────────────────
              _PlaybackCard(
                chapter: _chapters[_currentChapter],
                isPlaying: _isPlaying,
                progress: _progress,
                waveCtrl: _waveCtrl,
                onPlayPause: () => setState(() => _isPlaying = !_isPlaying),
                onPrev: _currentChapter > 0
                    ? () => setState(() => _currentChapter--)
                    : null,
                onNext: _currentChapter < _chapters.length - 1
                    ? () => setState(() => _currentChapter++)
                    : null,
                onSeek: (v) => setState(() => _progress = v),
              ),
              const SizedBox(height: 24),

              // ── Voice style ────────────────────────
              const SectionHeader(title: 'Voice Style'),
              Row(
                children: VoiceStyle.values.map((s) {
                  final active = s == _voiceStyle;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: s != VoiceStyle.values.last ? 8 : 0),
                      child: GestureDetector(
                        onTap: () => setState(() => _voiceStyle = s),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary.withOpacity(0.15)
                                : AppColors.bg3,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: active
                                  ? AppColors.primary
                                  : const Color(0xFF252840),
                            ),
                          ),
                          child: Text(
                            s.name[0].toUpperCase() + s.name.substring(1),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: active
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // ── Chapters ────────────────────────────
              const SectionHeader(title: 'Chapters'),
              ..._chapters.map((ch) => _ChapterTile(
                    chapter: ch,
                    isActive: ch.index == _currentChapter,
                    onTap: () => setState(() => _currentChapter = ch.index),
                  )),
              const SizedBox(height: 24),

              // ── Playback speed ──────────────────────
              const SectionHeader(title: 'Playback Speed'),
              Row(
                children: PlaybackSpeed.values.map((s) {
                  final active = s == _speed;
                  final label = switch (s) {
                    PlaybackSpeed.slow => '0.75×',
                    PlaybackSpeed.normal => '1.0×',
                    PlaybackSpeed.fast => '1.5×',
                  };
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: s != PlaybackSpeed.values.last ? 8 : 0),
                      child: GestureDetector(
                        onTap: () => setState(() => _speed = s),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary.withOpacity(0.15)
                                : AppColors.bg3,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: active
                                  ? AppColors.primary
                                  : const Color(0xFF252840),
                            ),
                          ),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: active
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Playback card ─────────────────────────────────────────────────────────────

class _PlaybackCard extends StatelessWidget {
  final _Chapter chapter;
  final bool isPlaying;
  final double progress;
  final AnimationController waveCtrl;
  final VoidCallback onPlayPause;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<double> onSeek;

  const _PlaybackCard({
    required this.chapter,
    required this.isPlaying,
    required this.progress,
    required this.waveCtrl,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'NOW PLAYING',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Chapter ${chapter.index + 1}: ${chapter.title}',
              style: AppTypography.heading3),
          Text('Arctic Circle · ${chapter.era}',
              style: AppTypography.bodySmall),
          const SizedBox(height: 16),

          // Waveform
          _Waveform(controller: waveCtrl, isPlaying: isPlaying),
          const SizedBox(height: 8),

          // Progress
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: progress,
              onChanged: onSeek,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration((progress * 310).round()),
                style: AppTypography.caption,
              ),
              Text('5:10', style: AppTypography.caption),
            ],
          ),
          const SizedBox(height: 16),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: onPrev,
                icon: Icon(
                  Icons.skip_previous_rounded,
                  size: 32,
                  color: onPrev != null
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: onPlayPause,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 28,
                    color: AppColors.bg0,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: onNext,
                icon: Icon(
                  Icons.skip_next_rounded,
                  size: 32,
                  color: onNext != null
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ── Animated Waveform ─────────────────────────────────────────────────────────

class _Waveform extends StatelessWidget {
  final AnimationController controller;
  final bool isPlaying;

  const _Waveform({required this.controller, required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _WaveformPainter(
              progress: controller.value,
              isPlaying: isPlaying,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;

  _WaveformPainter({required this.progress, required this.isPlaying});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const bars = 40;
    final barWidth = size.width / (bars * 2);
    final rng = math.Random(42);

    for (int i = 0; i < bars; i++) {
      final x = i * barWidth * 2 + barWidth;
      final baseH = rng.nextDouble() * size.height * 0.7 + size.height * 0.1;
      final animated = isPlaying
          ? baseH * (0.6 + 0.4 * math.sin(progress * math.pi * 2 + i * 0.4))
          : baseH * 0.4;
      final y1 = (size.height - animated) / 2;
      final y2 = y1 + animated;

      paint.color = AppColors.primary.withOpacity(0.7);
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.isPlaying != isPlaying;
}

// ── Chapter tile ──────────────────────────────────────────────────────────────

class _Chapter {
  final int index;
  final String title;
  final String era;
  final bool done;

  const _Chapter({
    required this.index,
    required this.title,
    required this.era,
    required this.done,
  });
}

class _ChapterTile extends StatelessWidget {
  final _Chapter chapter;
  final bool isActive;
  final VoidCallback onTap;

  const _ChapterTile({
    required this.chapter,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withOpacity(0.08) : AppColors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withOpacity(0.3)
                : const Color(0xFF1E2235),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: chapter.done
                    ? AppColors.good.withOpacity(0.2)
                    : isActive
                        ? AppColors.primary.withOpacity(0.2)
                        : AppColors.bg3,
              ),
              child: Center(
                child: chapter.done
                    ? const Icon(Icons.check, size: 16, color: AppColors.good)
                    : Text(
                        '${chapter.index + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chapter.title, style: AppTypography.heading3),
                  Text(
                    isActive ? '5:10 · Playing' : '4:22 · ${chapter.era}',
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}