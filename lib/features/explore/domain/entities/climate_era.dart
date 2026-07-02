/// Climate era enum — drives KML file selection throughout the app.
enum ClimateEra {
  preindustrial1900,
  present2026,
  projected2100;

  String get label {
    switch (this) {
      case ClimateEra.preindustrial1900:
        return '1900';
      case ClimateEra.present2026:
        return '2026';
      case ClimateEra.projected2100:
        return '2100';
    }
  }

  String get subtitle {
    switch (this) {
      case ClimateEra.preindustrial1900:
        return 'Pre-industrial';
      case ClimateEra.present2026:
        return 'Now';
      case ClimateEra.projected2100:
        return 'Projection';
    }
  }
}
