import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:climate_storyteller/core/theme/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';
import '../../domain/entities/climate_region.dart';
import '../../domain/entities/climate_era.dart';

class RegionDetailScreen extends StatefulWidget {
  final ClimateRegion region;

  const RegionDetailScreen({super.key, required this.region});

  @override
  State<RegionDetailScreen> createState() => _RegionDetailScreenState();
}

class _RegionDetailScreenState extends State<RegionDetailScreen> {
  final Map<String, _LayerStatus> _layerStatus = {};

  late final List<_KmlLayer> _layers;

  @override
  void initState() {
    super.initState();
    _layers = ClimateEra.values.map((era) {
      final filename = widget.region.kmlFiles[era] ?? '';
      return _KmlLayer(
        name: '${_categoryLabel(widget.region.category)} — ${era.subtitle}',
        icon: _categoryIcon(widget.region.category),
        era: era,
        filename: filename,
      );
    }).toList();

    for (final l in _layers) {
      _layerStatus[l.filename] = _LayerStatus.ready;
    }
  }

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

  Future<void> _sendLayer(_KmlLayer layer) async {
    final lg = DI.lgRepository;
    if (!lg.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Not connected — go to Settings → Connect to LG Rig'),
            backgroundColor: AppColors.bg2),
      );
      return;
    }

    setState(() => _layerStatus[layer.filename] = _LayerStatus.loading);

    try {
      // Build the KML
      final kmlPath = await DI.kmlGeneratorDataSource.buildKml(
        region: widget.region,
        era: layer.era,
      );

      // Read the KML content
      String kmlContent = '';
      if (!kIsWeb) {
        final file = File(kmlPath);
        if (await file.exists()) {
          kmlContent = await file.readAsString();
        }
      }

      await DI.sendKmlToLg(layer.filename, kmlContent: kmlContent);
      await Future.delayed(const Duration(seconds: 2));

      // Fly to the region
      await DI.flyToLg(
        latitude: widget.region.latitude,
        longitude: widget.region.longitude,
        altitude: widget.region.altitude,
      );

      if (mounted) {
        setState(() => _layerStatus[layer.filename] = _LayerStatus.loaded);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('${layer.name} loaded on LG!'),
          ]),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _layerStatus[layer.filename] = _LayerStatus.error);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.critical,
        ));
      }
    }
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
              ..._layers.map((l) => _KmlLayerTile(
                layer: l,
                status: _layerStatus[l.filename] ?? _LayerStatus.ready,
                onTap: () => _sendLayer(l),
              )),
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

  IconData _categoryIcon(String cat) => switch (cat) {
        'glacier' => Icons.ac_unit,
        'sealevel' => Icons.water,
        'forest' => Icons.forest,
        'heat' => Icons.thermostat,
        _ => Icons.place,
      };
}

enum _LayerStatus { ready, loading, loaded, error }

class _KmlLayer {
  final String name;
  final IconData icon;
  final ClimateEra era;
  final String filename;

  const _KmlLayer({
    required this.name,
    required this.icon,
    required this.era,
    required this.filename,
  });
}

class _KmlLayerTile extends StatelessWidget {
  final _KmlLayer layer;
  final _LayerStatus status;
  final VoidCallback onTap;

  const _KmlLayerTile({
    required this.layer,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pill = switch (status) {
      _LayerStatus.loaded  => StatusPill.loaded(),
      _LayerStatus.ready   => StatusPill.ready(),
      _LayerStatus.loading => StatusPill.loading(),
      _LayerStatus.error   => StatusPill(label: 'Error', color: AppColors.critical),
    };

    return GestureDetector(
      onTap: status == _LayerStatus.loading ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: status == _LayerStatus.loaded
              ? AppColors.good.withValues(alpha: 0.05)
              : AppColors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: status == _LayerStatus.loaded
                ? AppColors.good.withValues(alpha: 0.3)
                : const Color(0xFF1E2235),
          ),
        ),
        child: Row(
          children: [
            Icon(layer.icon, color: AppColors.textSecondary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(layer.name, style: AppTypography.bodyLarge),
                  Text(
                    'Tap to load on LG',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            pill,
          ],
        ),
      ),
    );
  }
}
