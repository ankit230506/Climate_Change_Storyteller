import 'package:climate_storyteller/features/lg_connection/lg_service.dart';
import 'package:climate_storyteller/features/climate_data/climate_data_service.dart';
import 'package:climate_storyteller/features/narrator/narrator_service.dart';
import 'package:climate_storyteller/core/localization/language_service.dart';
import 'package:climate_storyteller/core/theme/theme_service.dart';

class DI {
  DI._();

  static final lgService = LgService();
  
  static final climateDataService = ClimateDataService(
    lgService: lgService,
  );
  
  static final narratorService = NarratorService();

  static final languageService = LanguageService.instance;

  static final themeService = ThemeService.instance;
}
