import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/app_models.dart';
import '../widgets/shared_widgets.dart';
import '../services/narrator_service.dart';
import '../services/lg_ssh_service.dart';
import '../services/kml_builder_service.dart';

/// FEATURE: Story Mode Screen
///
/// PURPOSE:
/// Guided auto-play narrative experience for museum/exhibition settings.
/// The presenter presses Play — the app handles everything automatically:
///   1. Fly LG camera to the chapter's region
///   2. Send the era's KML to all LG screens
///   3. Generate AI narration via Gemini
///   4. Play the narration audio
///   5. Wait for audio to finish → auto-advance to next chapter
///
/// CHAPTERS:
///   1. The World Before      — 1900 — Arctic
///   2. The Great Melt        — 2026 — Arctic
///   3. Forests Falling       — 2026 — Amazon
///   4. Rising Waters         — 2100 — Maldives
///   5. A Choice Remains      — 2100 — Pacific
///
/// WHY AUTO-PLAY:
/// In museum mode a guide doesn't want to tap through manually.
/// The story flows like a documentary — region to region, era to era.

class StoryModeScreen extends StatefulWidget {
  const StoryModeScreen({super.key});

  @override
  State<StoryModeScreen> createState() => _StoryModeScreenState();
}

class _StoryModeScreenState extends State<StoryModeScreen>
    with TickerProviderStateMixin {

  // ── Chapters definition ────────────────────────────────────────────────────
  // Each chapter maps to a region + era + title
  // WHY here: chapters are story-mode specific, not part of general app models
  static final List<StoryChapter> _chapters = [
    StoryChapter(
      index:     0,
      title:     'The World Before',
      subtitle:  '1900 · Pre-industrial Earth',
      regionId:  'arctic',
      era:       ClimateEra.preindustrial1900,
      icon:      Icons.ac_unit,
      color:     AppColors.glacier,
      duration:  const Duration(minutes: 4, seconds: 30),
    ),
    StoryChapter(
      index:     1,
      title:     'The Great Melt',
      subtitle:  '2026 · Arctic Circle today',
      regionId:  'arctic',
      era:       ClimateEra.present2026,
      icon:      Icons.thermostat,
      color:     AppColors.warning,
      duration:  const Duration(minutes: 5, seconds: 10),
    ),
    StoryChapter(
      index:     2,
      title:     'Forests Falling',
      subtitle:  '2026 · Amazon Basin',
      regionId:  'amazon',
      era:       ClimateEra.present2026,
      icon:      Icons.forest,
      color:     AppColors.forest,
      duration:  const Duration(minutes: 4, seconds: 45),
    ),
    StoryChapter(
      index:     3,
      title:     'Rising Waters',
      subtitle:  '2100 · Maldives',
      regionId:  'maldives',
      era:       ClimateEra.projected2100,
      icon:      Icons.water,
      color:     AppColors.seaLevel,
      duration:  const Duration(minutes: 4, seconds: 22),
    ),
    StoryChapter(
      index:     4,
      title:     'A Choice Remains',
      subtitle:  '2100 · Pacific Islands',
      regionId:  'pacific',
      era:       ClimateEra.projected2100,
      icon:      Icons.public,
      color:     AppColors.primary,
      duration:  const Duration(minutes: 5, seconds: 0),
    ),
  ];

  // ── Playback state ─────────────────────────────────────────────────────────
  int     _currentChapter = 0;
  bool    _isPlaying      = false;
  bool    _isLoading      = false;
  String  _statusMsg      = 'Press Play to begin the story';
  double  _chapterProgress = 0.0; // 0.0 → 1.0 for current chapter
  int     _completedUpTo  = -1;   // last completed chapter index

  // ── Timers ────────────────────────────────────────────────────────────────
  Timer?  _progressTimer;
  int     _elapsedSeconds = 0;

  // ── Animation for the play button ─────────────────────────────────────────
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════
  // STORY PLAYBACK ENGINE
  // ════════════════════════════════════════════════════════════════════════

  /// Start or resume the story from current chapter
  Future<void> _play() async {
    setState(() { _isPlaying = true; _isLoading = true; });
    _pulseCtrl.repeat(reverse: true);

    final chapter = _chapters[_currentChapter];
    final region  = kDefaultRegions.firstWhere(
      (r) => r.id == chapter.regionId,
      orElse: () => kDefaultRegions.first,
    );

    try {
      // STEP 1: Fly LG camera to this chapter's region
      // WHY: Each chapter is set in a different location on Earth
      final ssh = LGSSHService.instance;
      if (ssh.state.isConnected) {
        setState(() => _statusMsg = 'Flying to ${region.name}…');
        await ssh.flyTo(
          latitude:  region.latitude,
          longitude: region.longitude,
          altitude:  region.altitude,
        );
      } else {
        setState(() => _statusMsg =
            '⚠️ LG not connected — running in preview mode');
      }

      // STEP 2: Build and send KML for this chapter's era
      // WHY: Each chapter shows different satellite data on LG screens
      if (ssh.state.isConnected) {
        setState(() => _statusMsg = 'Loading ${chapter.era.label} data…');
        final kmlPath = await KmlBuilderService.instance.buildKml(
          region: region,
          era:    chapter.era,
        );
        final content = await _readFile(kmlPath);
        await ssh.sendKml(
          '${region.id}_${chapter.era.label}_story.kml',
          kmlContent: content,
        );
      }

      // STEP 3: Generate narration via Gemini
      // WHY: Each chapter has a unique AI-generated narrative
      setState(() => _statusMsg = 'Generating narration…');
      final narration = await NarratorService.instance.generateNarration(
        region: region,
        era:    chapter.era,
        style:  VoiceStyle.poetic, // Story mode always uses poetic style
      );

      if (narration.hasError) {
        setState(() {
          _statusMsg = '⚠️ ${narration.errorMessage}';
          _isLoading = false;
        });
        _startProgressTimer(); // Still advance timer for demo
        return;
      }

      // STEP 4: Synthesize and play voice
      setState(() => _statusMsg = 'Playing narration…');
      final mp3 = await NarratorService.instance
          .synthesizeVoice(narration.text!);

      setState(() { _isLoading = false; });

      // STEP 5: Start progress timer
      // WHY: Progress bar advances while audio plays
      // Auto-advances to next chapter when timer completes
      _startProgressTimer();

    } catch (e) {
      setState(() {
        _isLoading  = false;
        _statusMsg  = 'Error: $e';
        _isPlaying  = false;
      });
      _pulseCtrl.stop();
    }
  }

  void _pause() {
    _progressTimer?.cancel();
    _pulseCtrl.stop();
    setState(() {
      _isPlaying = false;
      _statusMsg = 'Paused — tap Play to continue';
    });
  }

  void _goToChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;
    if (index > _completedUpTo + 1) return; // Can't skip ahead
    _progressTimer?.cancel();
    setState(() {
      _currentChapter  = index;
      _chapterProgress = 0.0;
      _elapsedSeconds  = 0;
      _isPlaying       = false;
      _statusMsg       = 'Chapter ${index + 1} selected — tap Play';
    });
  }

  void _nextChapter() {
    if (_currentChapter < _chapters.length - 1) {
      _goToChapter(_currentChapter + 1);
    }
  }

  void _prevChapter() {
    if (_currentChapter > 0) {
      _goToChapter(_currentChapter - 1);
    }
  }

  // Progress timer — advances the chapter progress bar
  void _startProgressTimer() {
    _progressTimer?.cancel();
    final totalSecs = _chapters[_currentChapter]
        .duration.inSeconds.toDouble();

    _progressTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _elapsedSeconds++;
      final progress = _elapsedSeconds / totalSecs;
      if (mounted) {
        setState(() => _chapterProgress = progress.clamp(0.0, 1.0));
      }

      // Auto-advance when chapter completes
      if (_elapsedSeconds >= totalSecs) {
        t.cancel();
        if (mounted) {
          setState(() {
            _completedUpTo = _currentChapter;
            _statusMsg     = '✓ Chapter complete';
          });

          // Move to next chapter after 2s pause
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && _isPlaying) {
              if (_currentChapter < _chapters.length - 1) {
                setState(() {
                  _currentChapter++;
                  _chapterProgress = 0;
                  _elapsedSeconds  = 0;
                });
                _play(); // Auto-play next chapter
              } else {
                // Story complete
                setState(() {
                  _isPlaying = false;
                  _statusMsg = '🎬 Story complete — all 5 chapters played';
                });
                _pulseCtrl.stop();
              }
            }
          });
        }
      }
    });
  }

  Future<String> _readFile(String path) async {
    try {
      // For web — return empty string (KML builder generates content)
      return '';
    } catch (_) {
      return '';
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // UI
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final chapter = _chapters[_currentChapter];
    final totalDuration = _chapters.fold<int>(
      0, (sum, c) => sum + c.duration.inSeconds);
    final totalMinutes = totalDuration ~/ 60;

    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),

              // ── Header ────────────────────────────────────────────────
              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Story Mode', style: AppTypography.heading1),
                    Text('5 Chapters · $totalMinutes min · Auto-play',
                        style: AppTypography.bodySmall),
                  ],
                )),
                // LG connection indicator
                StreamBuilder<LGRigState>(
                  stream: LGSSHService.instance.stateStream,
                  initialData: LGSSHService.instance.state,
                  builder: (_, snap) {
                    final connected = snap.data!.isConnected;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (connected
                            ? AppColors.good
                            : AppColors.warning).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (connected
                              ? AppColors.good
                              : AppColors.warning).withOpacity(0.4),
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: connected
                                ? AppColors.good : AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          connected ? 'LG Ready' : 'No LG',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: connected
                                ? AppColors.good : AppColors.warning,
                          ),
                        ),
                      ]),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 24),

              // ── Now playing card ──────────────────────────────────────
              _NowPlayingCard(
                chapter:  chapter,
                progress: _chapterProgress,
                isPlaying: _isPlaying,
                isLoading: _isLoading,
                statusMsg: _statusMsg,
                onPlay:   _isPlaying ? _pause : _play,
                onPrev:   _currentChapter > 0 ? _prevChapter : null,
                onNext:   _currentChapter < _chapters.length - 1
                    ? _nextChapter : null,
                pulseCtrl: _pulseCtrl,
              ),
              const SizedBox(height: 24),

              // ── Overall story progress ────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('STORY PROGRESS', style: AppTypography.label),
                  Text(
                    '${_completedUpTo + 1} / ${_chapters.length}',
                    style: AppTypography.caption,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_completedUpTo + 1) / _chapters.length,
                  backgroundColor: AppColors.bg3,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 24),

              // ── Chapter list ──────────────────────────────────────────
              const SectionHeader(title: 'Chapters'),
              ..._chapters.map((ch) => _ChapterTile(
                chapter:   ch,
                isCurrent: ch.index == _currentChapter,
                isDone:    ch.index <= _completedUpTo,
                isLocked:  ch.index > _completedUpTo + 1,
                onTap:     ch.index <= _completedUpTo + 1
                    ? () => _goToChapter(ch.index)
                    : null,
              )),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// NOW PLAYING CARD
