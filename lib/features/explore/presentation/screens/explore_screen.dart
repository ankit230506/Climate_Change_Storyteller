import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui' as ui;
import 'package:climate_storyteller/core/theme/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';
import '../../domain/entities/climate_region.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String         _category = 'All';
  ClimateRegion? _selected;
  final _mapController = MapController();

  static const _cats = ['All','Glaciers','Sea Level','Forests','Heat'];

  List<ClimateRegion> get _filtered {
    if (_category == 'All') return kDefaultRegions;
    final cat = switch (_category) {
      'Glaciers'  => 'glacier',
      'Sea Level' => 'sealevel',
      'Forests'   => 'forest',
      'Heat'      => 'heat',
      _           => '',
    };
    return kDefaultRegions.where((r) => r.category == cat).toList();
  }

  Color _catColor(String c) => switch (c) {
    'glacier'  => AppColors.glacier,
    'sealevel' => AppColors.seaLevel,
    'forest'   => AppColors.forest,
    'heat'     => AppColors.warning,
    _          => AppColors.textSecondary,
  };

  IconData _catIcon(String c) => switch (c) {
    'glacier'  => Icons.ac_unit,
    'sealevel' => Icons.water,
    'forest'   => Icons.forest,
    'heat'     => Icons.thermostat,
    _          => Icons.place,
  };

  void _onRegionTap(ClimateRegion region) {
    setState(() => _selected = region);
    _mapController.move(
      LatLng(region.latitude, region.longitude), 4,
    );
  }

  void _flyToLG(ClimateRegion region) async {
    final lg = DI.lgRepository;
    if (!lg.state.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Connect to LG rig first — go to Settings'),
        backgroundColor: AppColors.bg2,
      ));
      return;
    }
    await DI.flyToLg(
      latitude: region.latitude,
      longitude: region.longitude,
      altitude: region.altitude,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Flying to ${region.name} on LG…'),
        backgroundColor: AppColors.primary.withValues(alpha: 0.9),
      ));
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
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Explore', style: AppTypography.heading1),
                  Text('Select a climate region to begin',
                      style: AppTypography.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Category filters ─────────────────────────────────────
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: _cats.map((cat) {
                  final active = cat == _category;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _category = cat;
                      _selected = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.bg3,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: active
                                ? AppColors.primary
                                : const Color(0xFF252840)),
                      ),
                      child: Text(cat, style: TextStyle(
                        fontSize: 13,
                        fontWeight: active
                            ? FontWeight.w700 : FontWeight.w400,
                        color: active
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      )),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // ── flutter_map ──────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: const MapOptions(
                      initialCenter: LatLng(20, 30),
                      initialZoom: 1.8,
                    ),
                    children: [
                      // Real OSM tiles
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.example.climate_storyteller',
                      ),

                      // Proper pin markers
                      MarkerLayer(
                        markers: _filtered.map((region) {
                          final color    = _catColor(region.category);
                          final selected = _selected?.id == region.id;
                          return Marker(
                            point: LatLng(
                                region.latitude, region.longitude),
                            width:  selected ? 50 : 40,
                            height: selected ? 60 : 50,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () => _onRegionTap(region),
                              child: _MapPin(
                                color: color,
                                icon: _catIcon(region.category),
                                isSelected: selected,
                                label: region.name.split(' ').first,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Legend ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(spacing: 14, runSpacing: 6, children: [
                _dot(AppColors.glacier, 'Glaciers'),
                _dot(AppColors.forest,  'Forests'),
                _dot(AppColors.seaLevel,'Sea Rise'),
                _dot(AppColors.warning, 'Heat'),
              ]),
            ),
            const SizedBox(height: 12),

            // ── Region list ───────────────────────────────────────────
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('REGIONS', style: AppTypography.label),
                    const SizedBox(height: 10),
                    ..._filtered.map((r) {
                      final selected = _selected?.id == r.id;
                      final color    = _catColor(r.category);
                      return GestureDetector(
                        onTap: () => _onRegionTap(r),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected
                                ? color.withValues(alpha: 0.08)
                                : AppColors.bg2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? color.withValues(alpha: 0.5)
                                  : const Color(0xFF1E2235),
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(_catIcon(r.category),
                                  color: color, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name, style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                )),
                                Text(
                                  '${r.latitude.toStringAsFixed(1)}°, '
                                  '${r.longitude.toStringAsFixed(1)}°',
                                  style: AppTypography.bodySmall),
                              ],
                            )),
                            if (r.riskLevel != null)
                              StatusPill(
                                label: r.riskLevel!,
                                color: r.riskLevel == 'Critical'
                                    ? AppColors.critical
                                    : AppColors.warning,
                              ),
                          ]),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            // ── CTA ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                height: 54, width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _selected != null
                      ? () => _flyToLG(_selected!)
                      : null,
                  icon: const Icon(Icons.public,
                      size: 18, color: AppColors.bg0),
                  label: Text(_selected != null
                      ? 'Fly to ${_selected!.name} on LG'
                      : 'Select a Region Above'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
      const SizedBox(width: 4),
      Text(label, style: AppTypography.caption.copyWith(letterSpacing: 0.3)),
    ],
  );
}

// ── Proper map pin widget ─────────────────────────────────────────────────────
class _MapPin extends StatelessWidget {
  final Color    color;
  final IconData icon;
  final bool     isSelected;
  final String   label;

  const _MapPin({
    required this.color,
    required this.icon,
    required this.isSelected,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label above pin (only when selected)
        if (isSelected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),

        // Pin head (circle with icon)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width:  isSelected ? 36 : 30,
          height: isSelected ? 36 : 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: isSelected ? 12 : 4,
                spreadRadius: isSelected ? 2 : 0,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white,
              size: isSelected ? 18 : 14),
        ),

        // Pin tail (triangle pointer)
        CustomPaint(
          size: const Size(10, 6),
          painter: _PinTailPainter(color: color),
        ),
      ],
    );
  }
}

class _PinTailPainter extends CustomPainter {
  final Color color;
  _PinTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = ui.Path();
    path.moveTo(0, 0);
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width, 0);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PinTailPainter old) => old.color != color;
}
