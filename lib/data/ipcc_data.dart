/// IPCC AR6 scenario data bundled as Dart constants.
/// Source: https://data.ece.iiasa.ac.at/ar6
/// These are not live API calls — IPCC publishes static datasets.
/// Values represent global means under SSP3-7.0 (middle-of-road scenario).
library ipcc_data;

// ── Temperature anomaly (°C relative to 1850-1900 baseline) ─────────────────
const Map<int, double> kTemperatureAnomaly = {
  1900: 0.0,
  1950: 0.2,
  1980: 0.4,
  2000: 0.7,
  2010: 0.9,
  2020: 1.1,
  2026: 1.3,
  2050: 1.9,
  2075: 2.6,
  2100: 3.2,
};

// ── Arctic sea ice extent (million km²) ─────────────────────────────────────
const Map<int, double> kArcticIceExtent = {
  1900: 12.5,
  1950: 11.8,
  1980: 10.9,
  2000: 9.8,
  2010: 8.9,
  2020: 7.6,
  2026: 7.0,
  2050: 4.2,
  2100: 1.1, // near ice-free summers
};

// ── Global mean sea level rise (mm relative to 1900) ────────────────────────
const Map<int, double> kSeaLevelRise = {
  1900: 0,
  1950: 80,
  1980: 150,
  2000: 200,
  2010: 240,
  2020: 290,
  2026: 330,
  2050: 520,
  2100: 900, // SSP3-7.0 median
};

// ── Global forest cover loss (% of 1900 baseline) ───────────────────────────
const Map<int, double> kForestCoverLoss = {
  1900: 0,
  1950: 5.0,
  1980: 12.0,
  2000: 17.0,
  2010: 20.0,
  2020: 23.5,
  2026: 25.0,
  2050: 32.0,
  2100: 40.0,
};

// ── Regional data for app regions ───────────────────────────────────────────
class IpccRegionData {
  final String regionId;
  final String name;
  final Map<int, String> description; // era → narrative seed for Gemini

  // Climate stats per era [1900, 2026, 2100]
  final Map<int, double> localTempAnomaly;
  final Map<int, double> iceExtentKm2;    // for glacier regions
  final Map<int, double> seaLevelMm;      // for coastal regions
  final Map<int, double> forestCoverPct;  // for forest regions

  const IpccRegionData({
    required this.regionId,
    required this.name,
    required this.description,
    required this.localTempAnomaly,
    this.iceExtentKm2 = const {},
    this.seaLevelMm = const {},
    this.forestCoverPct = const {},
  });
}

const List<IpccRegionData> kRegionIpccData = [
  IpccRegionData(
    regionId: 'arctic',
    name: 'Arctic Circle',
    localTempAnomaly: {1900: 0.0, 2026: 2.1, 2100: 5.8},
    iceExtentKm2: {1900: 12500000, 2026: 7000000, 2100: 1100000},
    description: {
      1900: 'The Arctic in 1900 was a vast frozen expanse, with sea ice covering 12.5 million square kilometres each summer. Indigenous communities had lived in harmony with this landscape for millennia.',
      2026: 'Today the Arctic is warming four times faster than the global average. Sea ice now covers just 7 million square kilometres in summer — a loss the size of India since 1900.',
      2100: 'By 2100 under current trajectories, the Arctic will experience its first ice-free summers. Only 1.1 million km² of sea ice remains, confined to the oldest, thickest ice near Canada.',
    },
  ),
  IpccRegionData(
    regionId: 'himalaya',
    name: 'Himalaya',
    localTempAnomaly: {1900: 0.0, 2026: 1.5, 2100: 3.9},
    iceExtentKm2: {1900: 40000, 2026: 32000, 2100: 8000},
    description: {
      1900: 'The Himalayan glaciers in 1900 were stable, feeding the rivers that sustain two billion people across South Asia.',
      2026: 'Himalayan glaciers have lost 20% of their volume since 1900. Glacial lake outburst floods are increasing, threatening downstream communities.',
      2100: 'The Himalayas will lose 80% of their glacial mass by 2100. Rivers like the Ganges and Indus will face severe seasonal water stress, affecting agricultural systems across South Asia.',
    },
  ),
  IpccRegionData(
    regionId: 'amazon',
    name: 'Amazon Basin',
    localTempAnomaly: {1900: 0.0, 2026: 1.2, 2100: 3.1},
    forestCoverPct: {1900: 100, 2026: 75, 2100: 50},
    description: {
      1900: 'The Amazon rainforest covered 5.5 million km² in 1900, home to 10% of all species on Earth and storing 150 billion tonnes of carbon.',
      2026: 'The Amazon has lost 25% of its original cover. The forest is approaching a tipping point — at 20–25% loss, parts may transition permanently to savanna.',
      2100: 'At current deforestation rates, up to 50% of the Amazon could be replaced by degraded grassland, releasing stored carbon equivalent to a decade of global emissions.',
    },
  ),
  IpccRegionData(
    regionId: 'pacific',
    name: 'Pacific Islands',
    localTempAnomaly: {1900: 0.0, 2026: 1.1, 2100: 2.8},
    seaLevelMm: {1900: 0, 2026: 350, 2100: 1000},
    description: {
      1900: 'Pacific island nations in 1900 were ecological jewels — low-lying atolls built over millennia, surrounded by coral reefs teeming with marine life.',
      2026: 'Sea levels around the Pacific have risen 35 cm since 1900. Saltwater intrusion now contaminates freshwater aquifers on many atolls, and storm surges reach further inland.',
      2100: 'With 1 metre of sea level rise projected by 2100, nations like Tuvalu, Kiribati, and the Marshall Islands face existential threats. Most inhabited islands will be submerged or uninhabitable.',
    },
  ),
  IpccRegionData(
    regionId: 'maldives',
    name: 'Maldives',
    localTempAnomaly: {1900: 0.0, 2026: 1.0, 2100: 2.7},
    seaLevelMm: {1900: 0, 2026: 330, 2100: 900},
    description: {
      1900: 'The Maldives in 1900 was a nation of 1,200 islands averaging just 1.5 metres above sea level, sustained by healthy coral reefs.',
      2026: 'Sea levels have risen 33 cm. Coral bleaching has affected 60% of reefs. The Maldives government has already purchased land in India as a contingency.',
      2100: 'With 90 cm of sea level rise under SSP3, 80% of the Maldives landmass will be uninhabitable by 2100. The nation is studying how to preserve cultural identity without a physical homeland.',
    },
  ),
];

IpccRegionData? getRegionData(String regionId) {
  try {
    return kRegionIpccData.firstWhere((r) => r.regionId == regionId);
  } catch (_) {
    return null;
  }
}