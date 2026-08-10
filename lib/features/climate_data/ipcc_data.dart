/// IPCC AR6 scenario data bundled as Dart constants.
/// Source: https://data.ece.iiasa.ac.at/ar6
/// These represent global means under SSP3-7.0 (middle-of-road scenario).
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
  2100: 1.1,
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
  2100: 900,
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
  // US EPA AQI scale (0-500) for AQI regions. Unlike the fields above, this
  // is NOT sourced from an IPCC scenario — the IPCC does not publish
  // city-level air quality index projections, since AQI is driven mainly by
  // local pollution policy/emissions controls, not global climate forcing.
  // The 1900 and 2026 values here are real/well-documented; the 2100 value
  // is explicitly an illustrative "if current trends continue unchecked"
  // scenario, not an official projection — see the source line this feeds
  // into in lg_service.dart, which reflects that distinction rather than
  // mislabeling it as "IPCC AR6" like the other categories.
  final Map<int, double> aqiIndex;

  const IpccRegionData({
    required this.regionId,
    required this.name,
    required this.description,
    required this.localTempAnomaly,
    this.iceExtentKm2 = const {},
    this.seaLevelMm = const {},
    this.forestCoverPct = const {},
    this.aqiIndex = const {},
  });
}

const List<IpccRegionData> kRegionIpccData = [
  IpccRegionData(
    regionId: 'arctic',
    name: 'Arctic Circle',
    localTempAnomaly: {1900: 0.0, 2026: 2.1, 2100: 5.8},
    iceExtentKm2: {1900: 12500000, 2026: 7000000, 2100: 1100000},
    description: {
      1900: '''The Arctic in 1900 was a pristine, frozen citadel at the roof of the world. Multi-year sea ice stretched continuously across millions of square kilometers, forming an impenetrable white cap that reflected solar energy back into space and stabilized global climate patterns. Vast ice shelves over three meters thick endured even through the continuous sunlight of midsummer.

Inuit and other Arctic Indigenous communities lived in intricate harmony with this frozen seascape. Hunting sea ice ecosystems for seal, bowhead whale, and walrus, their traditional knowledge and cultural identity were inextricably bound to the predictability of seasonal ice formation and migration routes. Polar bears thrived along the ice edge, stalking prey across endless frozen plains.

Scientific expeditions of the turn of the century marveled at the absolute quiet and vast solitude of the high Arctic. The natural thermal gradient between the icy pole and temperate middle latitudes maintained a powerful polar jet stream, anchoring cold air in the north and preserving global meteorological balance for centuries.''',
      2026: '''Today, the Arctic is undergoing a profound and rapid transformation, warming at four times the global average—a phenomenon known as Arctic amplification. Summer sea ice extent has plummeted to nearly half of its historic coverage, representing a loss of ice area larger than the entire subcontinent of India since 1900.

The character of Arctic ice has fundamentally shifted from thick, multi-year ice to thin, vulnerable single-year ice that melts rapidly each summer. Glaciers across Greenland are discharging billions of tonnes of ice into the North Atlantic annually, accelerating global sea level rise. Permafrost thaw is destabilizing coastal settlements, slumping roads, and releasing trapped methane into the atmosphere.

For Arctic species like polar bears, walruses, and ringed seals, the loss of sea ice represents an existential habitat crisis. Indigenous hunters face increasingly hazardous ice conditions and shifting wildlife corridors. Meanwhile, receding ice has opened new maritime shipping lanes and resource competition, forever changing the remote wilderness of the far north.''',
      2100: '''By 2100 under high-emissions trajectories, the Arctic is projected to experience its first completely ice-free summers. The ancient white shield of multi-year sea ice will be virtually gone, replaced by open dark waters that absorb heat rather than reflect it, driving an accelerating feedback loop of regional and planetary warming.

Local surface temperatures across the high Arctic are projected to surge by up to nearly six degrees Celsius above pre-industrial baselines. Greenland's massive ice sheet will be in a state of irreversible net loss, contributing significantly to global sea levels and altering oceanic thermohaline circulation systems like the Atlantic Meridional Overturning Circulation.

The Arctic ecosystem will have undergone a total ecological regime shift. Ice-dependent marine mammals will face catastrophic range loss, replaced by boreal species migrating northward. Coastal human settlements will have required widespread relocation due to severe erosion and permafrost collapse, leaving the Arctic transformed from a frozen regulator of climate into an open ocean frontline.''',
    },
  ),
  IpccRegionData(
    regionId: 'himalaya',
    name: 'Himalaya',
    localTempAnomaly: {1900: 0.0, 2026: 1.5, 2100: 3.9},
    iceExtentKm2: {1900: 40000, 2026: 32000, 2100: 8000},
    description: {
      1900: '''The Himalayas in 1900 stood as the Third Pole of the Earth—a colossal sanctuary of ice, snow, and towering peaks spanning thousands of kilometers across Asia. Over forty thousand square kilometers of ancient glaciers nestled in the high-altitude valleys, storing vast freshwater reservoirs accumulated over millennia.

These majestic glaciers served as the reliable water towers of Asia. Perennial snowmelt fed the great river systems—the Ganges, Indus, Brahmaputra, Yangtze, and Mekong—providing a steady, life-sustaining flow of water across seasonal dry spells to support over a billion people downstream in agrarian civilisations.

High mountain communities lived in deep spiritual and ecological connection with the snow peaks, revered as sacred deities. Alpine ecosystems, from snow leopard territory above the tree line to lush rhododendron forests below, flourished in stable climatic belts regulated by predictable summer monsoons and winter snows.''',
      2026: '''Today, the Himalayan water towers are melting at an unprecedented rate. Over twenty percent of the region's total glacial ice volume has dissolved since 1900, with retreat rates accelerating dramatically over recent decades as mountain temperatures rise faster than lowland averages.

As glaciers retreat, thousands of meltwater lakes bounded by fragile moraine dams have formed across high mountain valleys. Glacial Lake Outburst Floods (GLOFs) pose severe flash-flood risks to downstream villages, hydroelectric infrastructure, and agricultural fields, while destabilized mountain slopes trigger frequent landslides.

Downstream communities face a dual crisis: immediate risks of catastrophic flooding followed by long-term water scarcity as glacial reservoirs shrink. Snowpack is melting earlier in spring, disrupting agricultural planting cycles and reducing late-summer streamflow for nearly two billion people who rely on these river basins for drinking water, farming, and power generation.''',
      2100: '''By 2100, the Himalayas are projected to lose up to eighty percent of their total ice mass under current emissions scenarios. Many lower-altitude glaciers will have disappeared entirely, leaving exposed grey rock and gravel beds where centuries of brilliant blue ice once lay.

The seasonal rhythm of Asia's major rivers will be fundamentally altered. Without the buffering capacity of glacial meltwater during dry seasons, river basins across South and East Asia will experience severe water stress, acute dry-season droughts, and heightened flood spikes during intense monsoonal weather events.

Subtropical and alpine ecosystems will be forced upwards into shrinking vertical bands, causing severe habitat fragmentation for endangered mountain wildlife like the snow leopard and blue sheep. Mountain communities will have adapted through costly water storage infrastructure or faced migration from water-scarce alpine valleys.''',
    },
  ),
  IpccRegionData(
    regionId: 'amazon',
    name: 'Amazon Basin',
    localTempAnomaly: {1900: 0.0, 2026: 1.2, 2100: 3.1},
    forestCoverPct: {1900: 100, 2026: 75, 2100: 50},
    description: {
      1900: '''In 1900, the Amazon rainforest was an unbroken, emerald expanse of over five and a half million square kilometers—the largest biological sanctuary on planet Earth. Its dense, multi-layered canopy created its own weather system, generating flying rivers of moisture that recycled rainfall across the South American continent.

The basin housed ten percent of all known terrestrial species on Earth. Jaguars roamed vast undisturbed territories, while pink river dolphins navigated deep river channels. The massive biomass of the forest stored an estimated one hundred and fifty billion tonnes of carbon, acting as a giant global carbon sink that cooled the planet.

Hundreds of Indigenous nations lived throughout the forest basin, possessing deep botanical and ecological wisdom. They managed forest landscapes sustainably through agroforestry and traditional practices without disrupting the overarching structure of the tropical ecosystem.''',
      2026: '''Today, the Amazon basin has lost a quarter of its original forest canopy due to deforestation, agricultural expansion, road construction, and commercial logging. Large swaths of the southern and eastern edges of the forest have been fragmented into cattle pastures and cropland.

Climate change has brought increasingly severe droughts and record heatwaves to the basin, causing widespread tree mortality and wild forest fires in ecosystems that historically rarely burned. In degraded regions, the forest has shifted from absorbing atmospheric carbon to emitting it during dry months.

Scientists warn that the Amazon is rapidly approaching a critical ecological tipping point. At twenty to twenty-five percent total forest loss combined with global warming, large portions of the moist tropical forest may undergo irreversible dieback, transitioning permanently into dry savanna landscapes.''',
      2100: '''By 2100 under continued high emissions and deforestation, up to half of the Amazon rainforest could be converted into degraded tropical savanna and scrubland. The continuous canopy that once cooled South America will be severely fragmented, collapsing the continental water cycle and rain generation.

The release of tens of billions of tonnes of carbon from decaying and burning trees will significantly accelerate global climate change, equivalent to years of global fossil fuel emissions. The rich biodiversity of the Amazon will face catastrophic losses, with thousands of endemic plant and animal species driven toward extinction.

Indigenous communities and local populations will lose their historic homelands and vital forest resources. The collapse of the Amazonian hydrological system will trigger severe agricultural droughts across southern South America, altering weather patterns across the Americas.''',
    },
  ),
  IpccRegionData(
    regionId: 'pacific',
    name: 'Pacific Islands',
    localTempAnomaly: {1900: 0.0, 2026: 1.1, 2100: 2.8},
    seaLevelMm: {1900: 0, 2026: 350, 2100: 1000},
    description: {
      1900: '''In 1900, the island nations of the Pacific were vibrant, self-sustaining ocean sanctuaries scattered across the vast blue expanse of the world's largest ocean. Low-lying coral atolls and volcanic islands were fringed by healthy, thriving coral reefs teeming with colorful marine life.

Pacific islanders were master voyagers and ocean stewards. Their rich cultural traditions, oral histories, and daily livelihoods were rooted in deep sea navigation, coastal fishing, and taro cultivation in freshwater lenses fed by predictable tropical rainfall.

The surrounding coral barrier reefs acted as natural wave breakers, dissipating ocean swells and protecting island shorelines from coastal erosion. The marine and terrestrial ecosystems operated in stable equilibrium, isolated from major global industrial footprints.''',
      2026: '''Today, Pacific island nations stand on the frontlines of global climate change. Sea levels surrounding the islands have risen by thirty-five centimeters since 1900, with rates of rise accelerating markedly over recent decades due to thermal expansion of warming oceans and melting land ice.

Rising ocean tides and violent storm surges regularly inundate low-lying islands, forcing saltwater into underground freshwater aquifers and destroying traditional agricultural crops like taro. Coastal erosion is washing away beaches, roads, and ancestral burial grounds.

Ocean warming and acidification have triggered recurring marine heatwaves and mass coral bleaching events across the Pacific. Fragile reef ecosystems are deteriorating, reducing coastal protection and diminishing fish populations vital for food security across island communities.''',
      2100: '''By 2100, sea level rise of up to one full meter will present an existential threat to low-lying Pacific atoll nations such as Kiribati, Tuvalu, and the Marshall Islands. Large portions of inhabited islands will experience frequent or permanent inundation, rendering them uninhabitable.

Saltwater intrusion will have completely compromised freshwater sources and agricultural lands on low atolls. Coral reefs will be severely degraded under combined thermal stress and ocean acidification, destroying natural breakwaters and coastal marine biodiversity.

Island populations face forced climate displacement and the loss of physical homelands. Pacific nations are actively establishing legal frameworks to preserve their national sovereignty, maritime zones, and rich cultural heritage even if their physical territories become submerged under ocean waters.''',
    },
  ),
  IpccRegionData(
    regionId: 'maldives',
    name: 'Maldives',
    localTempAnomaly: {1900: 0.0, 2026: 1.0, 2100: 2.7},
    seaLevelMm: {1900: 0, 2026: 330, 2100: 900},
    description: {
      1900: '''In 1900, the Maldives was an idyllic archipelago of nearly twelve hundred low-lying coral islands stretching across the central Indian Ocean. Resting on average just one and a half meters above sea level, the islands were masterpiece formations of living coral architecture constructed over thousands of years.

The island communities lived in harmony with the sea, relying on artisanal pole-and-line fishing and coconut palm cultivation. The surrounding turquoise lagoons and outer barrier reefs provided abundant marine harvests and natural shelter against ocean tempests.

Freshwater lenses floating atop underground saltwater layers sustained coconut groves, fruit trees, and island wells. The delicate balance between coral growth and wave action kept island shorelines stable and naturally replenished.''',
      2026: '''Today, the Maldives is one of the most vulnerable nations on Earth to climate change. Local sea levels have risen by thirty-three centimeters since 1900, narrowing beaches and causing severe shoreline erosion across over two-thirds of inhabited islands.

Rising sea temperatures have caused severe, repeated coral bleaching events, affecting over sixty percent of the country's living reefs. As living coral dies, the islands lose their natural defense against ocean waves, making coastal infrastructure and resorts increasingly vulnerable to high tides.

Saltwater intrusion has contaminated freshwater aquifers on nearly all inhabited islands, requiring expensive desalination plants to supply drinking water. The Maldivian government has invested heavily in land reclamation, artificial islands like Hulhumalé, and sea walls to protect its population.''',
      2100: '''By 2100 under IPCC emissions scenarios, sea levels in the Indian Ocean are projected to rise by up to ninety centimeters. Under these conditions, over eighty percent of the Maldives land area will be inundated or subject to routine flooding during high tides.

Without living, growing coral reefs to keep pace with sea level rise and dissipate wave energy, low-lying islands will face overwhelming coastal erosion and frequent overwash events during seasonal storms.

The nation faces profound questions regarding physical survival and sovereign preservation. Comprehensive relocation plans, artificial floating cities, and international legal agreements to preserve Maldivian sovereignty and maritime boundaries are being explored as the archipelago faces total transformation.''',
    },
  ),
  IpccRegionData(
    regionId: 'sahara',
    name: 'Sahara',
    localTempAnomaly: {1900: 0.5, 2026: 1.5, 2100: 3.5},
    seaLevelMm: {1900: 0, 2026: 0, 2100: 0},
    description: {
      1900: '''In 1900, the Sahara Desert was already the largest hot desert on Earth, spanning over nine million square kilometers across North Africa. Its vast dunes, rocky plateaus, and sparse oases had established an extreme, arid equilibrium over millennia.

Nomadic peoples, including the Tuareg and Bedouin, possessed master adaptations for desert survival. Traversing ancient trade routes, they relied on deep water wells, oasis date palm agriculture, and seasonal movements guided by intimate knowledge of desert microclimates.

While harsh, the desert supported specialized wildlife like addax antelopes, dorcas gazelles, and desert foxes adapted to survive on minimal water. Summer heat reached extreme levels, but nighttime cooling provided thermal relief across the arid expanse.''',
      2026: '''Today, the Sahara is warming at a rate significantly faster than the global average, with surface temperatures having increased by one and a half degrees Celsius above pre-industrial levels. Extreme heatwaves exceeding fifty degrees Celsius are becoming longer and more frequent.

The southern border of the desert is actively expanding southward into the Sahel region—a process known as desertification. Declining and erratic rainfall combined with extreme heat is destroying arable land, drying up traditional wells, and displacing pastoral communities.

Dust storms originating in the Sahara have increased in intensity, lifting millions of tonnes of mineral dust into the atmosphere. These airborne dust plumes travel across the Atlantic Ocean, affecting air quality across West Africa, the Caribbean, and the Americas.''',
      2100: '''By 2100, the Sahara is projected to warm by three and a half degrees Celsius above historical baselines. Peak summer temperatures will regularly breach fifty-five degrees Celsius, pushing environmental conditions beyond the limits of human physiological tolerance without artificial cooling.

Desertification will have pushed the Sahara's borders further south, consuming vast tracts of agricultural land in the Sahel and triggering widespread food insecurity, water scarcity, and forced migration across North and West Africa.

Oasis ecosystems will face total drying as deep aquifers deplete under extreme evaporation rates. The region will be dominated by hyper-arid wasteland conditions, posing extreme challenges for human habitation, livestock grazing, and regional stability.''',
    },
  ),
  IpccRegionData(
    regionId: 'delhi',
    name: 'Delhi NCR',
    localTempAnomaly: {1900: 0.3, 2026: 1.4, 2100: 3.4},
    aqiIndex: {1900: 40, 2026: 198, 2100: 280},
    description: {
      1900: '''In 1900, Delhi was a historic city nestled along the banks of the Yamuna River, surrounded by green agricultural fields, ridge forests, and historic monuments. Pre-industrial air quality was clean, with natural dust and wood fires being the primary ambient emissions.

The Yamuna River flowed clean and clear, supporting vibrant riverbank agriculture, fisheries, and public bathing. Seasonal monsoons brought predictable rains that recharged local groundwater tables and filled historical stepwells across the region.

The urban footprint was modest, allowing natural cooling from surrounding forests and river corridors. Summer heat was managed through traditional architecture, courtyard ventilation, and shaded gardens.''',
      2026: '''Today, the Delhi National Capital Region is a vast megacity of over thirty million people, facing severe climate and environmental challenges. Local temperatures have risen by nearly one and a half degrees Celsius, amplified by an intense urban heat island effect.

Delhi is regularly ranked among the world's most atmospheric-polluted major capitals. During winter months, a toxic blanket of smog composed of vehicular exhaust, industrial emissions, construction dust, and agricultural crop stubble burning traps air pollution in the "Very Poor" to "Hazardous" AQI range.

Extreme weather events have intensified. Delhi experiences unprecedented summer heatwaves reaching nearly fifty degrees Celsius, alongside intense urban flash floods during compressed monsoon downpours that strain urban infrastructure and public health.''',
      2100: '''By 2100 under unchecked urban growth and emissions, summer temperatures in Delhi NCR are projected to rise by over three and a half degrees Celsius. Combined heat and humidity levels will frequently exceed lethal wet-bulb temperature thresholds, creating hazardous conditions for outdoor workers and vulnerable populations.

Without aggressive clean energy, electric mobility, and regional pollution controls, severe air pollution could persist as a year-round crisis. Ground-level ozone and fine particulate matter will cause chronic health impacts and reduced life expectancy across the metropolitan region.

The Yamuna River basin and regional groundwater supplies will face extreme stress from demand and altered monsoonal patterns. Transformative green infrastructure, massive urban afforestation, and clean energy transitions will be critical to maintaining livability in the megacity.''',
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

double getInterpolatedTemperature(int year) => _interpolate(kTemperatureAnomaly, year);
double getInterpolatedSeaLevel(int year) => _interpolate(kSeaLevelRise, year);
double getInterpolatedIceExtent(int year) => _interpolate(kArcticIceExtent, year);
double getInterpolatedForestLoss(int year) => _interpolate(kForestCoverLoss, year);

double _interpolate(Map<int, double> data, int year) {
  final years = data.keys.toList()..sort();
  if (year <= years.first) return data[years.first]!;
  if (year >= years.last)  return data[years.last]!;
  for (int i = 0; i < years.length - 1; i++) {
    if (year >= years[i] && year <= years[i + 1]) {
      final t = (year - years[i]) / (years[i + 1] - years[i]);
      return data[years[i]]! + t * (data[years[i + 1]]! - data[years[i]]!);
    }
  }
  return 0;
}