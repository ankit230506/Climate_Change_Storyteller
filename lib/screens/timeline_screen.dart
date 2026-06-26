import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '/core/theme/app_theme.dart';
import '../models/app_models.dart';
import '../widgets/shared_widgets.dart';
import '../services/lg_ssh_service.dart';
import '../services/kml_builder_service.dart';
import '../services/climate_data_service.dart';


class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  ClimateRegion _region   = kDefaultRegions.first;
  ClimateEra    _era      = ClimateEra.present2026;
  bool          _loading  = false;
  bool          _statsLoading = false;
  String?       _statusMsg;
  ClimateStats? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  // ── Fetch real climate stats from NOAA / IPCC ─────────────────────────────
  // WHY HERE: Stats shown below the era slider must update when era changes.
  // ClimateDataService handles the API calls + IPCC fallback automatically.
  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final year  = int.tryParse(_era.label) ?? DateTime.now().year;
      final stats = await ClimateDataService.instance
          .getStatsForYear(year);
      if (mounted) setState(() => _stats = stats);
    } catch (e) {
      debugPrint('Stats load error: $e');
    } finally {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  // ── Build KML + send to LG ────────────────────────────────────────────────
  Future<void> _sendKmlToLG() async {
    final ssh = LGSSHService.instance;
    if (!ssh.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected — go to Settings → Connect to LG Rig'),
        backgroundColor: AppColors.bg2,
      ));
      return;
    }
    setState(() { _loading = true; _statusMsg = 'Building KML…'; });
    try {
      setState(() => _statusMsg = 'Fetching NASA GIBS data…');
      final kmlPath = await KmlBuilderService.instance.buildKml(
        region: _region, era: _era);

      setState(() => _statusMsg = 'Uploading to rig…');
      String kmlContent = '';
      if (!kIsWeb) {
        kmlContent = await File(kmlPath).readAsString();
      }
      final filename   = '${_region.id}_${_era.label}.kml';
      await ssh.sendKml(filename, kmlContent: kmlContent);

      setState(() => _statusMsg = 'Flying to ${_region.name}…');
      await ssh.flyTo(
        latitude: _region.latitude,
        longitude: _region.longitude,
        altitude: _region.altitude,
      );

      if (mounted) {
        setState(() => _statusMsg = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('${_region.name} ${_era.label} loaded on LG!'),
          ]),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMsg = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.critical,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),

              // ── Header ──────────────────────────────────────────────────
              Text(_region.name, style: AppTypography.heading1),
              Text('Slide to travel through time',
                  style: AppTypography.bodySmall),
              const SizedBox(height: 24),

              // ── Era slider ───────────────────────────────────────────────
              _EraSlider(
                selected: _era,
                onChanged: (era) {
                  setState(() => _era = era);
                  _loadStats();   // reload stats for new era
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
                    style: const TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -3,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              Center(child: Text(
                _eraSource(_era),
                style: AppTypography.bodySmall,
              )),
              const SizedBox(height: 24),

              // ── REAL STAT CARDS from NOAA / IPCC ────────────────────────
              // WHY: Shows real data fetched from NOAA (2026) or
              // IPCC constants (1900/2100) below the era slider.
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
                // Data source attribution
                Text(
                  'Source: ${_stats!.source}',
                  style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted),
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
                              ? AppColors.primary.withOpacity(0.15)
                              : AppColors.bg3,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: active
                                ? AppColors.primary
                                : const Color(0xFF252840),
                          ),
                        ),
                        child: Text(
                          r.name.split(' ').first,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w700 : FontWeight.w400,
                            color: active
                                ? AppColors.primary
                                : AppColors.textSecondary,
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
                stream: LGSSHService.instance.stateStream,
                initialData: LGSSHService.instance.state,
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
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.3)),
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
                            strokeWidth: 2, color: AppColors.bg0))
                    : const Icon(Icons.send, size: 18, color: AppColors.bg0),
                label: Text(_loading ? 'Sending…' : 'Send KML to LG'),
              ),
              const SizedBox(height: 32),
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

// ── Era slider ────────────────────────────────────────────────────────────────
class _EraSlider extends StatelessWidget {
  final ClimateEra selected;
  final ValueChanged<ClimateEra> onChanged;
  const _EraSlider({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final index = ClimateEra.values.indexOf(selected).toDouble();
    return Column(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: ClimateEra.values.map((e) => Text(
          e.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: e == selected ? FontWeight.w700 : FontWeight.w400,
            color: e == selected
                ? AppColors.primary : AppColors.textSecondary,
          ),
        )).toList(),
      ),
      const SizedBox(height: 8),
      Slider(min: 0, max: 2, divisions: 2, value: index,
          onChanged: (v) => onChanged(ClimateEra.values[v.round()])),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: ClimateEra.values.map((e) => Text(
          e.subtitle, style: AppTypography.caption)).toList(),
      ),
    ]);
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;
  final Color    color;
  const _StatCard({required this.label, required this.value,
      required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2235)),
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
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        )),
      ]),
    );
  }
}

// ── Era card ──────────────────────────────────────────────────────────────────
class _EraCard extends StatelessWidget {
  final ClimateEra era;
  final bool       isActive;
  final VoidCallback onTap;
  const _EraCard({required this.era, required this.isActive,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withOpacity(0.08) : AppColors.bg2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withOpacity(0.4)
                : const Color(0xFF1E2235),
          ),
        ),
        child: Row(children: [
          Icon(_icon(era),
              color: isActive
                  ? AppColors.primary : AppColors.textSecondary,
              size: 22),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(era.label, style: AppTypography.heading3),
              Text(_desc(era), style: AppTypography.bodySmall),
            ],
          )),
          if (isActive)
            StatusPill.active()
          else
            const Icon(Icons.chevron_right,
                color: AppColors.textMuted, size: 20),
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