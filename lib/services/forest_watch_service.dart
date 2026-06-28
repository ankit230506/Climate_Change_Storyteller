import 'package:http/http.dart' as http;
import 'lg_ssh_service.dart';

/// FEATURE: Global Forest Watch Deforestation Layer
///
/// PURPOSE:
/// Shows real forest loss data on LG rig screens as a KML
/// GroundOverlay. Data comes from Global Forest Watch (GFW)
/// tile API — completely FREE, no API key needed.
///
/// HOW GFW TILES WORK:
/// GFW publishes forest loss data as PNG map tiles at:
/// https://tiles.globalforestwatch.org/umd_tree_cover_loss/
///   latest/dynamic/{z}/{x}/{y}.png
///
/// Each tile shows tree cover loss in red/orange pixels.
/// We embed these tiles as KML GroundOverlay on the LG rig.
///
/// REGIONS SUPPORTED:
///   - Amazon Basin  (-15°S to 5°N, -80°W to -45°W)
///   - Congo Basin   (-5°S to 5°N, 15°E to 30°E)
///   - Borneo        (-4°S to 7°N, 108°E to 119°E)
///   - Himalayas     (25°N to 35°N, 75°E to 95°E)
class ForestWatchService {
  ForestWatchService._();
  static final ForestWatchService instance = ForestWatchService._();

  // GFW tile base URLs — no key needed
  static const _gfwBase =
      'https://tiles.globalforestwatch.org/umd_tree_cover_loss/latest/dynamic';
  static const _canopyBase =
      'https://tiles.globalforestwatch.org/umd_tree_cover_density_2000/latest/dynamic';

  // ── Region bounding boxes ─────────────────────────────────────────────────
  static const Map<String, _BBox> _regionBounds = {
    'amazon':   _BBox(north: 5,   south: -15, east: -45, west: -80),
    'congo':    _BBox(north: 5,   south: -5,  east: 30,  west: 15),
    'borneo':   _BBox(north: 7,   south: -4,  east: 119, west: 108),
    'himalaya': _BBox(north: 35,  south: 25,  east: 95,  west: 75),
  };

  // ════════════════════════════════════════════════════════════════════════
  // BUILD DEFORESTATION KML
  // ════════════════════════════════════════════════════════════════════════

