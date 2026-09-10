import 'package:flutter_test/flutter_test.dart';
import 'package:climate_storyteller/features/lg_connection/lg_service.dart';

void main() {
  group('Liquid Galaxy 4-Way Screen Element Routing', () {
    test('getLeftMostScreenNumber returns lg5 for 5-screen rig', () {
      expect(getLeftMostScreenNumber(5), equals(5));
      expect(getLeftMostScreenNumber(3), equals(3));
      expect(getLeftMostScreenNumber(7), equals(7));
    });

    test('getMasterScreenNumber returns 1 for all rigs (lg1)', () {
      expect(getMasterScreenNumber(5), equals(1));
      expect(getMasterScreenNumber(3), equals(1));
    });

    test('getRightMostScreenNumber returns lg4 for 5-screen rig and lg2 for 3-screen rig', () {
      expect(getRightMostScreenNumber(5), equals(4));
      expect(getRightMostScreenNumber(3), equals(2));
      expect(getRightMostScreenNumber(7), equals(6));
    });

    test('Screen Element Isolation: Logo ONLY on Leftmost, Slider ONLY on Master, Balloon ONLY on Rightmost', () {
      const sampleKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>Test Document</name>
    <gx:TimeStamp><when>2026-01-01T00:00:00Z</when></gx:TimeStamp>
    <TimeSpan><begin>1900-01-01T00:00:00Z</begin><end>2100-12-31T23:59:59Z</end></TimeSpan>
    <ScreenOverlay>
      <name>Liquid Galaxy Logo</name>
      <Icon><href>http://localhost:81/kml/lg_logo.png</href></Icon>
    </ScreenOverlay>
    <Placemark>
      <name>Scientific Profile</name>
      <gx:balloonVisibility>1</gx:balloonVisibility>
    </Placemark>
  </Document>
</kml>''';

      final lg = LgService();
      final sceneOnly = lg.stripScreenOverlaysForTest(sampleKml);
      final masterContent = lg.stripBalloonVisibilityForTest(sceneOnly);
      expect(masterContent.contains('<ScreenOverlay>'), isFalse, reason: 'Master lg1 must have 0 logo');
      expect(masterContent.contains('<gx:balloonVisibility>1</gx:balloonVisibility>'), isFalse, reason: 'Master lg1 must have 0 balloon popup');
      expect(masterContent.contains('<gx:TimeStamp>'), isTrue, reason: 'Master lg1 MUST retain Time Slider');
      final leftContent = lg.stripBalloonVisibilityForTest(lg.stripTimeSpansForTest(sceneOnly));
      expect(leftContent.contains('<gx:TimeStamp>'), isFalse, reason: 'Leftmost must have 0 time slider');
      expect(leftContent.contains('<gx:balloonVisibility>1</gx:balloonVisibility>'), isFalse, reason: 'Leftmost must have 0 balloon popup');
      final rightContent = lg.ensureBalloonVisibilityForTest(lg.stripTimeSpansForTest(sceneOnly));
      expect(rightContent.contains('<gx:balloonVisibility>1</gx:balloonVisibility>'), isTrue, reason: 'Rightmost MUST retain Balloon popup');
      expect(rightContent.contains('<ScreenOverlay>'), isFalse, reason: 'Rightmost must have 0 logo');
      expect(rightContent.contains('<gx:TimeStamp>'), isFalse, reason: 'Rightmost must have 0 time slider');
      final slaveContent = lg.stripBalloonVisibilityForTest(lg.stripTimeSpansForTest(sceneOnly));
      expect(slaveContent.contains('<ScreenOverlay>'), isFalse);
      expect(slaveContent.contains('<gx:TimeStamp>'), isFalse);
      expect(slaveContent.contains('<gx:balloonVisibility>1</gx:balloonVisibility>'), isFalse);
    });
  });

  group('Liquid Galaxy 3D Geometric Polynomial Shapes & View Ranges', () {
    test('build3DCylinderTower generates tiered facets and wireframe rings', () {
      final kml = LG3DVisuals.build3DCylinderTower(
        centerLat: -3.4653,
        centerLon: -62.2159,
        radiusDeg: 0.25,
        heightMeters: 45000.0,
        segments: 16,
        tiers: 4,
        baseColorAbgr: 'cc22c55e',
        topColorAbgr: 'ee16a34a',
        wireColorAbgr: 'ff4ade80',
        name: 'Amazon 3D Biome Tower',
      );

      expect(kml.contains('<name>Amazon 3D Biome Tower</name>'), isTrue);
      expect(kml.contains('<altitudeMode>relativeToGround</altitudeMode>'), isTrue);
      expect(kml.contains('Tower Tier 1 - Facet'), isTrue);
      expect(kml.contains('Tier 4 Level Ring'), isTrue);
      expect(kml.contains('Tower Top Cap'), isTrue);
    });

    test('build3DGlacialSpire generates 4-sided shaded pyramid faces with apex', () {
      final kml = LG3DVisuals.build3DGlacialSpire(
        centerLat: 27.9881,
        centerLon: 86.9250,
        spanDeg: 0.35,
        heightMeters: 46000.0,
        face1ColorAbgr: 'cceedd00',
        face2ColorAbgr: 'ccffffcc',
        face3ColorAbgr: 'cc00f0ff',
        face4ColorAbgr: 'ccd0e0ff',
        name: 'Himalaya Glacier Spire',
      );

      expect(kml.contains('<name>Himalaya Glacier Spire</name>'), isTrue);
      expect(kml.contains('Glacial Peak South Face'), isTrue);
      expect(kml.contains('Glacial Peak East Face'), isTrue);
      expect(kml.contains('Glacial Peak North Face'), isTrue);
      expect(kml.contains('Glacial Peak West Face'), isTrue);
      expect(kml.contains('86.925000,27.988100,46000.0'), isTrue);
    });

    test('build3DGeodesicDome generates faceted thermal panels', () {
      final kml = LG3DVisuals.build3DGeodesicDome(
        centerLat: 23.4162,
        centerLon: 25.6628,
        radiusDeg: 0.45,
        heightMeters: 35000.0,
        segments: 12,
        faceColorsAbgr: ['ccf97316', 'ccfb923c'],
        name: 'Sahara Heat Dome',
      );

      expect(kml.contains('<name>Sahara Heat Dome</name>'), isTrue);
      expect(kml.contains('Dome Panel 1'), isTrue);
      expect(kml.contains('Dome Panel 12'), isTrue);
      expect(kml.contains('25.662800,23.416200,35000.0'), isTrue);
    });

    test('build3DSensorBeacon and build3DConnectingCorridor generate elevated telemetry geometries', () {
      final beaconKml = LG3DVisuals.build3DSensorBeacon(
        centerLat: 28.75,
        centerLon: 77.30,
        radiusDeg: 0.02,
        heightMeters: 14000.0,
        beaconColorAbgr: 'c000e5ff',
        name: 'Delhi Sub-Station Alpha',
      );

      expect(beaconKml.contains('Beacon Diamond Upper 1'), isTrue);
      expect(beaconKml.contains('Beacon Diamond Lower 1'), isTrue);

      final corridorKml = LG3DVisuals.build3DConnectingCorridor(
        fromLat: 28.75,
        fromLon: 77.30,
        toLat: 28.6139,
        toLon: 77.2090,
        altitudeMeters: 9000.0,
        lineColorAbgr: 'aa00e5ff',
        name: 'Telemetry Link',
      );

      expect(corridorKml.contains('<extrude>1</extrude>'), isTrue);
      expect(corridorKml.contains('<altitudeMode>relativeToGround</altitudeMode>'), isTrue);
      expect(corridorKml.contains('77.300000,28.750000,9000.0'), isTrue);
    });
  });
}

extension LgServiceTestHelpers on LgService {
  String stripScreenOverlaysForTest(String kml) => kml.replaceAll(
        RegExp(r'<ScreenOverlay>.*?</ScreenOverlay>', dotAll: true),
        '',
      );

  String stripTimeSpansForTest(String kml) => kml
      .replaceAll(
        RegExp(
          r'<(gx:)?Time(Span|Stamp|Primitive)\b[^>]*>.*?</\s*(gx:)?Time(Span|Stamp|Primitive)\s*>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'<(gx:)?Time(Span|Stamp|Primitive)\b[^>]*/>',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'<when>[^<]*</when>|<begin>[^<]*</begin>|<end>[^<]*</end>|<gx:begin>[^<]*</gx:begin>|<gx:end>[^<]*</gx:end>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      );

  String stripBalloonVisibilityForTest(String kml) => kml.replaceAll(
        RegExp(r'<gx:balloonVisibility>\s*1\s*</gx:balloonVisibility>', dotAll: true),
        '<gx:balloonVisibility>0</gx:balloonVisibility>',
      );

  String ensureBalloonVisibilityForTest(String kml) {
    if (kml.contains('<gx:balloonVisibility>')) {
      return kml.replaceAll(
        RegExp(r'<gx:balloonVisibility>\s*0\s*</gx:balloonVisibility>', dotAll: true),
        '<gx:balloonVisibility>1</gx:balloonVisibility>',
      );
    }
    return kml.replaceAll('<Placemark>', '<Placemark><gx:balloonVisibility>1</gx:balloonVisibility>');
  }
}
