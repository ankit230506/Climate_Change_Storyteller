/// All named routes for the Climate Change Storyteller app.
class AppRoutes {
  AppRoutes._();
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const apiSetup = '/api-setup';
  static const shell = '/shell';
  static const explore = '/explore';
  static const regionDetail = '/region-detail';
  static const storyMode = '/story-mode';
  static const kmlMap = '/kml-map';
  static const aqiControl = '/aqi-control';
  static const dataInsights = '/data-insights';
  static const settings = '/settings';
  static const lgConnect = '/lg-connect';
}

/// Bottom navigation tab indices — single source of truth.
class NavTab {
  NavTab._();
  static const explore = 0;
  static const storyMode = 1;
  static const settings = 2;
}
