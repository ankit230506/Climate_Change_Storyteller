import 'dart:io';
import 'package:flutter/material.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/features/explore/climate_era.dart';
import 'package:climate_storyteller/features/explore/climate_region.dart';
import 'package:climate_storyteller/features/climate_data/climate_stats.dart';
import 'package:climate_storyteller/features/lg_connection/lg_rig_state.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  ClimateEra    _era    = ClimateEra.present2026;
  ClimateRegion _region = kDefaultRegions.first;
  bool          _loading = false;
  String?       _statusMsg;

  ClimateStats? _stats;
  bool _statsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final year  = int.tryParse(_era.label) ?? DateTime.now().year;
      final stats = await DI.climateDataService.getStatsForYear(year);
      if (mounted) setState(() => _stats = stats);
    } catch (e) {
      debugPrint('Stats load error: $e');
    } finally {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _sendKmlToLG() async {
    final lg = DI.lgService;
    if (!lg.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected — go to Settings → Connect to LG Rig'),
        backgroundColor: AppColors.bg2,
      ));
      return;
    }
    setState(() { _loading = true; _statusMsg = 'Building KML…'; });
    try {
      final filename = 'timeline_${_region.id}_${_era.name}.kml';
      setState(() => _statusMsg = 'Fetching NASA GIBS data…');
      final kmlPath = await DI.lgService.buildKml(
        region: _region, era: _era);
      // buildKml() returns a local FILE PATH (it caches the generated KML
      // on disk), not the KML text itself. Passing the path straight into
      // sendKml's kmlContent would upload the literal path string to the
      // rig instead of actual XML — read the file to get the real content.
      final kmlContent = await File(kmlPath).readAsString();

      setState(() => _statusMsg = 'Uploading to rig…');
      await DI.lgService.sendKml(filename, kmlContent: kmlContent);

      setState(() => _statusMsg = 'Flying to ${_region.name}…');
      await DI.lgService.flyTo(
        latitude: _region.latitude,
        longitude: _region.longitude,
        altitude: _region.altitude,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Loaded ${_region.name} (${_era.label}) on LG rig!'),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.critical,
        ));
      }
    } finally {
      if (mounted) setState(() { _loading = false; _statusMsg = null; });
    }
  }

  Future<void> _clearKmlFromLG() async {
    final lg = DI.lgService;
    if (!lg.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected — go to Settings → Connect to LG Rig'),
        backgroundColor: AppColors.bg2,
      ));
      return;
    }
    setState(() { _loading = true; _statusMsg = 'Clearing KMLs…'; });
    try {
      await DI.lgService.clearKml();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cleared all KMLs from LG rig.'),
          backgroundColor: AppColors.good,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error clearing KMLs: $e'),
          backgroundColor: AppColors.critical,
        ));
      }
    } finally {
      if (mounted) setState(() { _loading = false; _statusMsg = null; });
    }
  }

  Future<void> _verifyKmlPipeline(BuildContext context) async {
    final colors = AppColors.of(context);
    final lg = DI.lgService;
    if (!lg.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected — connect to LG Rig first in Settings'),
        backgroundColor: AppColors.bg2,
      ));
      return;
    }

    setState(() { _loading = true; _statusMsg = 'Running diagnostics…'; });

    try {
      final kmlPath = await DI.lgService.buildKml(region: _region, era: _era);
      // Same fix as _sendKmlToLG(): buildKml() returns a path, not content.
      // Reading the file here also makes the byte-count diagnostic below
      // accurate — previously it reported the length of the path string.
      final kmlContent = await File(kmlPath).readAsString();
      final looksValid = kmlContent.trim().startsWith('<?xml') ||
          kmlContent.trim().startsWith('<kml');

      final results = <String, String>{
        'kml_build': looksValid
            ? 'Generated valid-looking KML (${kmlContent.length} bytes) at:\n$kmlPath'
            : '⚠️ Content does NOT look like KML (${kmlContent.length} bytes) — check buildKml()/_generateKml()',
        'lg_connection': 'Connected to LG rig and ready for delivery.',
        'send_ready': 'KML pipeline is available for upload.',
      };

      if (!context.mounted) return;
      setState(() { _loading = false; _statusMsg = null; });

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: colors.bg1,
          title: const Text('KML Pipeline Diagnostic',
              style: TextStyle(color: AppColors.accent, fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: results.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.key.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(e.value,
                          style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 13,
                              fontFamily: 'monospace')),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      setState(() { _loading = false; _statusMsg = null; });

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: colors.bg1,
          title: const Text('Diagnostic Result',
              style: TextStyle(color: AppColors.critical, fontSize: 16)),
          content: Text(e.toString(), style: TextStyle(color: colors.textPrimary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
              Text(_region.name, style: AppTypography.heading1.copyWith(color: colors.textPrimary)),
              Text('Slide to travel through time',
                  style: AppTypography.bodySmall.copyWith(color: colors.textSecondary)),
              const SizedBox(height: 24),

              // ── Era slider ───────────────────────────────────────────────
              _EraSlider(
                selected: _era,
                onChanged: (era) {
                  setState(() => _era = era);
                  _loadStats();
                },
              ),
              const SizedBox(height: 20),

              // ── Big animated year ────────────────────────────────────────
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.3),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                          parent: anim, curve: Curves.easeOut)),
                      child: child,
                    ),
                  ),
                  child: Text(
                    _era.label,
                    key: ValueKey(_era),
                    style: TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -3,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              Center(child: Text(
                _eraSource(_era),
                style: AppTypography.bodySmall.copyWith(color: colors.textSecondary),
              )),
              const SizedBox(height: 24),

              // ── REAL STAT CARDS from NOAA / IPCC ────────────────────────
              const SectionHeader(title: 'Climate Data'),
              if (_statsLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2),
                  ),
                )
              else if (_stats != null) ...[
                Row(children: [
                  Expanded(child: _StatCard(
                    label: 'TEMP ANOMALY',
                    value: _stats!.tempLabel,
                    icon: Icons.thermostat,
                    color: AppColors.heat,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(
                    label: 'SEA LEVEL RISE',
                    value: _stats!.seaLabel,
                    icon: Icons.water,
                    color: AppColors.seaLevel,
                  )),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _StatCard(
                    label: 'ARCTIC ICE',
                    value: _stats!.iceLabel,
                    icon: Icons.ac_unit,
                    color: AppColors.glacier,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(
                    label: 'FOREST LOSS',
                    value: _stats!.forestLabel,
                    icon: Icons.forest,
                    color: AppColors.forest,
                  )),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Source: ${_stats!.source}',
                  style: AppTypography.caption.copyWith(
                      color: colors.textMuted),
                ),
              ],
              const SizedBox(height: 24),

              // ── Region selector ──────────────────────────────────────────
              const SectionHeader(title: 'Region'),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: kDefaultRegions.map((r) {
                    final active = r.id == _region.id;
                    return GestureDetector(
                      onTap: () => setState(() => _region = r),
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
                        child: Text(
                          r.name.split(' ').first,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w700 : FontWeight.w500,
                            color: active
                                ? AppColors.primary
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // ── Era detail cards ─────────────────────────────────────────
              ...ClimateEra.values.map((era) => _EraCard(
                era: era,
                isActive: era == _era,
                onTap: () {
                  setState(() => _era = era);
                  _loadStats();
                },
              )),
              const SizedBox(height: 16),

              // ── LG status ────────────────────────────────────────────────
              StreamBuilder<LGRigState>(
                stream: DI.lgService.stateStream,
                initialData: DI.lgService.state,
                builder: (_, snap) =>
                    LGStatusCard(rigState: snap.data!),
              ),
              const SizedBox(height: 12),

              // ── Status progress ──────────────────────────────────────────
              if (_statusMsg != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary)),
                    const SizedBox(width: 10),
                    Text(_statusMsg!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.primary)),
                  ]),
                ),

              // ── Send KML button ──────────────────────────────────────────
              ElevatedButton.icon(
                onPressed: _loading ? null : _sendKmlToLG,
                icon: _loading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 18, color: Colors.white),
                label: Text(_loading ? 'Sending…' : 'Send KML to LG'),
              ),
              const SizedBox(height: 8),

              // ── Remove KML button ─────────────────────────────────────────
              OutlinedButton.icon(
                onPressed: _loading ? null : _clearKmlFromLG,
                icon: const Icon(Icons.delete_sweep, size: 18, color: AppColors.critical),
                label: const Text('🗑️ Remove All KMLs from LG'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.critical,
                  side: const BorderSide(color: AppColors.critical),
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
              const SizedBox(height: 8),

              // ── Verify KML pipeline diagnostic ────────────────────────────
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _verifyKmlPipeline(context),
                icon: const Icon(Icons.bug_report, size: 18, color: AppColors.accent),
                label: const Text('🔍 Verify KML Pipeline'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _eraSource(ClimateEra era) => switch (era) {
    ClimateEra.preindustrial1900 => 'Pre-industrial baseline · IPCC AR6',
    ClimateEra.present2026       => 'NASA GIBS · NOAA · Currently active',
    ClimateEra.projected2100     => 'IPCC AR6 SSP3-7.0 projection',
  };
}

class _EraSlider extends StatelessWidget {
  final ClimateEra selected;
  final ValueChanged<ClimateEra> onChanged;
  const _EraSlider({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final index = ClimateEra.values.indexOf(selected).toDouble();
    return Column(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: ClimateEra.values.map((e) => Text(
          e.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: e == selected ? FontWeight.w700 : FontWeight.w500,
            color: e == selected
                ? AppColors.primary : colors.textSecondary,
          ),
        )).toList(),
      ),
      const SizedBox(height: 8),
      Slider(min: 0, max: 2, divisions: 2, value: index,
          onChanged: (v) => onChanged(ClimateEra.values[v.round()])),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: ClimateEra.values.map((e) => Text(
          e.subtitle, style: AppTypography.caption.copyWith(color: colors.textMuted))).toList(),
      ),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;
  final Color    color;
  const _StatCard({required this.label, required this.value,
      required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: AppTypography.caption
              .copyWith(color: color, letterSpacing: 0.8)),
        ]),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
          letterSpacing: -0.5,
        )),
      ]),
    );
  }
}

