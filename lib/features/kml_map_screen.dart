import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '/core/theme/app_theme.dart';
import '../models/app_models.dart';
import '../widgets/shared_widgets.dart';
import '../services/lg_ssh_service.dart';
import '../services/kml_builder_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// KML MAP SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class KmlMapScreen extends StatefulWidget {
  const KmlMapScreen({super.key});

  @override
  State<KmlMapScreen> createState() => _KmlMapScreenState();
}

class _KmlMapScreenState extends State<KmlMapScreen> {
  ClimateEra _era = ClimateEra.present2026;
  String _pollutant = 'AQI';
  ClimateRegion? _selected;

  static const _pollutants = ['AQI', 'PM2.5', 'NO₂', 'PM10', 'O3'];

  @override
  void initState() {
    super.initState();
    _selected = kDefaultRegions.first;
  }

  Future<void> _sendToLG() async {
    if (_selected == null) return;
    final ssh = LGSSHService.instance;
    if (!ssh.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Connect to LG rig first'),
            backgroundColor: AppColors.bg2),
      );
      return;
    }

    try {
      String kmlContent = '';
      if (!kIsWeb) {
        final kmlPath = await KmlBuilderService.instance.buildKml(
          region: _selected!,
          era: _era,
        );
        kmlContent = await File(kmlPath).readAsString();
      }

      final file = _selected!.kmlFiles[_era];
      if (file == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No KML file for this era')),
        );
        return;
      }

      await ssh.sendKml(file, kmlContent: kmlContent.isNotEmpty ? kmlContent : null);

      await ssh.flyTo(
        latitude: _selected!.latitude,
        longitude: _selected!.longitude,
        altitude: _selected!.altitude,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent $file and flew to region'),
            backgroundColor: AppColors.primary.withOpacity(0.9),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.critical,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('KML Placemarks', style: AppTypography.heading2),
                        Text('Air Quality · Google Maps',
                            style: AppTypography.bodySmall),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.critical.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.critical.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: AppColors.critical),
                        ),
                        const SizedBox(width: 5),
                        Text('LIVE',
                            style: AppTypography.caption
                                .copyWith(color: AppColors.critical)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Map placeholder
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1222),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1A2035)),
                ),
                child: Center(
                  child: Text('KML Heatmap View\n(google_maps_flutter)',
                      style: AppTypography.caption.copyWith(letterSpacing: 0),
                      textAlign: TextAlign.center),
                ),
              ),
            ),

            // Legend
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  _dot(AppColors.critical, 'Hazardous'),
                  const SizedBox(width: 14),
                  _dot(AppColors.warning, 'Moderate'),
                  const SizedBox(width: 14),
                  _dot(AppColors.good, 'Good'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Pollutant + Era selectors
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Pollutant Layer'),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pollutants.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final p = _pollutants[i];
                        final active = p == _pollutant;
                        return GestureDetector(
                          onTap: () => setState(() => _pollutant = p),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.primary.withOpacity(0.15)
                                  : AppColors.bg3,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: active
                                      ? AppColors.primary
                                      : const Color(0xFF252840)),
                            ),
                            child: Text(p,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: active
                                        ? AppColors.primary
                                        : AppColors.textSecondary)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(title: 'Time Period'),
                  Row(
                    children: ClimateEra.values
                        .map((e) => Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                    right: e != ClimateEra.values.last ? 8 : 0),
                                child: EraChip(
                                  era: e,
                                  isSelected: e == _era,
                                  onTap: () => setState(() => _era = e),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: ElevatedButton.icon(
                onPressed: _selected != null ? _sendToLG : null,
                icon: const Icon(Icons.send, size: 18, color: AppColors.bg0),
                label: const Text('Send KML to LG'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c, String label) => Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.caption.copyWith(letterSpacing: 0.3)),
      ]);
}

// SettingsScreen lives in settings_screen.dart