import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_storyteller/features/explore/climate_region.dart';

/// Manages persistence of user-created custom climate regions.
/// Uses SharedPreferences for lightweight JSON storage.
class CustomRegionService {
  CustomRegionService._();
  static final CustomRegionService instance = CustomRegionService._();

  static const _kCustomRegions = 'custom_regions_json';

  List<ClimateRegion> _customRegions = [];
  final _streamCtrl = StreamController<List<ClimateRegion>>.broadcast();

  /// Stream of custom regions for reactive UI updates.
  Stream<List<ClimateRegion>> get regionsStream => _streamCtrl.stream;

  /// Current custom regions (synchronous).
  List<ClimateRegion> get customRegions => List.unmodifiable(_customRegions);

  /// All regions = built-in + custom.
  List<ClimateRegion> get allRegions => [
        ...kDefaultRegions,
        ..._customRegions,
      ];

  /// Load persisted custom regions on app startup.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_kCustomRegions);
      if (json != null && json.isNotEmpty) {
        _customRegions = ClimateRegion.decodeList(json);
        _streamCtrl.add(_customRegions);
      }
    } catch (e) {
      _customRegions = [];
    }
  }

  /// Add a new custom region and persist.
  Future<void> addRegion(ClimateRegion region) async {
    _customRegions.add(region);
    await _persist();
    _streamCtrl.add(_customRegions);
  }

  /// Remove a custom region by ID and persist.
  Future<void> removeRegion(String regionId) async {
    _customRegions.removeWhere((r) => r.id == regionId);
    await _persist();
    _streamCtrl.add(_customRegions);
  }

  /// Update an existing custom region and persist.
  Future<void> updateRegion(ClimateRegion updated) async {
    final idx = _customRegions.indexWhere((r) => r.id == updated.id);
    if (idx != -1) {
      _customRegions[idx] = updated;
      await _persist();
      _streamCtrl.add(_customRegions);
    }
  }

  /// Clear all custom regions.
  Future<void> clearAll() async {
    _customRegions.clear();
    await _persist();
    _streamCtrl.add(_customRegions);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCustomRegions,
        ClimateRegion.encodeList(_customRegions),
      );
    } catch (_) {}
  }
}
