/// All named routes for the Climate Change Storyteller app.
class AppRoutes {
  AppRoutes._();

  // Onboarding
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const apiSetup = '/api-setup';

  // Main shell (bottom nav)
  static const shell = '/shell';

  // Explore tab
  static const explore = '/explore';
  static const regionDetail = '/region-detail';

  // Timeline tab
  static const timeline = '/timeline';

  // Narrator tab
  static const narrator = '/narrator';

  // Story tab
  static const storyMode = '/story-mode';

  // KML Map tab
  static const kmlMap = '/kml-map';

  // AQI screen
  static const aqiControl = '/aqi-control';

  // Data insights
  static const dataInsights = '/data-insights';

  // Settings tab
  static const settings = '/settings';
  static const lgConnect = '/lg-connect';
}

/// Bottom navigation tab indices — single source of truth.
class NavTab {
  NavTab._();
  static const explore = 0;
  static const timeline = 1;
  static const narrator = 2;
  static const kmlMap = 3;
  static const settings = 4;
}
