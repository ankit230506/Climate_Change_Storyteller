import 'dart:async';
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';
import 'package:climate_storyteller/features/lg_connection/lg_rig_state.dart';
import 'package:climate_storyteller/features/explore/climate_region.dart';
import 'package:climate_storyteller/features/explore/climate_era.dart';
import 'package:climate_storyteller/features/narrator/narration_result.dart';
import 'package:audioplayers/audioplayers.dart';

class StoryModeScreen extends StatefulWidget {
  const StoryModeScreen({super.key});

  @override
  State<StoryModeScreen> createState() => _StoryModeScreenState();
}

class _StoryModeScreenState extends State<StoryModeScreen>
    with TickerProviderStateMixin {

  static final List<StoryChapter> _chapters = [
    const StoryChapter(
      index:     0,
      title:     'The World Before',
      subtitle:  '1900 · Pre-industrial Earth',
      regionId:  'arctic',
      era:       ClimateEra.preindustrial1900,
      icon:      Icons.ac_unit,
      color:     AppColors.glacier,
      duration:  Duration(minutes: 4, seconds: 30),
    ),
    const StoryChapter(
      index:     1,
      title:     'The Great Melt',
      subtitle:  '2026 · Arctic Circle today',
      regionId:  'arctic',
      era:       ClimateEra.present2026,
      icon:      Icons.thermostat,
      color:     AppColors.warning,
      duration:  Duration(minutes: 5, seconds: 10),
    ),
    const StoryChapter(
      index:     2,
      title:     'Forests Falling',
      subtitle:  '2026 · Amazon Basin',
      regionId:  'amazon',
      era:       ClimateEra.present2026,
      icon:      Icons.forest,
      color:     AppColors.forest,
      duration:  Duration(minutes: 4, seconds: 45),
    ),
    const StoryChapter(
      index:     3,
      title:     'Rising Waters',
      subtitle:  '2100 · Maldives',
      regionId:  'maldives',
      era:       ClimateEra.projected2100,
      icon:      Icons.water,
      color:     AppColors.seaLevel,
      duration:  Duration(minutes: 4, seconds: 22),
    ),
    const StoryChapter(
      index:     4,
      title:     'A Choice Remains',
      subtitle:  '2100 · Pacific Islands',
      regionId:  'pacific',
      era:       ClimateEra.projected2100,
      icon:      Icons.public,
      color:     AppColors.primary,
      duration:  Duration(minutes: 5, seconds: 0),
    ),
  ];

  int     _currentChapter = 0;
  bool    _isPlaying      = false;
  bool    _isLoading      = false;
  String  _statusMsg      = 'Press Play to begin the story';
  double  _chapterProgress = 0.0;
  int     _completedUpTo  = -1;

  Timer?  _progressTimer;
  int     _elapsedSeconds = 0;
  final AudioPlayer _player = AudioPlayer();

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
    _player.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (_elapsedSeconds > 0 && !_isPlaying) {
      await _player.resume();
      setState(() { _isPlaying = true; });
      _pulseCtrl.repeat(reverse: true);
      _startProgressTimer();
      return;
    }

    await _player.stop();
    setState(() { _isPlaying = true; _isLoading = true; });
    _pulseCtrl.repeat(reverse: true);

    final chapter = _chapters[_currentChapter];
    final region  = kDefaultRegions.firstWhere(
      (r) => r.id == chapter.regionId,
      orElse: () => kDefaultRegions.first,
    );

    try {
      final lg = DI.lgService;
      if (lg.state.isConnected) {
        setState(() => _statusMsg = 'Flying to ${region.name}…');
        await DI.lgService.flyTo(
          latitude:  region.latitude,
          longitude: region.longitude,
          altitude:  region.altitude,
        );
      } else {
        setState(() => _statusMsg =
            '⚠️ LG not connected — running in preview mode');
      }

      if (lg.state.isConnected) {
        setState(() => _statusMsg = 'Loading ${chapter.era.label} data…');
        final kmlPath = await DI.lgService.buildKml(
          region: region,
          era:    chapter.era,
        );
        final content = await _readFile(kmlPath);
        await DI.lgService.sendKml(
          '${region.id}_${chapter.era.label}_story.kml',
          kmlContent: content,
        );
      }

      setState(() => _statusMsg = 'Generating narration…');
      final narration = await DI.narratorService.generateNarration(
        region: region,
        era:    chapter.era,
        style:  VoiceStyle.poetic,
      );

      if (narration.hasError) {
        setState(() {
          _statusMsg = '⚠️ ${narration.errorMessage}';
          _isLoading = false;
        });
        _startProgressTimer();
        return;
      }

      setState(() => _statusMsg = 'Synthesizing audio…');
      final narrationText = narration.text ?? '';
      if (narrationText.isEmpty) {
        setState(() {
          _statusMsg = '⚠️ No narration text generated';
          _isLoading = false;
        });
        _startProgressTimer();
        return;
      }

      final mp3Bytes = await DI.narratorService.synthesizeVoice(narrationText, style: VoiceStyle.poetic);
      if (mp3Bytes != null && mp3Bytes.isNotEmpty) {
        await _player.play(BytesSource(mp3Bytes));
        setState(() => _statusMsg = 'Narration playing…');
      } else {
        setState(() => _statusMsg = 'Narration ready (audio failed)');
      }

      setState(() { _isLoading = false; });
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
    _player.pause();
    setState(() {
      _isPlaying = false;
      _statusMsg = 'Paused — tap Play to continue';
    });
  }

  void _goToChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;
    if (index > _completedUpTo + 1 && index > _currentChapter + 1) return;
    _progressTimer?.cancel();
    _player.stop();
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

      if (_elapsedSeconds >= totalSecs) {
        t.cancel();
        if (mounted) {
          setState(() {
            _completedUpTo = _currentChapter;
            _statusMsg     = '✓ Chapter complete';
          });

          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && _isPlaying) {
              if (_currentChapter < _chapters.length - 1) {
                setState(() {
                  _currentChapter++;
                  _chapterProgress = 0;
                  _elapsedSeconds  = 0;
                });
                _play();
              } else {
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
      return await rootBundle.loadString(path);
    } catch (_) {
      try {
        final file = File(path);
        if (await file.exists()) {
          return await file.readAsString();
        }
      } catch (e) {
        debugPrint('Error reading KML file: $e');
      }
      return '';
    }
  }

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

              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Story Mode', style: AppTypography.heading1),
                    Text('5 Chapters · $totalMinutes min · Auto-play',
                        style: AppTypography.bodySmall),
                  ],
                )),
                StreamBuilder<LGRigState>(
                  stream: DI.lgService.stateStream,
                  initialData: DI.lgService.state,
                  builder: (_, snap) {
                    final connected = snap.data!.isConnected;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (connected
                            ? AppColors.good
                            : AppColors.warning).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (connected
                              ? AppColors.good
                              : AppColors.warning).withValues(alpha: 0.4),
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
              ? chapter.color.withValues(alpha: 0.4)
              : const Color(0xFF1E2235),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: chapter.color.withValues(alpha: 0.15),
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

          Text(
            'Chapter ${chapter.index + 1}: ${chapter.title}',
            style: AppTypography.heading2,
          ),
          Text(chapter.subtitle, style: AppTypography.bodySmall),
          const SizedBox(height: 16),

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

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: onPrev,
                icon: Icon(Icons.skip_previous_rounded,
                  size: 32,
                  color: onPrev != null
                      ? AppColors.textPrimary : AppColors.textMuted),
              ),
              const SizedBox(width: 16),

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
                          color: chapter.color.withValues(alpha: 0.4),
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
              ? chapter.color.withValues(alpha: 0.08)
              : AppColors.bg2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCurrent
                ? chapter.color.withValues(alpha: 0.4)
                : const Color(0xFF1E2235),
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone
                  ? AppColors.good.withValues(alpha: 0.15)
                  : isCurrent
                      ? chapter.color.withValues(alpha: 0.15)
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
                    color: chapter.color.withValues(alpha: 0.15),
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