  /// Builds a KML file with GFW forest loss tile overlay.
  /// [regionId] — 'amazon', 'congo', 'borneo', or 'himalaya'
  /// [year]     — 2000-2023 (GFW data range)
  String buildDeforestationKml({
    required String regionId,
    int year = 2023,
  }) {
    final bbox = _regionBounds[regionId]
        ?? _regionBounds['amazon']!;

    // GFW tile URL at zoom level 6 (good balance of detail/performance)
    // We use a WMS-style request for the full bounding box
    final tileUrl = _buildGfwUrl(bbox, year);

    // Canopy density URL (shows existing forest in green)
    final canopyUrl = _buildCanopyUrl(bbox);

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
     xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>Forest Loss — ${_regionName(regionId)} ($year)</name>
    <description>
      Global Forest Watch data showing tree cover loss.
      Red areas = forest lost since 2000.
      Green areas = remaining tree cover.
      Source: Hansen/UMD/Google/USGS/NASA via Global Forest Watch.
    </description>

    <!-- Camera position for this region -->
    <LookAt>
      <longitude>${(bbox.east + bbox.west) / 2}</longitude>
      <latitude>${(bbox.north + bbox.south) / 2}</latitude>
      <altitude>0</altitude>
      <heading>0</heading>
      <tilt>0</tilt>
      <range>${_cameraRange(bbox)}</range>
      <altitudeMode>relativeToGround</altitudeMode>
    </LookAt>

    <!-- Existing tree canopy (green layer, bottom) -->
    <GroundOverlay>
      <name>Tree Cover 2000 (baseline)</name>
      <color>99ffffff</color>
      <drawOrder>1</drawOrder>
      <Icon>
        <href>$canopyUrl</href>
        <viewBoundScale>1.0</viewBoundScale>
      </Icon>
      <LatLonBox>
        <north>${bbox.north}</north>
        <south>${bbox.south}</south>
        <east>${bbox.east}</east>
        <west>${bbox.west}</west>
      </LatLonBox>
    </GroundOverlay>

    <!-- Forest loss overlay (red layer, top) -->
    <GroundOverlay>
      <name>Tree Cover Loss 2000–$year</name>
      <color>ccffffff</color>
      <drawOrder>2</drawOrder>
      <Icon>
        <href>$tileUrl</href>
        <viewBoundScale>1.0</viewBoundScale>
      </Icon>
      <LatLonBox>
        <north>${bbox.north}</north>
        <south>${bbox.south}</south>
        <east>${bbox.east}</east>
        <west>${bbox.west}</west>
      </LatLonBox>
    </GroundOverlay>

    <!-- Region boundary outline -->
    <Placemark>
      <name>${_regionName(regionId)} boundary</name>
      <Style>
        <LineStyle>
          <color>ff00ff88</color>
          <width>2</width>
        </LineStyle>
        <PolyStyle>
          <color>0000ff88</color>
        </PolyStyle>
      </Style>
      <Polygon>
        <tessellate>1</tessellate>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              ${bbox.west},${bbox.south},0
              ${bbox.east},${bbox.south},0
              ${bbox.east},${bbox.north},0
              ${bbox.west},${bbox.north},0
              ${bbox.west},${bbox.south},0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>

    <!-- Stats placemark in centre -->
    <Placemark>
      <name>${_regionName(regionId)} — Forest Loss Data</name>
      <description><![CDATA[
        <b>${_regionName(regionId)} Deforestation</b><br/>
        Data period: 2000 – $year<br/>
        Source: Global Forest Watch (Hansen et al.)<br/>
        Resolution: 30m per pixel<br/>
        Red = tree cover loss<br/>
        Green = remaining canopy<br/><br/>
        <a href="https://www.globalforestwatch.org">
          globalforestwatch.org
        </a>
      ]]></description>
      <Point>
        <coordinates>
          ${(bbox.east + bbox.west) / 2},
          ${(bbox.north + bbox.south) / 2},0
        </coordinates>
      </Point>
    </Placemark>

  </Document>
</kml>''';
  }

  // ════════════════════════════════════════════════════════════════════════
  // SEND TO LG RIG
  // ════════════════════════════════════════════════════════════════════════

  /// Builds KML and sends it directly to the LG rig.
  Future<void> sendToLG({
    required String regionId,
    int year = 2023,
  }) async {
    final ssh = LGSSHService.instance;
    if (!ssh.state.isConnected) {
      throw Exception('LG rig not connected');
    }

    final kml      = buildDeforestationKml(regionId: regionId, year: year);
    final filename = 'forest_${regionId}_$year.kml';

    await ssh.sendKml(filename, kmlContent: kml);

    // Fly camera to region
    final bbox = _regionBounds[regionId]!;
    await ssh.flyTo(
      latitude:  (bbox.north + bbox.south) / 2,
      longitude: (bbox.east  + bbox.west)  / 2,
      altitude:  _cameraRange(bbox).toDouble(),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // COMPARE TWO YEARS (2000 vs 2023)
  // Sends a split-screen KML showing before/after
  // ════════════════════════════════════════════════════════════════════════

  /// Builds a KML showing forest loss progression.
  /// Used in Story Mode for the "Forests Falling" chapter.
  String buildComparisonKml({required String regionId}) {
    final bbox      = _regionBounds[regionId] ?? _regionBounds['amazon']!;
    final canopyUrl = _buildCanopyUrl(bbox);
    final lossUrl   = _buildGfwUrl(bbox, 2023);
    final midLon    = (bbox.east + bbox.west) / 2;
    final midLat    = (bbox.north + bbox.south) / 2;

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Forest Comparison — ${_regionName(regionId)}</name>

    <LookAt>
      <longitude>$midLon</longitude>
      <latitude>$midLat</latitude>
      <altitude>0</altitude>
      <range>${_cameraRange(bbox)}</range>
      <altitudeMode>relativeToGround</altitudeMode>
    </LookAt>

    <!-- 2000 baseline — left half -->
    <GroundOverlay>
      <name>Forest Cover 2000</name>
      <drawOrder>1</drawOrder>
      <Icon><href>$canopyUrl</href></Icon>
      <LatLonBox>
        <north>${bbox.north}</north>
        <south>${bbox.south}</south>
        <east>$midLon</east>
        <west>${bbox.west}</west>
      </LatLonBox>
    </GroundOverlay>

    <!-- 2023 loss — right half -->
    <GroundOverlay>
      <name>Forest Loss 2000–2023</name>
      <drawOrder>2</drawOrder>
      <Icon><href>$lossUrl</href></Icon>
      <LatLonBox>
        <north>${bbox.north}</north>
        <south>${bbox.south}</south>
        <east>${bbox.east}</east>
        <west>$midLon</west>
      </LatLonBox>
    </GroundOverlay>

    <!-- Dividing line -->
    <Placemark>
      <name>Before | After</name>
      <Style>
        <LineStyle><color>ffffffff</color><width>3</width></LineStyle>
      </Style>
      <LineString>
        <tessellate>1</tessellate>
        <coordinates>
          $midLon,${bbox.south},0
          $midLon,${bbox.north},0
        </coordinates>
      </LineString>
    </Placemark>

  </Document>
</kml>''';
  }

  // ── URL builders ──────────────────────────────────────────────────────────

  String _buildGfwUrl(_BBox bbox, int year) {
    // GFW WMS endpoint for tree cover loss
    return 'https://api.resourcewatch.org/v1/layer/'
        'umd-tree-cover-loss/tile/gee/{z}/{x}/{y}'
        '?startYear=2000&endYear=$year';
  }

  String _buildCanopyUrl(_BBox bbox) {
    return 'https://api.resourcewatch.org/v1/layer/'
        'umd-tree-cover-density-2000/tile/gee/{z}/{x}/{y}';
  }

  double _cameraRange(_BBox bbox) {
    final latSpan = (bbox.north - bbox.south).abs();
    final lonSpan = (bbox.east  - bbox.west ).abs();
    final span    = latSpan > lonSpan ? latSpan : lonSpan;
    return span * 110000 * 2.5; // rough metres per degree
  }

  String _regionName(String id) => switch (id) {
    'amazon'   => 'Amazon Basin',
    'congo'    => 'Congo Basin',
    'borneo'   => 'Borneo',
    'himalaya' => 'Himalaya',
    _          => id,
  };
}

// ── Bounding box data class ───────────────────────────────────────────────────
class _BBox {
  final double north, south, east, west;
  const _BBox({
    required this.north, required this.south,
    required this.east,  required this.west,
  });
}