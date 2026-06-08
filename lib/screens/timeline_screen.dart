import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/app_models.dart';
import '../widgets/shared_widgets.dart';
import '../services/lg_ssh_service.dart';
import '../services/kml_builder_service.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  ClimateRegion _region = kDefaultRegions.first; // Arctic
  ClimateEra    _selectedEra = ClimateEra.present2026;
  bool          _isSending = false;
  String?       _statusMsg;

  Future<void> _sendKmlToLG() async {
    final ssh = LGSSHService.instance;
    if (!ssh.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected — go to Settings → Connect to LG Rig'),
        backgroundColor: AppColors.bg2,
      ));
      return;
    }

    setState(() { _isSending = true; _statusMsg = 'Building KML…'; });

    try {
      // 1. Build KML from NASA GIBS + IPCC data
      setState(() => _statusMsg = 'Fetching NASA GIBS data…');
      final kmlPath = await KmlBuilderService.instance.buildKml(
        region: _region,
        era:    _selectedEra,
      );

      // 2. Read the built KML file content
      setState(() => _statusMsg = 'Uploading KML to rig…');
      final file = await Future(() async {
        final f = await _readFile(kmlPath);
        return f;
      });

      // 3. Send KML to LG rig via SSH/SFTP
      final filename = '${_region.id}_${_selectedEra.label}.kml';
      await ssh.sendKml(filename, kmlContent: file);

      // 4. Fly camera to region
      setState(() => _statusMsg = 'Flying to ${_region.name}…');
      await ssh.flyTo(
        latitude:  _region.latitude,
        longitude: _region.longitude,
        altitude:  _region.altitude,
      );

      if (mounted) {
        setState(() => _statusMsg = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('${_region.name} ${_selectedEra.label} loaded on LG!'),
          ]),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 4),
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
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<String> _readFile(String path) async {
    final file = File(path);
    if (await file.exists()) return file.readAsString();
    return '';
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

              // ── Header ───────────────────────────────────────────────
              Text(_region.name, style: AppTypography.heading1),
              Text('Drag slider — sends KML to LG',
                  style: AppTypography.bodySmall),
              const SizedBox(height: 28),

              // ── Era slider ───────────────────────────────────────────
              _TimelineSlider(
                selected: _selectedEra,
                onChanged: (era) => setState(() => _selectedEra = era),
              ),
              const SizedBox(height: 24),

              // ── Big year ─────────────────────────────────────────────
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _selectedEra.label,
                    key: ValueKey(_selectedEra),
                    style: const TextStyle(
                      fontSize: 72, fontWeight: FontWeight.w800,
                      letterSpacing: -2, color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(_eraSource(_selectedEra),
                    style: AppTypography.bodySmall),
              ),
              const SizedBox(height: 28),

              // ── Era cards ────────────────────────────────────────────
              ...ClimateEra.values.map((era) => _EraCard(
                era:     era,
                isActive: era == _selectedEra,
                kmlFile:  _region.kmlFiles[era]!,
                onTap: () => setState(() => _selectedEra = era),
              )),
              const SizedBox(height: 16),

              // ── Region selector ──────────────────────────────────────
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
                                ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // ── LG status ────────────────────────────────────────────
              StreamBuilder<LGRigState>(
                stream: LGSSHService.instance.stateStream,
                initialData: LGSSHService.instance.state,
                builder: (_, snap) => LGStatusCard(rigState: snap.data!),
              ),
              const SizedBox(height: 16),

              // ── Status message ───────────────────────────────────────
              if (_statusMsg != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary),
                      ),
                      const SizedBox(width: 10),
                      Text(_statusMsg!,
                          style: AppTypography.bodySmall.copyWith(
                              color: AppColors.primary)),
                    ],
                  ),
                ),

              // ── CTA ──────────────────────────────────────────────────
              ElevatedButton.icon(
                onPressed: _isSending ? null : _sendKmlToLG,
                icon: _isSending
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.bg0),
                      )
                    : const Icon(Icons.send, size: 18, color: AppColors.bg0),
                label: Text(_isSending ? 'Sending…' : 'Send KML to LG'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  String _eraSource(ClimateEra era) => switch (era) {
    ClimateEra.preindustrial1900 => 'Pre-industrial baseline (IPCC AR6)',
    ClimateEra.present2026       => 'NASA GIBS satellite · Currently active',
    ClimateEra.projected2100     => 'IPCC AR6 SSP3-7.0 projection',
  };
}

// ── Timeline slider ───────────────────────────────────────────────────────────

class _TimelineSlider extends StatelessWidget {
  final ClimateEra        selected;
  final ValueChanged<ClimateEra> onChanged;

  const _TimelineSlider({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final index = ClimateEra.values.indexOf(selected).toDouble();
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ClimateEra.values.map((e) => Text(
            e.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: e == selected ? FontWeight.w700 : FontWeight.w400,
              color: e == selected ? AppColors.primary : AppColors.textSecondary,
            ),
          )).toList(),
        ),
        const SizedBox(height: 8),
        Slider(
          min: 0, max: 2, divisions: 2,
          value: index,
          onChanged: (v) => onChanged(ClimateEra.values[v.round()]),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ClimateEra.values.map((e) => Text(
            e.subtitle, style: AppTypography.caption,
          )).toList(),
        ),
      ],
    );
  }
}

// ── Era card ──────────────────────────────────────────────────────────────────

class _EraCard extends StatelessWidget {
  final ClimateEra era;
  final bool       isActive;
  final String     kmlFile;
  final VoidCallback onTap;

  const _EraCard({
    required this.era, required this.isActive,
    required this.kmlFile, required this.onTap,
  });

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
        child: Row(
          children: [
            Icon(_eraIcon(era),
                color: isActive
                    ? AppColors.primary : AppColors.textSecondary,
                size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(era.label, style: AppTypography.heading3),
                  Text(_eraDesc(era), style: AppTypography.bodySmall),
                ],
              ),
            ),
            if (isActive)
              StatusPill.active()
            else
              const Icon(Icons.chevron_right,
                  color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  IconData _eraIcon(ClimateEra e) => switch (e) {
    ClimateEra.preindustrial1900 => Icons.ac_unit,
    ClimateEra.present2026       => Icons.satellite_alt_outlined,
    ClimateEra.projected2100     => Icons.show_chart,
  };

  String _eraDesc(ClimateEra e) => switch (e) {
    ClimateEra.preindustrial1900 => 'Pre-industrial · Full ice extent',
    ClimateEra.present2026       => 'Now · NASA GIBS satellite data',
    ClimateEra.projected2100     => 'Projection · IPCC SSP3 scenario',
  };
}