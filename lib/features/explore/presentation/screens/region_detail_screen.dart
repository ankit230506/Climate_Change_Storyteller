import 'package:flutter/material.dart';
import 'package:climate_storyteller/core/theme/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';
import '../../domain/entities/climate_region.dart';

class RegionDetailScreen extends StatefulWidget {
  final ClimateRegion region;

  const RegionDetailScreen({super.key, required this.region});

  @override
  State<RegionDetailScreen> createState() => _RegionDetailScreenState();
}

class _RegionDetailScreenState extends State<RegionDetailScreen> {
  static const _layers = [
    _KmlLayer(name: 'Glacier Extent', icon: Icons.ac_unit, status: 'loaded'),
    _KmlLayer(name: 'Sea Level Rise', icon: Icons.water, status: 'ready'),
    _KmlLayer(name: 'KML Placemarks', icon: Icons.place, status: 'loading'),
  ];

  Future<void> _flyToRegion() async {
    final lg = DI.lgRepository;
    if (!lg.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Not connected to LG Rig'),
            backgroundColor: AppColors.bg2),
      );
      return;
    }
    await DI.flyToLg(
      latitude: widget.region.latitude,
      longitude: widget.region.longitude,
      altitude: widget.region.altitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: Text(widget.region.name),
        backgroundColor: AppColors.bg0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Region badges
              Row(
                children: [
                  if (widget.region.riskLevel != null)
                    StatusPill(
                      label: widget.region.riskLevel!,
                      color: widget.region.riskLevel == 'Critical'
                           ? AppColors.critical
                           : AppColors.warning,
                    ),
                  const SizedBox(width: 8),
                  StatusPill(
                    label: _categoryLabel(widget.region.category),
                    color: AppColors.secondary,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Map stub
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1830),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1A2035)),
                ),
                child: Center(
                  child: Text(
                    'Region Map\n(google_maps_flutter)',
                    style: AppTypography.caption.copyWith(letterSpacing: 0),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // KML Layers
              const SectionHeader(title: 'KML Layers'),
              ..._layers.map((l) => _KmlLayerTile(layer: l)),
              const SizedBox(height: 24),

              // Fly to CTA
              ElevatedButton.icon(
                onPressed: _flyToRegion,
                icon: const Icon(Icons.public, size: 18, color: AppColors.bg0),
                label: Text('Fly to ${widget.region.name} on LG'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  String _categoryLabel(String cat) => switch (cat) {
        'glacier' => 'Glacier',
        'sealevel' => 'Sea Level',
        'forest' => 'Forest',
        'heat' => 'Heat',
        _ => cat,
      };
}

class _KmlLayer {
  final String name;
  final IconData icon;
  final String status; // loaded | ready | loading

  const _KmlLayer({required this.name, required this.icon, required this.status});
}

class _KmlLayerTile extends StatelessWidget {
  final _KmlLayer layer;

  const _KmlLayerTile({required this.layer});

  @override
  Widget build(BuildContext context) {
    final pill = switch (layer.status) {
      'loaded' => StatusPill.loaded(),
      'ready' => StatusPill.ready(),
      'loading' => StatusPill.loading(),
      _ => StatusPill(label: layer.status, color: AppColors.textMuted),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Row(
        children: [
          Icon(layer.icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(layer.name, style: AppTypography.bodyLarge),
          ),
          pill,
        ],
      ),
    );
  }
}
