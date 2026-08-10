import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui' as ui;
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';
import 'package:climate_storyteller/widgets/lg_map_controller_widget.dart';
import 'package:climate_storyteller/features/lg_connection/lg_service.dart';
import 'climate_region.dart';
import 'climate_year_slider.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String         _category = 'All';
  ClimateRegion? _selected = kDefaultRegions.first;
  final _mapController = MapController();
  final bool _isLiveSyncEnabled = false;
  final bool _isBiDirectional = false;
  bool _is3DTilt = true;
  int  _selectedYear = 2026;
  bool _isLoadingKml = false;
  bool _isProgrammaticMove = false;
  StreamSubscription<LgViewpoint>? _vpSub;

  @override
  void initState() {
    super.initState();
    _vpSub = DI.lgService.lgViewpointStream.listen((vp) {
      if (_isBiDirectional && mounted && !_isProgrammaticMove) {
        _isProgrammaticMove = true;
        _mapController.move(LatLng(vp.latitude, vp.longitude), _mapController.camera.zoom);
        Future.delayed(const Duration(milliseconds: 300), () {
          _isProgrammaticMove = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _vpSub?.cancel();
    DI.lgService.stopLgViewpointPolling();
    super.dispose();
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (_isLiveSyncEnabled && hasGesture && !_isProgrammaticMove) {
      DI.lgService.flyToThrottled(
        latitude: camera.center.latitude,
        longitude: camera.center.longitude,
        zoom: camera.zoom,
        tilt: _is3DTilt ? 45.0 : 0.0,
      );
    }
  }

  void _onZoomIn() {
    final currentZoom = _mapController.camera.zoom;
    final targetZoom = (currentZoom + 1.0).clamp(1.0, 18.0);
    _mapController.move(_mapController.camera.center, targetZoom);
    if (_isLiveSyncEnabled || DI.lgService.state.isConnected) {
      DI.lgService.flyToThrottled(
        latitude: _mapController.camera.center.latitude,
        longitude: _mapController.camera.center.longitude,
        zoom: targetZoom,
        tilt: _is3DTilt ? 45.0 : 0.0,
      );
    }
  }

  void _onZoomOut() {
    final currentZoom = _mapController.camera.zoom;
    final targetZoom = (currentZoom - 1.0).clamp(1.0, 18.0);
    _mapController.move(_mapController.camera.center, targetZoom);
    if (_isLiveSyncEnabled || DI.lgService.state.isConnected) {
      DI.lgService.flyToThrottled(
        latitude: _mapController.camera.center.latitude,
        longitude: _mapController.camera.center.longitude,
        zoom: targetZoom,
        tilt: _is3DTilt ? 45.0 : 0.0,
      );
    }
  }

  void _onToggleTilt() {
    setState(() => _is3DTilt = !_is3DTilt);
    if (_isLiveSyncEnabled || DI.lgService.state.isConnected) {
      DI.lgService.flyToThrottled(
        latitude: _mapController.camera.center.latitude,
        longitude: _mapController.camera.center.longitude,
        zoom: _mapController.camera.zoom,
        tilt: _is3DTilt ? 45.0 : 0.0,
      );
    }
  }

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
    _launchRegionOnLG(region, _selectedYear);
  }

  void _showEnlargedImage(BuildContext context, ClimateRegion region) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.black,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InteractiveViewer(
                    child: Image.network(
                      region.imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, loading) => loading == null
                          ? child
                          : const Padding(
                              padding: EdgeInsets.all(40),
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.black87,
                    child: Text(
                      '${region.name} — ${region.category.toUpperCase()}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchRegionOnLG(ClimateRegion region, int year) async {
    final lg = DI.lgService;
    if (!lg.state.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connect to LG rig in Settings to see 3D visualization & time slider'),
          duration: Duration(seconds: 2),
        ));
      }
      return;
    }

    setState(() => _isLoadingKml = true);
    try {
      await lg.flyTo(
        latitude: region.latitude,
        longitude: region.longitude,
        altitude: region.altitude,
      );

      final kmlPath = await lg.buildKmlForYear(
        region: region,
        year: year,
      );
      final content = await File(kmlPath).readAsString();
      final filename = '${region.id}_year_${year}_${region.category}.kml';

      await lg.sendKmlRealtime(filename, kmlContent: content);

      await Future.delayed(const Duration(milliseconds: 3500));

      if (mounted && _selected?.id == region.id) {
        await lg.startOrbit(
          latitude: region.latitude,
          longitude: region.longitude,
          altitude: region.altitude,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Loaded ${region.name} KML & Auto-Orbiting on LG!'),
          backgroundColor: AppColors.primary.withValues(alpha: 0.9),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      debugPrint('Error launching KML on LG tap: $e');
    } finally {
      if (mounted) setState(() => _isLoadingKml = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg0,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Explore Climate Regions', style: AppTypography.heading1.copyWith(color: colors.textPrimary)),
                    Text('Tap a pin on map to auto-open description balloon on Right-Most LG screen',
                        style: AppTypography.bodySmall.copyWith(color: colors.textSecondary)),
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
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : colors.bg3,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: active
                                  ? AppColors.primary
                                  : colors.cardBorder),
                        ),
                        child: Text(cat, style: TextStyle(
                          fontSize: 13,
                          fontWeight: active
                              ? FontWeight.w700 : FontWeight.w500,
                          color: active
                              ? AppColors.primary
                              : colors.textSecondary,
                        )),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              // ── Map view container ───────────────────────────────────
              Container(
                height: 250,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: const LatLng(20, 30),
                          initialZoom: 1.8,
                          onPositionChanged: _onMapPositionChanged,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName:
                                'com.example.climate_storyteller',
                          ),
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
                      Positioned(
                        top: 10,
                        right: 10,
                        child: LGMapControllerWidget(
                          is3DTilt: _is3DTilt,
                          onZoomIn: _onZoomIn,
                          onZoomOut: _onZoomOut,
                          onToggleTilt: _onToggleTilt,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Active Selected Region Card (Full Width with Tap-to-Enlarge Image) ──
              if (_selected != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.bg2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tap image thumbnail to view full-screen enlarge modal!
                            GestureDetector(
                              onTap: () => _showEnlargedImage(context, _selected!),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      _selected!.imageUrl,
                                      width: 110,
                                      height: 85,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 110, height: 85,
                                        color: colors.bg3,
                                        child: Icon(Icons.image_not_supported, color: colors.textMuted),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.fullscreen, color: Colors.white, size: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(_catIcon(_selected!.category),
                                          color: _catColor(_selected!.category), size: 18),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _selected!.name,
                                          style: AppTypography.heading3.copyWith(
                                            color: colors.textPrimary,
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selected!.description,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: colors.textSecondary,
                                      fontSize: 12,
                                      height: 1.3,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap image to view full-screen',
                                    style: AppTypography.caption.copyWith(color: AppColors.primary, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),

              // ── Spacious Full-Width Time Slider Card ─────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.bg2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune, color: AppColors.primary, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'LG KML Time Slider (1850 – 2150)',
                              style: AppTypography.heading3.copyWith(
                                fontSize: 14,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          if (_isLoadingKml)
                            const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_selected != null)
                        ClimateYearSlider(
                          lgService: DI.lgService,
                          region: _selected!,
                          initialYear: _selectedYear,
                          onYearChanged: (y) => setState(() => _selectedYear = y),
                        )
                      else
                        Text(
                          'Select a climate region to activate LG time slider',
                          style: AppTypography.bodySmall.copyWith(color: colors.textMuted, fontSize: 12),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _selected != null
                              ? () => _launchRegionOnLG(_selected!, _selectedYear)
                              : null,
                          icon: const Icon(Icons.public, size: 18, color: Colors.white),
                          label: Text(
                            _selected != null ? 'Reload ${_selected!.name} KML on LG' : 'Select a Region Pin',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Bottom Section: 2-Block Horizontal Layout (Settings-Style) of Climate Regions ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('CLIMATE REGIONS', style: AppTypography.label.copyWith(color: colors.textMuted)),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    for (int i = 0; i < _filtered.length; i += 2) ...[
                      Row(
                        children: [
                          Expanded(child: _buildRegionCard(_filtered[i], colors)),
                          const SizedBox(width: 12),
                          if (i + 1 < _filtered.length)
                            Expanded(child: _buildRegionCard(_filtered[i + 1], colors))
                          else
                            const Expanded(child: SizedBox()),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegionCard(ClimateRegion r, AppColorScheme colors) {
    final selected = _selected?.id == r.id;
    final color = _catColor(r.category);
    return GestureDetector(
      onTap: () => _onRegionTap(r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : colors.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : colors.cardBorder,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_catIcon(r.category), color: color, size: 16),
                ),
                const Spacer(),
                if (r.riskLevel != null)
                  StatusPill(
                    label: r.riskLevel!,
                    color: r.riskLevel == 'Critical' ? AppColors.critical : AppColors.warning,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              r.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${r.latitude.toStringAsFixed(1)}°, ${r.longitude.toStringAsFixed(1)}°',
              style: AppTypography.bodySmall.copyWith(
                color: colors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
