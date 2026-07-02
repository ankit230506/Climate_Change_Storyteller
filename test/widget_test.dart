import 'package:flutter_test/flutter_test.dart';
import 'package:climate_storyteller/main.dart';

void main() {
  testWidgets('App onboarding screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ClimateStorytellerApp());
    expect(find.byType(ClimateStorytellerApp), findsOneWidget);
  });
}
