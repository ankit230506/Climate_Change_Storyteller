import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_storyteller/features/explore/explore_screen.dart';
import 'package:climate_storyteller/features/explore/custom_region_service.dart';
import 'package:climate_storyteller/features/explore/climate_region.dart';

class _TestHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TestHttpOverrides();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CustomRegionService.instance.clearAll();
  });

  group('ExploreScreen Custom Locations UI Tests', () {
    testWidgets('Remove All Added button is visible when custom locations exist and clears them on confirm', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final service = CustomRegionService.instance;
        final r = ClimateRegion(
          id: 'custom_widget_test',
          name: 'Widget Test Location',
          category: 'heat',
          latitude: 10.0,
          longitude: 20.0,
          altitude: 350000,
          riskLevel: 'Moderate',
          kmlFiles: ClimateRegion.generateKmlFiles('custom_widget_test', 'heat'),
          bboxNorth: 12,
          bboxSouth: 8,
          bboxEast: 22,
          bboxWest: 18,
          imageUrl: '',
          description: 'Widget test region',
          isCustom: true,
        );
        await service.addRegion(r);

        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const MaterialApp(
          home: ExploreScreen(),
        ));
        await tester.pump(const Duration(milliseconds: 300));

        final removeAllBtn = find.byKey(const Key('remove_all_custom_locations_btn'));
        expect(removeAllBtn, findsOneWidget);

        await tester.ensureVisible(removeAllBtn);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(removeAllBtn);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Remove All Added Locations?'), findsOneWidget);
        final confirmBtn = find.text('Remove All');
        expect(confirmBtn, findsOneWidget);
        await tester.tap(confirmBtn);
        await tester.pump(const Duration(milliseconds: 300));
        expect(service.customRegions, isEmpty);
        expect(find.byKey(const Key('remove_all_custom_locations_btn')), findsNothing);
      });
    });
  });
}
