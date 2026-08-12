import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:climate_storyteller/features/explore/climate_region.dart';
import 'package:climate_storyteller/features/lg_connection/lg_service.dart';

class ClimateYearSlider extends StatefulWidget {
  const ClimateYearSlider({
    super.key,
    required this.lgService,
    required this.region,
    this.initialYear = 2026,
    this.minYear = 1850,
    this.maxYear = 2150,
    this.debounceMs = 80,
    this.onYearChanged,
    this.onYearChangeEnd,
  });

  final LgService lgService;
  final ClimateRegion region;
  final int initialYear;
  final int minYear;
  final int maxYear;

  /// How long to wait after the last drag tick before pushing a full KML
  /// rebuild to the rig. 80ms updates KML ~12 times per second during dragging,
  /// keeping the master KML document timestamp synced with the slider.
  final int debounceMs;

  /// Optional callback when the year changes during dragging.
  final ValueChanged<int>? onYearChanged;

  /// Optional callback when the slider drag ends.
  final ValueChanged<int>? onYearChangeEnd;

  @override
  State<ClimateYearSlider> createState() => _ClimateYearSliderState();
}

class _ClimateYearSliderState extends State<ClimateYearSlider> {
  late double _year;

  // Guards against out-of-order network writes: if the KML for year 1950
  // is still uploading when the user has already dragged to 2040, we
  // drop the stale 1950 result instead of letting it overwrite 2040 on
  // the rig.
  int _requestSeq = 0;

  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear.toDouble().clamp(
          widget.minYear.toDouble(),
          widget.maxYear.toDouble(),
        );
  }

  @override
  void didUpdateWidget(ClimateYearSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialYear != widget.initialYear ||
        oldWidget.region.id != widget.region.id) {
      _year = widget.initialYear.toDouble().clamp(
            widget.minYear.toDouble(),
            widget.maxYear.toDouble(),
          );
      _lastTimeQueryYear = null;
    }
  }

  // ─────────────────────────────────────────────
  // Drag handlers
  // ─────────────────────────────────────────────

  int? _lastTimeQueryYear;
  Timer? _dragKmlTimer;

  @override
  void dispose() {
    _dragKmlTimer?.cancel();
    super.dispose();
  }

  void _onDrag(double value) {
    setState(() => _year = value);
    final year = value.round();

    if (_lastTimeQueryYear != year) {
      _lastTimeQueryYear = year;
      widget.onYearChanged?.call(year);

      // Instantly trigger Google Earth time clock update via /tmp/query.txt
      widget.lgService.sendTimeQuery(
        year,
        latitude: widget.region.latitude,
        longitude: widget.region.longitude,
        altitude: widget.region.altitude,
      );

      // Stream KML payload updates with minimum 40ms latency while sliding
      _dragKmlTimer?.cancel();
      _dragKmlTimer = Timer(const Duration(milliseconds: 40), () {
        if (mounted && _year.round() == year) {
          _pushKmlForYear(year, immediate: false);
        }
      });
    }
  }

  void _onDragEnd(double value) {
    _dragKmlTimer?.cancel();
    final year = value.round();
    _pushKmlForYear(year, immediate: true);
    widget.onYearChangeEnd?.call(year);
  }

  // ─────────────────────────────────────────────
  // KML push (shared by debounced + on-release paths)
  // ─────────────────────────────────────────────

  Future<void> _pushKmlForYear(int year, {required bool immediate}) async {
    final seq = ++_requestSeq;
    if (mounted) setState(() => _isSyncing = true);

    try {
      final path = await widget.lgService.buildKmlForYear(
        region: widget.region,
        year: year,
      );

      // If the user has since dragged further, this result is stale —
      // drop it rather than pushing an out-of-date KML to the rig.
      if (seq != _requestSeq) return;

      final content = await File(path).readAsString();
      if (seq != _requestSeq) return;

      final filename = '${widget.region.id}_year_${year}_${widget.region.category}.kml';

      if (immediate) {
        // Bypass the debounce timer entirely — used on release, so the
        // final state is always pushed without extra delay.
        await widget.lgService.sendKmlRealtime(filename, kmlContent: content);
      } else {
        await widget.lgService.sendKmlDebounced(
          filename,
          kmlContent: content,
          duration: Duration.zero, // already debounced by our own Timer
        );
      }

      // Re-trigger time query immediately after SFTP upload completes to force
      // Google Earth on LG to instantly refresh the displayed KML layer.
      if (seq == _requestSeq) {
        await widget.lgService.sendTimeQuery(
          year,
          latitude: widget.region.latitude,
          longitude: widget.region.longitude,
          altitude: widget.region.altitude,
        );
      }
    } catch (e) {
      debugPrint('ClimateYearSlider: KML push failed for $year: $e');
    } finally {
      if (mounted && seq == _requestSeq) {
        setState(() => _isSyncing = false);
      }
    }
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final year = _year.round();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '${widget.minYear}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Expanded(
          child: Slider(
            min: widget.minYear.toDouble(),
            max: widget.maxYear.toDouble(),
            value: _year,
            label: '$year',
            divisions: widget.maxYear - widget.minYear,
            onChanged: _onDrag,
            onChangeEnd: _onDragEnd,
          ),
        ),
        Text(
          '${widget.maxYear}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 56,
          child: Row(
            children: [
              Text(
                '$year',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (_isSyncing) ...[
                const SizedBox(width: 6),
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}