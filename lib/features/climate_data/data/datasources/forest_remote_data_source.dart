class BBox {
  final double north, south, east, west;
  const BBox({
    required this.north, required this.south,
    required this.east,  required this.west,
  });
}

abstract class ForestRemoteDataSource {
  String buildDeforestationKml({required String regionId, int year = 2023});
  String buildComparisonKml({required String regionId});
  BBox getBBox(String regionId);
}

class ForestRemoteDataSourceImpl implements ForestRemoteDataSource {
  static const Map<String, BBox> _regionBounds = {
    'amazon':   BBox(north: 5,   south: -15, east: -45, west: -80),
    'congo':    BBox(north: 5,   south: -5,  east: 30,  west: 15),
    'borneo':   BBox(north: 7,   south: -4,  east: 119, west: 108),
    'himalaya': BBox(north: 35,  south: 25,  east: 95,  west: 75),
  };

  @override
  BBox getBBox(String regionId) {
    return _regionBounds[regionId] ?? _regionBounds['amazon']!;
  }

  @override
  String buildDeforestationKml({required String regionId, int year = 2023}) {
    final bbox = getBBox(regionId);
    final tileUrl = _buildGfwUrl(year);
    final canopyUrl = _buildCanopyUrl();

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

  @override
  String buildComparisonKml({required String regionId}) {
    final bbox = getBBox(regionId);
    final canopyUrl = _buildCanopyUrl();
    final lossUrl = _buildGfwUrl(2023);
    final midLon = (bbox.east + bbox.west) / 2;
    final midLat = (bbox.north + bbox.south) / 2;

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

  String _buildGfwUrl(int year) {
    return 'https://api.resourcewatch.org/v1/layer/'
        'umd-tree-cover-loss/tile/gee/{z}/{x}/{y}'
        '?startYear=2000&endYear=$year';
  }

  String _buildCanopyUrl() {
    return 'https://api.resourcewatch.org/v1/layer/'
        'umd-tree-cover-density-2000/tile/gee/{z}/{x}/{y}';
  }

  double _cameraRange(BBox bbox) {
    final latSpan = (bbox.north - bbox.south).abs();
    final lonSpan = (bbox.east - bbox.west).abs();
    final span = latSpan > lonSpan ? latSpan : lonSpan;
    return span * 110000 * 2.5;
  }

  String _regionName(String id) => switch (id) {
    'amazon'   => 'Amazon Basin',
    'congo'    => 'Congo Basin',
    'borneo'   => 'Borneo',
    'himalaya' => 'Himalaya',
    _          => id,
  };
}