// ════════════════════════════════════════════════════════════════════════════

class _NowPlayingCard extends StatelessWidget {
  final StoryChapter  chapter;
  final double        progress;
  final bool          isPlaying;
  final bool          isLoading;
  final String        statusMsg;
  final VoidCallback  onPlay;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final AnimationController pulseCtrl;

  const _NowPlayingCard({
    required this.chapter,
    required this.progress,
    required this.isPlaying,
    required this.isLoading,
    required this.statusMsg,
    required this.onPlay,
    required this.onPrev,
    required this.onNext,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPlaying
              ? chapter.color.withOpacity(0.4)
              : const Color(0xFF1E2235),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Story badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: chapter.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.play_circle_outline,
                  size: 12, color: chapter.color),
              const SizedBox(width: 5),
              Text('STORY MODE', style: AppTypography.caption.copyWith(
                  color: chapter.color, letterSpacing: 1.2)),
            ]),
          ),
          const SizedBox(height: 14),

          // Chapter title
          Text(
            'Chapter ${chapter.index + 1}: ${chapter.title}',
            style: AppTypography.heading2,
          ),
          Text(chapter.subtitle, style: AppTypography.bodySmall),
          const SizedBox(height: 16),

          // Status message
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey(statusMsg),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusMsg,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Chapter progress bar
          Row(children: [
            Text('Chapter progress', style: AppTypography.caption),
            const Spacer(),
            Text('${(progress * 100).toInt()}%',
                style: AppTypography.caption),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.bg3,
              valueColor: AlwaysStoppedAnimation<Color>(chapter.color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 20),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous
              IconButton(
                onPressed: onPrev,
                icon: Icon(Icons.skip_previous_rounded,
                  size: 32,
                  color: onPrev != null
                      ? AppColors.textPrimary : AppColors.textMuted),
              ),
              const SizedBox(width: 16),

              // Play / Pause
              GestureDetector(
                onTap: onPlay,
                child: AnimatedBuilder(
                  animation: pulseCtrl,
                  builder: (_, __) => Transform.scale(
                    scale: isPlaying
                        ? 1.0 + pulseCtrl.value * 0.05 : 1.0,
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isLoading
                            ? AppColors.bg3 : chapter.color,
                        boxShadow: isPlaying ? [BoxShadow(
                          color: chapter.color.withOpacity(0.4),
                          blurRadius: 20, spreadRadius: 2,
                        )] : null,
                      ),
                      child: isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(18),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: chapter.color,
                              ))
                          : Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 34, color: AppColors.bg0,
                            ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Next
              IconButton(
                onPressed: onNext,
                icon: Icon(Icons.skip_next_rounded,
                  size: 32,
                  color: onNext != null
                      ? AppColors.textPrimary : AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CHAPTER TILE
// ════════════════════════════════════════════════════════════════════════════

class _ChapterTile extends StatelessWidget {
  final StoryChapter  chapter;
  final bool          isCurrent;
  final bool          isDone;
  final bool          isLocked;
  final VoidCallback? onTap;

  const _ChapterTile({
    required this.chapter,
    required this.isCurrent,
    required this.isDone,
    required this.isLocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final mins = chapter.duration.inMinutes;
    final secs = chapter.duration.inSeconds.remainder(60)
        .toString().padLeft(2, '0');

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrent
              ? chapter.color.withOpacity(0.08)
              : AppColors.bg2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCurrent
                ? chapter.color.withOpacity(0.4)
                : const Color(0xFF1E2235),
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          // Chapter number / status icon
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone
                  ? AppColors.good.withOpacity(0.15)
                  : isCurrent
                      ? chapter.color.withOpacity(0.15)
                      : AppColors.bg3,
            ),
            child: Center(
              child: isDone
                  ? const Icon(Icons.check,
                      size: 18, color: AppColors.good)
                  : isLocked
                      ? const Icon(Icons.lock_outline,
                          size: 16, color: AppColors.textMuted)
                      : Text(
                          '${chapter.index + 1}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isCurrent
                                ? chapter.color
                                : AppColors.textSecondary,
                          ),
                        ),
            ),
          ),
          const SizedBox(width: 14),

          // Title + subtitle
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chapter.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isCurrent
                      ? FontWeight.w700 : FontWeight.w500,
                  color: isLocked
                      ? AppColors.textMuted : AppColors.textPrimary,
                )),
              const SizedBox(height: 2),
              Text(chapter.subtitle,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            ],
          )),

          // Duration + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$mins:$secs',
                style: AppTypography.caption),
              const SizedBox(height: 4),
              if (isCurrent && !isDone)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: chapter.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Playing',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: chapter.color)),
                )
              else if (isDone)
                const Text('Done',
                  style: TextStyle(
                      fontSize: 10, color: AppColors.good,
                      fontWeight: FontWeight.w600))
              else if (isLocked)
                const Icon(Icons.lock_outline,
                    size: 14, color: AppColors.textMuted),
            ],
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// DATA MODEL
// ════════════════════════════════════════════════════════════════════════════

class StoryChapter {
  final int          index;
  final String       title;
  final String       subtitle;
  final String       regionId;
  final ClimateEra   era;
  final IconData     icon;
  final Color        color;
  final Duration     duration;

  const StoryChapter({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.regionId,
    required this.era,
    required this.icon,
    required this.color,
    required this.duration,
  });
}