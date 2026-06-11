import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/app_theme.dart';
import '../models/app_models.dart';
import '../widgets/shared_widgets.dart';
import '../services/lg_ssh_service.dart';

/// FEATURE: Explore Screen — Real Google Map
///
/// PURPOSE:
/// Replaces the globe placeholder with an interactive Google Map.
/// Shows 6 colored markers for each climate region.
/// Tapping a marker selects that region and shows its info card.
///
/// SETUP REQUIRED:
///   1. Get a free API key: console.cloud.google.com
///   2. Enable "Maps JavaScript API" (for web) and
///      "Maps SDK for Android" (for Android)
///   3. Add the key to:
///      - web/index.html (for Chrome)
///      - android/app/src/main/AndroidManifest.xml (for Android)
///
/// WHY GoogleMap widget:
/// google_maps_flutter is the official Flutter package, works on
/// both Android and Web (with the JS API key configured).
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String         _category    = 'All';
  ClimateRegion? _selected;
  GoogleMapController? _mapController;

  static const _cats = ['All', 'Glaciers', 'Sea Level', 'Forests', 'Heat'];

  // ── Initial camera position — centered on world ──────────────────────────
  static const _initialCamera = CameraPosition(
    target: LatLng(15, 30),
    zoom: 1.6,
  );

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

  Color _catColor(String cat) => switch (cat) {
    'glacier'  => AppColors.glacier,
    'sealevel' => AppColors.seaLevel,
    'forest'   => AppColors.forest,
    'heat'     => AppColors.warning,
    _          => AppColors.textSecondary,
  };

  IconData _catIcon(String cat) => switch (cat) {
    'glacier'  => Icons.ac_unit,
    'sealevel' => Icons.water,
    'forest'   => Icons.forest,
    'heat'     => Icons.thermostat,
    _          => Icons.place,
  };

  // ── Convert category color to Google Maps marker hue ────────────────────
  // BitmapDescriptor only accepts hue values 0-360, not arbitrary colors
  double _catHue(String cat) => switch (cat) {
    'glacier'  => BitmapDescriptor.hueAzure,
    'sealevel' => BitmapDescriptor.hueCyan,
    'forest'   => BitmapDescriptor.hueGreen,
    'heat'     => BitmapDescriptor.hueOrange,
    _          => BitmapDescriptor.hueRed,
  };

  // ── Build markers from filtered regions ──────────────────────────────────
  Set<Marker> get _markers {
    return _filtered.map((region) {
      final isSelected = _selected?.id == region.id;
      return Marker(
        markerId: MarkerId(region.id),
        position: LatLng(region.latitude, region.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(
            _catHue(region.category)),
        infoWindow: InfoWindow(
          title: region.name,
          snippet: '${region.category} · ${region.riskLevel ?? ''}',
        ),
        onTap: () => setState(() => _selected = region),
        zIndex: isSelected ? 2 : 1,
      );
    }).toSet();
  }

  void _flyToRegion(ClimateRegion region) async {
    // Animate Flutter map camera to region first
    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(region.latitude, region.longitude),
          zoom: 4,
        ),
      ),
    );

    // Then send command to LG rig if connected
    final ssh = LGSSHService.instance;
    if (!ssh.state.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Connect to LG rig first — go to Settings'),
        backgroundColor: AppColors.bg2,
      ));
      return;
    }

    await ssh.flyTo(
      latitude:  region.latitude,
      longitude: region.longitude,
      altitude:  region.altitude,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Flying to ${region.name} on LG…'),
        backgroundColor: AppColors.primary.withOpacity(0.9),
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

            // ── Header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Explore', style: AppTypography.heading1),
                  Text('Tap a region to begin',
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
                            ? AppColors.primary.withOpacity(0.15)
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

            // ── Google Map ────────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: _initialCamera,
                        markers: _markers,
                        onMapCreated: (c) => _mapController = c,
                        mapType: MapType.satellite,
                        zoomControlsEnabled: false,
                        myLocationButtonEnabled: false,
                        style: _darkMapStyle, // dark theme JSON
                      ),

                      // Gradient overlay at edges for visual polish
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color(0xFF1A2035),
                                  width: 1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
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

            // ── Selected region card / region list ───────────────────
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
                      final color = _catColor(r.category);
                      return GestureDetector(
                        onTap: () => setState(() => _selected = r),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected
                                ? color.withOpacity(0.08)
                                : AppColors.bg2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? color.withOpacity(0.5)
                                  : const Color(0xFF1E2235),
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(_catIcon(r.category),
                                  color: color, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(r.name, style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                )),
                                Text(
                                  '${r.latitude.toStringAsFixed(1)}°, '
                                  '${r.longitude.toStringAsFixed(1)}°',
                                  style: AppTypography.bodySmall,
                                ),
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
                      ? () => _flyToRegion(_selected!)
                      : null,
                  icon: const Icon(Icons.public, size: 18,
                      color: AppColors.bg0),
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
      Text(label, style: AppTypography.caption
          .copyWith(letterSpacing: 0.3)),
    ],
  );
}

// ── Dark map style JSON ─────────────────────────────────────────────────────
// WHY: Default Google Maps is light/colorful. This JSON makes it match
// our dark theme. Generated via mapstyle.withgoogle.com
const String _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0e1018"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0e1018"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8892AA"}]},
  {"featureType":"administrative","elementType":"geometry",
   "stylers":[{"color":"#1c2035"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry",
   "stylers":[{"color":"#0a1830"}]},
  {"featureType":"landscape","elementType":"geometry",
   "stylers":[{"color":"#161824"}]}
]
''';