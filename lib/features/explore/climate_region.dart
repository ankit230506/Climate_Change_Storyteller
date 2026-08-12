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
  final String imageUrl;
  final String description;

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
    required this.imageUrl,
    required this.description,
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
    altitude: 45000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'arctic_1900_glacier.kml',
      ClimateEra.midCentury1950: 'arctic_1950_glacier.kml',
      ClimateEra.lateCentury1980: 'arctic_1980_glacier.kml',
      ClimateEra.present2026: 'arctic_2026_glacier.kml',
      ClimateEra.midProjection2060: 'arctic_2060_glacier.kml',
      ClimateEra.projected2100: 'arctic_2100_glacier.kml',
    },
    bboxNorth: 85.0,
    bboxSouth: 65.0,
    bboxEast: 60.0,
    bboxWest: -30.0,
    imageUrl: 'https://images.unsplash.com/photo-1517411032315-54ef2cb783bb?w=600&q=80',
    description: 'Rapid Arctic sea ice decline & glacial retreat. The Arctic is warming nearly 4x faster than the global average.',
  ),
  ClimateRegion(
    id: 'himalaya',
    name: 'Himalaya',
    category: 'glacier',
    latitude: 27.9881,
    longitude: 86.9250,
    altitude: 40000,
    riskLevel: 'High',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'himalaya_1900_glacier.kml',
      ClimateEra.midCentury1950: 'himalaya_1950_glacier.kml',
      ClimateEra.lateCentury1980: 'himalaya_1980_glacier.kml',
      ClimateEra.present2026: 'himalaya_2026_glacier.kml',
      ClimateEra.midProjection2060: 'himalaya_2060_glacier.kml',
      ClimateEra.projected2100: 'himalaya_2100_glacier.kml',
    },
    bboxNorth: 36.0,
    bboxSouth: 26.0,
    bboxEast: 100.0,
    bboxWest: 72.0,
    imageUrl: 'https://images.unsplash.com/photo-1589182373726-e4f658ab50f0?w=600&q=80',
    description: 'Third Pole glacier melting threatens freshwater security for over 1.3 billion people across South Asia.',
  ),
  ClimateRegion(
    id: 'amazon',
    name: 'Amazon Basin',
    category: 'forest',
    latitude: -3.4653,
    longitude: -62.2159,
    altitude: 50000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'amazon_1900_forest.kml',
      ClimateEra.midCentury1950: 'amazon_1950_forest.kml',
      ClimateEra.lateCentury1980: 'amazon_1980_forest.kml',
      ClimateEra.present2026: 'amazon_2026_forest.kml',
      ClimateEra.midProjection2060: 'amazon_2060_forest.kml',
      ClimateEra.projected2100: 'amazon_2100_forest.kml',
    },
    bboxNorth: 5.0,
    bboxSouth: -20.0,
    bboxEast: -44.0,
    bboxWest: -80.0,
    imageUrl: 'https://images.unsplash.com/photo-1516026672322-bc52d61a55d5?w=600&q=80',
    description: 'Accelerated tropical deforestation and severe droughts risk pushing the Amazon rainforest past its ecological tipping point.',
  ),
  ClimateRegion(
    id: 'pacific',
    name: 'Pacific Islands',
    category: 'sealevel',
    latitude: -8.7832,
    longitude: 179.0000,
    altitude: 50000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'pacific_1900_sealevel.kml',
      ClimateEra.midCentury1950: 'pacific_1950_sealevel.kml',
      ClimateEra.lateCentury1980: 'pacific_1980_sealevel.kml',
      ClimateEra.present2026: 'pacific_2026_sealevel.kml',
      ClimateEra.midProjection2060: 'pacific_2060_sealevel.kml',
      ClimateEra.projected2100: 'pacific_2100_sealevel.kml',
    },
    bboxNorth: 2.0,
    bboxSouth: -18.0,
    bboxEast: -168.0,
    bboxWest: 165.0,
    imageUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600&q=80',
    description: 'Low-lying island nations facing existential threats from accelerated sea level rise, saltwater intrusion, and king tides.',
  ),
  ClimateRegion(
    id: 'sahara',
    name: 'Sahara',
    category: 'heat',
    latitude: 23.4162,
    longitude: 25.6628,
    altitude: 50000,
    riskLevel: 'High',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'sahara_1900_heat.kml',
      ClimateEra.midCentury1950: 'sahara_1950_heat.kml',
      ClimateEra.lateCentury1980: 'sahara_1980_heat.kml',
      ClimateEra.present2026: 'sahara_2026_heat.kml',
      ClimateEra.midProjection2060: 'sahara_2060_heat.kml',
      ClimateEra.projected2100: 'sahara_2100_heat.kml',
    },
    bboxNorth: 37.0,
    bboxSouth: 15.0,
    bboxEast: 35.0,
    bboxWest: -17.0,
    imageUrl: 'https://images.unsplash.com/photo-1509316975850-ff9c5deb0cd9?w=600&q=80',
    description: 'Desertification expanding south into the Sahel belt, driving record heatwaves and displacement.',
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
      ClimateEra.midCentury1950: 'maldives_1950_sealevel.kml',
      ClimateEra.lateCentury1980: 'maldives_1980_sealevel.kml',
      ClimateEra.present2026: 'maldives_2026_sealevel.kml',
      ClimateEra.midProjection2060: 'maldives_2060_sealevel.kml',
      ClimateEra.projected2100: 'maldives_2100_sealevel.kml',
    },
    bboxNorth: 8.0,
    bboxSouth: -1.0,
    bboxEast: 74.5,
    bboxWest: 72.0,
    imageUrl: 'https://images.unsplash.com/photo-1514282401047-d79a71a590e8?w=600&q=80',
    description: 'The world\'s lowest-lying nation where over 80% of coral islands sit less than 1 meter above sea level.',
  ),
  ClimateRegion(
    id: 'delhi',
    name: 'Delhi NCR',
    category: 'aqi',
    latitude: 28.6139,
    longitude: 77.2090,
    altitude: 12000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'delhi_1900_aqi.kml',
      ClimateEra.midCentury1950: 'delhi_1950_aqi.kml',
      ClimateEra.lateCentury1980: 'delhi_1980_aqi.kml',
      ClimateEra.present2026: 'delhi_2026_aqi.kml',
      ClimateEra.midProjection2060: 'delhi_2060_aqi.kml',
      ClimateEra.projected2100: 'delhi_2100_aqi.kml',
    },
    bboxNorth: 29.5,
    bboxSouth: 27.5,
    bboxEast: 78.5,
    bboxWest: 76.0,
    imageUrl: 'https://images.unsplash.com/photo-1587474260584-136574528ed5?w=600&q=80',
    description: 'Severe urban heat island effects and dangerous air quality index levels impacting tens of millions.',
  ),
];