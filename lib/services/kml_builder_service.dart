import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/app_models.dart';
import '../data/ipcc_data.dart';

/// Fetches real climate data from NASA GIBS, NOAA, and IPCC AR6
/// and converts it into KML files ready to send to the LG rig.
class KmlBuilderService {
  KmlBuilderService._();
  static final KmlBuilderService instance = KmlBuilderService._();

  // ── NASA GIBS base URL (free, no API key) ────────────────────────────────
  // WMTS endpoint for satellite imagery tiles
  static const _gibsBase =
      'https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi';

  // ── NOAA CDO API (free key via email at ncei.noaa.gov) ──────────────────
  static const _noaaBase = 'https://www.ncei.noaa.gov/cdo-web/api/v2';

  // ── NASA GIBS layer names per climate type ────────────────────────────────
  static const Map<String, String> _gibsLayers = {
    'glacier':  'MODIS_Terra_Sea_Ice_Extent',
    'sealevel': 'VIIRS_NOAA20_CorrectedReflectance_TrueColor',
    'forest':   'MODIS_Terra_NDVI_8Day',
    'heat':     'MODIS_Terra_Land_Surface_Temp_Day',
  };

  // ── Cache directory ──────────────────────────────────────────────────────
  Future<Directory> get _kmlDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/kmls');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC — build and cache a KML file for a region + era
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns the local file path of the KML ready to SCP to the LG rig.
  Future<String> buildKml({
    required ClimateRegion region,
    required ClimateEra era,
    String? noaaApiKey,
  }) async {
    final filename = '${region.id}_${era.label}_${region.category}.kml';
    final dir = await _kmlDir;
    final file = File('${dir.path}/$filename');

    // Return cached file if fresh (< 24 h old)
    if (file.existsSync()) {
      final age = DateTime.now().difference(file.lastModifiedSync());
      if (age.inHours < 24) return file.path;
    }

    final kml = await _generateKml(region: region, era: era,
        noaaApiKey: noaaApiKey);
    await file.writeAsString(kml, encoding: utf8);
    return file.path;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE — KML generation logic
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> _generateKml({
    required ClimateRegion region,
    required ClimateEra era,
    String? noaaApiKey,
  }) async {
    final regionData = getRegionData(region.id);
    final eraYear = int.parse(era.label);

    // Fetch live data where available; fall back to IPCC constants
    final overlayUrl = _buildGibsOverlayUrl(region.category, era);
    final stats = _getEraStats(regionData, region.category, eraYear);
    final noaaTemp = await _fetchNoaaTemperature(noaaApiKey);

    return _buildKmlString(
      region: region,
      era: era,
      overlayUrl: overlayUrl,
      stats: stats,
      noaaGlobalTemp: noaaTemp,
      regionData: regionData,
    );
  }

  // ── NASA GIBS overlay URL ─────────────────────────────────────────────────
  /// Builds a WMS GetMap URL for a GIBS layer.
  /// For 1900 and 2100 we use the closest real date available or a proxy.
  String _buildGibsOverlayUrl(String category, ClimateEra era) {
    final layer = _gibsLayers[category] ?? _gibsLayers['glacier']!;

    // GIBS only has real data from ~2000 onwards.
    // For 1900 → use oldest available MODIS (2000-02-24).
    // For 2100 → use most recent as visual proxy; IPCC data carries the story.
    final date = switch (era) {
      ClimateEra.preindustrial1900 => '2000-02-24', // oldest MODIS
      ClimateEra.present2026       => '2026-01-01',
      ClimateEra.projected2100     => '2024-01-01', // proxy; story from IPCC
    };

    return '$_gibsBase?'
        'SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0'
        '&LAYERS=$layer'
        '&CRS=CRS:84'
        '&FORMAT=image/png'
        '&WIDTH=1024&HEIGHT=512'
        '&BBOX=-180,-90,180,90'
        '&TIME=$date';
  }

  // ── NOAA temperature fetch ────────────────────────────────────────────────
  /// Fetches the latest global temperature anomaly from NOAA CDO.
  /// Requires a free NOAA token (register at ncei.noaa.gov).
  /// Returns null gracefully if no key or network failure.
  Future<double?> _fetchNoaaTemperature(String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) return null;
    try {
      final uri = Uri.parse(
        '$_noaaBase/data?datasetid=GHCND'
        '&datatypeid=TAVG'
        '&stationid=GHCND:USW00094728' // Central Park, NY — global proxy
        '&limit=1'
        '&sortfield=date&sortorder=desc',
      );
      final res = await http.get(uri,
          headers: {'token': apiKey}).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final value = body['results']?[0]?['value'] as num?;
        return value?.toDouble();
      }
    } catch (_) {
      // Network failure — fall back to IPCC data silently
    }
    return null;
  }

  // ── IPCC stats for era ───────────────────────────────────────────────────
  Map<String, String> _getEraStats(
      IpccRegionData? data, String category, int year) {
    final tempAnomaly = _interpolate(kTemperatureAnomaly, year);
    final seaLevel = _interpolate(kSeaLevelRise, year);
    final iceExtent = _interpolate(kArcticIceExtent, year);
    final forestLoss = _interpolate(kForestCoverLoss, year);

    return {
      'temp_anomaly': '+${tempAnomaly.toStringAsFixed(1)}°C',
      'sea_level':    '${seaLevel.toStringAsFixed(0)} mm',
      'ice_extent':   '${(iceExtent / 1e6).toStringAsFixed(1)} M km²',
      'forest_loss':  '${forestLoss.toStringAsFixed(1)}%',
    };
  }

  // ── KML string builder ───────────────────────────────────────────────────
  String _buildKmlString({
    required ClimateRegion region,
    required ClimateEra era,
    required String overlayUrl,
    required Map<String, String> stats,
    required double? noaaGlobalTemp,
    required IpccRegionData? regionData,
  }) {
    final description = regionData?.description[int.parse(era.label)] ??
        'Climate data for ${region.name} — ${era.label}';

    final tempLine = noaaGlobalTemp != null
        ? '<Data name="noaa_live_temp"><value>$noaaGlobalTemp°C</value></Data>'
        : '';

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
     xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>${region.name} — ${era.label}</name>
    <description><![CDATA[$description]]></description>

    <!-- ── Camera position ── -->
    <LookAt>
      <longitude>${region.longitude}</longitude>
      <latitude>${region.latitude}</latitude>
      <altitude>${region.altitude}</altitude>
      <tilt>0</tilt>
      <heading>0</heading>
      <altitudeMode>relativeToGround</altitudeMode>
    </LookAt>

    <!-- ── NASA GIBS satellite overlay ── -->
    <GroundOverlay>
      <name>NASA GIBS — ${era.label}</name>
      <description>Source: NASA GIBS WMTS</description>
      <Icon>
        <href>$overlayUrl</href>
        <viewBoundScale>0.75</viewBoundScale>
      </Icon>
      <LatLonBox>
        <north>90</north>
        <south>-90</south>
        <east>180</east>
        <west>-180</west>
      </LatLonBox>
      <altitude>0</altitude>
      <altitudeMode>clampToGround</altitudeMode>
    </GroundOverlay>

    <!-- ── Region placemark ── -->
    <Placemark>
      <name>${region.name}</name>
      <description><![CDATA[
        <b>${region.name} — ${era.label}</b><br/>
        $description<br/><br/>
        <b>Climate Statistics (IPCC AR6 SSP3-7.0)</b><br/>
        🌡️ Temp anomaly: ${stats['temp_anomaly']}<br/>
        🌊 Sea level rise: ${stats['sea_level']}<br/>
        🧊 Arctic ice extent: ${stats['ice_extent']}<br/>
        🌲 Forest cover loss: ${stats['forest_loss']}<br/>
        $tempLine
      ]]></description>
      <ExtendedData>
        <Data name="era"><value>${era.label}</value></Data>
        <Data name="category"><value>${region.category}</value></Data>
        <Data name="temp_anomaly"><value>${stats['temp_anomaly']}</value></Data>
        <Data name="sea_level_rise"><value>${stats['sea_level']}</value></Data>
        <Data name="ice_extent"><value>${stats['ice_extent']}</value></Data>
        <Data name="forest_loss"><value>${stats['forest_loss']}</value></Data>
        $tempLine
      </ExtendedData>
      <Point>
        <coordinates>${region.longitude},${region.latitude},0</coordinates>
      </Point>
    </Placemark>

    ${_buildCategoryLayer(region, era, stats)}

  </Document>
</kml>''';
  }

  // ── Category-specific KML layers ─────────────────────────────────────────
  String _buildCategoryLayer(
      ClimateRegion region, ClimateEra era, Map<String, String> stats) {
    switch (region.category) {
      case 'glacier':
        return _glacierPolygon(region, era);
      case 'sealevel':
        return _seaLevelPolygon(region, era);
      case 'forest':
        return _forestPolygon(region, era);
      default:
        return '';
    }
  }

  String _glacierPolygon(ClimateRegion region, ClimateEra era) {
    // Opacity decreases across eras to show ice loss
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => 'aa',
      ClimateEra.present2026       => '77',
      ClimateEra.projected2100     => '33',
    };
    final lat = region.latitude;
    final lon = region.longitude;
    final d = 3.0; // degree spread
    return '''
    <Placemark>
      <name>Glacier extent — ${era.label}</name>
      <Style>
        <PolyStyle>
          <color>${opacity}aaddff</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>ff88ccff</color>
          <width>1.5</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              ${lon - d},${lat - d},0
              ${lon + d},${lat - d},0
              ${lon + d},${lat + d},0
              ${lon - d},${lat + d},0
              ${lon - d},${lat - d},0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  String _seaLevelPolygon(ClimateRegion region, ClimateEra era) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => '33',
      ClimateEra.present2026       => '66',
      ClimateEra.projected2100     => 'aa',
    };
    final lat = region.latitude;
    final lon = region.longitude;
    const d = 1.5;
    return '''
    <Placemark>
      <name>Sea level inundation — ${era.label}</name>
      <Style>
        <PolyStyle>
          <color>${opacity}3388ff</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>ff3388ff</color>
          <width>2</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              ${lon - d},${lat - d},0
              ${lon + d},${lat - d},0
              ${lon + d},${lat + d},0
              ${lon - d},${lat + d},0
              ${lon - d},${lat - d},0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  String _forestPolygon(ClimateRegion region, ClimateEra era) {
    final opacity = switch (era) {
      ClimateEra.preindustrial1900 => 'aa',
      ClimateEra.present2026       => '77',
      ClimateEra.projected2100     => '44',
    };
    final lat = region.latitude;
    final lon = region.longitude;
    const d = 4.0;
    return '''
    <Placemark>
      <name>Forest cover — ${era.label}</name>
      <Style>
        <PolyStyle>
          <color>${opacity}22aa55</color>
          <outline>1</outline>
        </PolyStyle>
        <LineStyle>
          <color>ff44bb66</color>
          <width>1.5</width>
        </LineStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              ${lon - d},${lat - d},0
              ${lon + d},${lat - d},0
              ${lon + d},${lat + d},0
              ${lon - d},${lat + d},0
              ${lon - d},${lat - d},0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>''';
  }

  // ── Linear interpolation helper ──────────────────────────────────────────
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

  // ── List cached KML files ────────────────────────────────────────────────
  Future<List<FileSystemEntity>> listCachedKmls() async {
    final dir = await _kmlDir;
    return dir.listSync().where((f) => f.path.endsWith('.kml')).toList();
  }

  Future<void> clearCache() async {
    final dir = await _kmlDir;
    for (final f in dir.listSync()) {
      f.deleteSync();
    }
  }
}