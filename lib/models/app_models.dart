/// Represents the connection state of the Liquid Galaxy rig.
enum LGConnectionStatus { disconnected, connecting, connected, error }

class LGRigState {
  final LGConnectionStatus status;
  final String? ipAddress;
  final int port;
  final int screenCount;
  final int? latencyMs;
  final String? currentKml;
  final String? errorMessage;

  const LGRigState({
    this.status = LGConnectionStatus.disconnected,
    this.ipAddress,
    this.port = 2222,
    this.screenCount = 5,
    this.latencyMs,
    this.currentKml,
    this.errorMessage,
  });

  bool get isConnected => status == LGConnectionStatus.connected;

  LGRigState copyWith({
    LGConnectionStatus? status,
    String? ipAddress,
    int? port,
    int? screenCount,
    int? latencyMs,
    String? currentKml,
    String? errorMessage,
  }) {
    return LGRigState(
      status: status ?? this.status,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      screenCount: screenCount ?? this.screenCount,
      latencyMs: latencyMs ?? this.latencyMs,
      currentKml: currentKml ?? this.currentKml,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() =>
      'LGRigState(status: $status, ip: $ipAddress:$port, screens: $screenCount)';
}

/// Climate era enum — drives KML file selection throughout the app.
enum ClimateEra {
  preindustrial1900,
  present2026,
  projected2100;

  String get label {
    switch (this) {
      case ClimateEra.preindustrial1900:
        return '1900';
      case ClimateEra.present2026:
        return '2026';
      case ClimateEra.projected2100:
        return '2100';
    }
  }

  String get subtitle {
    switch (this) {
      case ClimateEra.preindustrial1900:
        return 'Pre-industrial';
      case ClimateEra.present2026:
        return 'Now';
      case ClimateEra.projected2100:
        return 'Projection';
    }
  }
}

/// A climate region that can be visualized on the LG rig.
class ClimateRegion {
  final String id;
  final String name;
  final String category; // glacier | sealevel | forest | heat
  final double latitude;
  final double longitude;
  final double altitude;
  final String? riskLevel; // Critical | High | Moderate
  final Map<ClimateEra, String> kmlFiles; // era -> KML filename

  const ClimateRegion({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    this.riskLevel,
    required this.kmlFiles,
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
    altitude: 5000000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'arctic_1900_glacier.kml',
      ClimateEra.present2026: 'arctic_2026_glacier.kml',
      ClimateEra.projected2100: 'arctic_2100_glacier.kml',
    },
  ),
  ClimateRegion(
    id: 'himalaya',
    name: 'Himalaya',
    category: 'glacier',
    latitude: 27.9881,
    longitude: 86.9250,
    altitude: 3000000,
    riskLevel: 'High',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'himalaya_1900_glacier.kml',
      ClimateEra.present2026: 'himalaya_2026_glacier.kml',
      ClimateEra.projected2100: 'himalaya_2100_glacier.kml',
    },
  ),
  ClimateRegion(
    id: 'amazon',
    name: 'Amazon Basin',
    category: 'forest',
    latitude: -3.4653,
    longitude: -62.2159,
    altitude: 4000000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'amazon_1900_forest.kml',
      ClimateEra.present2026: 'amazon_2026_forest.kml',
      ClimateEra.projected2100: 'amazon_2100_forest.kml',
    },
  ),
  ClimateRegion(
    id: 'pacific',
    name: 'Pacific Islands',
    category: 'sealevel',
    latitude: -8.7832,
    longitude: 179.0000,
    altitude: 2000000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'pacific_1900_sealevel.kml',
      ClimateEra.present2026: 'pacific_2026_sealevel.kml',
      ClimateEra.projected2100: 'pacific_2100_sealevel.kml',
    },
  ),
  ClimateRegion(
    id: 'sahara',
    name: 'Sahara',
    category: 'heat',
    latitude: 23.4162,
    longitude: 25.6628,
    altitude: 3500000,
    riskLevel: 'High',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'sahara_1900_heat.kml',
      ClimateEra.present2026: 'sahara_2026_heat.kml',
      ClimateEra.projected2100: 'sahara_2100_heat.kml',
    },
  ),
  ClimateRegion(
    id: 'maldives',
    name: 'Maldives',
    category: 'sealevel',
    latitude: 3.2028,
    longitude: 73.2207,
    altitude: 1500000,
    riskLevel: 'Critical',
    kmlFiles: {
      ClimateEra.preindustrial1900: 'maldives_1900_sealevel.kml',
      ClimateEra.present2026: 'maldives_2026_sealevel.kml',
      ClimateEra.projected2100: 'maldives_2100_sealevel.kml',
    },
  ),
];