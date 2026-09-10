import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/features/explore/climate_region.dart';

/// Screen for creating a custom climate region.
/// Users can name, categorize, and pick coordinates from a map.
class AddRegionScreen extends StatefulWidget {
  const AddRegionScreen({super.key});

  @override
  State<AddRegionScreen> createState() => _AddRegionScreenState();
}

class _AddRegionScreenState extends State<AddRegionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _mapController = MapController();

  String _category = 'heat';
  String _riskLevel = 'Moderate';
  LatLng? _pickedLocation;
  bool _isSaving = false;

  static const _categories = [
    ('glacier', 'Glacier', Icons.ac_unit),
    ('sealevel', 'Sea Level', Icons.water),
    ('forest', 'Forest', Icons.forest),
    ('heat', 'Heat', Icons.thermostat),
    ('aqi', 'Air Quality', Icons.air),
  ];

  static const _riskLevels = ['Moderate', 'High', 'Critical'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _pickedLocation = point;
      _latCtrl.text = point.latitude.toStringAsFixed(4);
      _lngCtrl.text = point.longitude.toStringAsFixed(4);
    });
  }

  Future<void> _saveRegion() async {
    if (!_formKey.currentState!.validate()) return;

    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter valid coordinates or tap on the map'),
        backgroundColor: AppColors.critical,
      ));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final name = _nameCtrl.text.trim();
      final id = 'custom_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch}';
      final bbox = ClimateRegion.defaultBbox(lat, lng);

      final region = ClimateRegion(
        id: id,
        name: name,
        category: _category,
        latitude: lat,
        longitude: lng,
        altitude: 350000,
        riskLevel: _riskLevel,
        kmlFiles: ClimateRegion.generateKmlFiles(id, _category),
        bboxNorth: bbox.n,
        bboxSouth: bbox.s,
        bboxEast: bbox.e,
        bboxWest: bbox.w,
        imageUrl: '',
        description: _descCtrl.text.trim().isNotEmpty
            ? _descCtrl.text.trim()
            : 'Custom climate hotspot region added by user.',
        isCustom: true,
      );

      await DI.customRegionService.addRegion(region);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('$name added as a custom region!'),
            ],
          ),
          backgroundColor: AppColors.good,
        ));
        Navigator.pop(context, region);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.critical,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.bg0,
      appBar: AppBar(
        backgroundColor: colors.bg0,
        title: Text(
          'Add Custom Region',
          style: AppTypography.heading2.copyWith(color: colors.textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.close, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TAP ON MAP TO PICK LOCATION',
                    style: AppTypography.label.copyWith(color: colors.textMuted)),
                const SizedBox(height: 8),
                Container(
                  height: 220,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.cardBorder),
                  ),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: const LatLng(20, 30),
                      initialZoom: 2.0,
                      onTap: _onMapTap,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.example.climate_storyteller',
                      ),
                      if (_pickedLocation != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _pickedLocation!,
                              width: 40,
                              height: 50,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.primary,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.5),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(Icons.add_location,
                                        color: Colors.white, size: 16),
                                  ),
                                  Container(
                                    width: 2,
                                    height: 8,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        style: TextStyle(
                            color: colors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Latitude',
                          labelStyle:
                              TextStyle(color: colors.textSecondary),
                          filled: true,
                          fillColor: colors.bg2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: colors.cardBorder),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }
                          final d = double.tryParse(v.trim());
                          if (d == null || d < -90 || d > 90) {
                            return '-90 to 90';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lngCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        style: TextStyle(
                            color: colors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Longitude',
                          labelStyle:
                              TextStyle(color: colors.textSecondary),
                          filled: true,
                          fillColor: colors.bg2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: colors.cardBorder),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }
                          final d = double.tryParse(v.trim());
                          if (d == null || d < -180 || d > 180) {
                            return '-180 to 180';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Region Name',
                    hintText: 'e.g. Great Barrier Reef',
                    labelStyle: TextStyle(color: colors.textSecondary),
                    hintStyle: TextStyle(color: colors.textMuted),
                    filled: true,
                    fillColor: colors.bg2,
                    prefixIcon:
                        Icon(Icons.place, color: colors.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.cardBorder),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 16),
                Text('CATEGORY',
                    style: AppTypography.label.copyWith(color: colors.textMuted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories.map((cat) {
                    final isSelected = _category == cat.$1;
                    final catColor = _getCatColor(cat.$1);
                    return GestureDetector(
                      onTap: () => setState(() => _category = cat.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? catColor.withValues(alpha: 0.2)
                              : colors.bg2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? catColor : colors.cardBorder,
                            width: isSelected ? 1.6 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(cat.$3,
                                color:
                                    isSelected ? catColor : colors.textSecondary,
                                size: 16),
                            const SizedBox(width: 6),
                            Text(
                              cat.$2,
                              style: TextStyle(
                                color: isSelected
                                    ? catColor
                                    : colors.textSecondary,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text('RISK LEVEL',
                    style: AppTypography.label.copyWith(color: colors.textMuted)),
                const SizedBox(height: 8),
                Row(
                  children: _riskLevels.map((level) {
                    final isSelected = _riskLevel == level;
                    final levelColor = level == 'Critical'
                        ? AppColors.critical
                        : (level == 'High'
                            ? AppColors.warning
                            : AppColors.ready);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _riskLevel = level),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? levelColor.withValues(alpha: 0.2)
                                : colors.bg2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? levelColor
                                  : colors.cardBorder,
                              width: isSelected ? 1.6 : 1.0,
                            ),
                          ),
                          child: Text(
                            level,
                            style: TextStyle(
                              color: isSelected
                                  ? levelColor
                                  : colors.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descCtrl,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    hintText:
                        'Describe the climate impact at this location...',
                    labelStyle: TextStyle(color: colors.textSecondary),
                    hintStyle: TextStyle(color: colors.textMuted),
                    filled: true,
                    fillColor: colors.bg2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.cardBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveRegion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.add_location_alt, size: 20),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Add Custom Region',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getCatColor(String c) => switch (c) {
        'glacier' => AppColors.glacier,
        'sealevel' => AppColors.seaLevel,
        'forest' => AppColors.forest,
        'heat' => AppColors.warning,
        'aqi' => AppColors.critical,
        _ => AppColors.textSecondary,
      };
}
