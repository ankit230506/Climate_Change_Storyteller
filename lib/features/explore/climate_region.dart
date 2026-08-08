import 'climate_era.dart';

/// A climate region that can be visualized on the LG rig.
class ClimateRegion {
  final String id;
  final String name;
  final String category; // glacier | sealevel | forest | heat | aqi
  final double latitude;
  final double longitude;
  final double altitude;
  final String? riskLevel; // Critical | High | Moderate
  final Map<ClimateEra, String> kmlFiles; // era -> KML filename
  final double bboxNorth;
  final double bboxSouth;
  final double bboxEast;
  final double bboxWest;

  const ClimateRegion({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    this.riskLevel,
    required this.kmlFiles,
    required this.bboxNorth,
    required this.bboxSouth,
    required this.bboxEast,
    required this.bboxWest,
  });
}

/// Pre-defined regions matching the mockups.
const List<ClimateRegion> kDefaultRegions = [
  ClimateRegion(
    id: 'arctic',
    name: 'Arctic Circle',
    category: 'glacier',
    latitude: 78.2232,
    longitude: 15.6267,
    altitude: 50000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'arctic_1900_glacier.kml',
      ClimateEra.present2026: 'arctic_2026_glacier.kml',
      ClimateEra.projected2100: 'arctic_2100_glacier.kml',
    },
    bboxNorth: 85.0,
    bboxSouth: 65.0,
    bboxEast: 60.0,
    bboxWest: -30.0,
  ),
  ClimateRegion(
    id: 'himalaya',
    name: 'Himalaya',
    category: 'glacier',
    latitude: 27.9881,
    longitude: 86.9250,
    altitude: 45000,
    riskLevel: 'High',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'himalaya_1900_glacier.kml',
      ClimateEra.present2026: 'himalaya_2026_glacier.kml',
      ClimateEra.projected2100: 'himalaya_2100_glacier.kml',
    },
    bboxNorth: 36.0,
    bboxSouth: 26.0,
    bboxEast: 100.0,
    bboxWest: 72.0,
  ),
  ClimateRegion(
    id: 'amazon',
    name: 'Amazon Basin',
    category: 'forest',
    latitude: -3.4653,
    longitude: -62.2159,
    altitude: 65000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'amazon_1900_forest.kml',
      ClimateEra.present2026: 'amazon_2026_forest.kml',
      ClimateEra.projected2100: 'amazon_2100_forest.kml',
    },
    bboxNorth: 5.0,
    bboxSouth: -20.0,
    bboxEast: -44.0,
    bboxWest: -80.0,
  ),
  ClimateRegion(
    id: 'pacific',
    name: 'Pacific Islands',
    category: 'sealevel',
    latitude: -8.7832,
    longitude: 179.0000,
    altitude: 30000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'pacific_1900_sealevel.kml',
      ClimateEra.present2026: 'pacific_2026_sealevel.kml',
      ClimateEra.projected2100: 'pacific_2100_sealevel.kml',
    },
    bboxNorth: 2.0,
    bboxSouth: -18.0,
    bboxEast: -168.0,
    bboxWest: 165.0,
  ),
  ClimateRegion(
    id: 'sahara',
    name: 'Sahara',
    category: 'heat',
    latitude: 23.4162,
    longitude: 25.6628,
    altitude: 65000,
    riskLevel: 'High',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'sahara_1900_heat.kml',
      ClimateEra.present2026: 'sahara_2026_heat.kml',
      ClimateEra.projected2100: 'sahara_2100_heat.kml',
    },
    bboxNorth: 37.0,
    bboxSouth: 15.0,
    bboxEast: 35.0,
    bboxWest: -17.0,
  ),
  ClimateRegion(
    id: 'maldives',
    name: 'Maldives',
    category: 'sealevel',
    latitude: 3.2028,
    longitude: 73.2207,
    altitude: 25000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'maldives_1900_sealevel.kml',
      ClimateEra.present2026: 'maldives_2026_sealevel.kml',
      ClimateEra.projected2100: 'maldives_2100_sealevel.kml',
    },
    bboxNorth: 8.0,
    bboxSouth: -1.0,
    bboxEast: 74.5,
    bboxWest: 72.0,
  ),
  // AQI category existed in the KML-generation backend (GIBS aerosol
  // layer, colored haze-zone polygon, legend/overlay assets) but had NO
  // entry anywhere in this region list — so there was no chip in the
  // Timeline screen's region selector that could ever produce
  // region.category == 'aqi'. Delhi is a globally recognized, severe and
  // worsening air-quality case, making it a natural fit for the
  // 1900 (green/clean) → 2026 (yellow/moderate) → 2100 (red/hazardous)
  // storytelling arc the rest of the app already uses.
  ClimateRegion(
    id: 'delhi',
    name: 'Delhi NCR',
    category: 'aqi',
    latitude: 28.6139,
    longitude: 77.2090,
    altitude: 40000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'delhi_1900_aqi.kml',
      ClimateEra.present2026: 'delhi_2026_aqi.kml',
      ClimateEra.projected2100: 'delhi_2100_aqi.kml',
    },
    bboxNorth: 29.5,
    bboxSouth: 27.5,
    bboxEast: 78.5,
    bboxWest: 76.0,
  ),
];