class _EraCard extends StatelessWidget {
  final ClimateEra era;
  final bool       isActive;
  final VoidCallback onTap;
  const _EraCard({required this.era, required this.isActive,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.08) : colors.bg2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.4)
                : colors.cardBorder,
          ),
        ),
        child: Row(children: [
          Icon(_icon(era),
              color: isActive
                  ? AppColors.primary : colors.textSecondary,
              size: 22),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(era.label, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
              Text(_desc(era), style: AppTypography.bodySmall.copyWith(color: colors.textSecondary)),
            ],
          )),
          if (isActive)
            StatusPill.active()
          else
            Icon(Icons.chevron_right,
                color: colors.textMuted, size: 20),
        ]),
      ),
    );
  }

  IconData _icon(ClimateEra e) => switch (e) {
    ClimateEra.preindustrial1900 => Icons.ac_unit,
    ClimateEra.present2026       => Icons.satellite_alt_outlined,
    ClimateEra.projected2100     => Icons.show_chart,
  };

  String _desc(ClimateEra e) => switch (e) {
    ClimateEra.preindustrial1900 => 'Pre-industrial · Full ice extent',
    ClimateEra.present2026       => 'Now · NASA GIBS satellite data',
    ClimateEra.projected2100     => 'Projection · IPCC SSP3 scenario',
  };
}