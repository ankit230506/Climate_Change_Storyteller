/// Climate era enum — drives KML file selection throughout the app.
enum ClimateEra {
  preindustrial1900,
  midCentury1950,
  lateCentury1980,
  present2026,
  midProjection2060,
  projected2100;

  String get label {
    switch (this) {
      case ClimateEra.preindustrial1900:
        return '1900';
      case ClimateEra.midCentury1950:
        return '1950';
      case ClimateEra.lateCentury1980:
        return '1980';
      case ClimateEra.present2026:
        return '2026';
      case ClimateEra.midProjection2060:
        return '2060';
      case ClimateEra.projected2100:
        return '2100';
    }
  }

  String get subtitle {
    switch (this) {
      case ClimateEra.preindustrial1900:
        return 'Pre-industrial';
      case ClimateEra.midCentury1950:
        return 'Mid 20th C.';
      case ClimateEra.lateCentury1980:
        return 'Late 20th C.';
      case ClimateEra.present2026:
        return 'Now';
      case ClimateEra.midProjection2060:
        return 'Mid 21st C.';
      case ClimateEra.projected2100:
        return 'Projection';
    }
  }
}
