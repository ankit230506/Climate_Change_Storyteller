import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/features/explore/shell_screen.dart';
import 'package:climate_storyteller/features/explore/onboarding_screen.dart';
import 'package:climate_storyteller/features/explore/region_detail_screen.dart';
import 'package:climate_storyteller/core/constant/app_routes.dart';
import 'package:climate_storyteller/features/explore/climate_region.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DI.languageService.init();
  await DI.themeService.init();

  // Lock to portrait orientation (smartphone controller)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Set initial system overlay style
  _updateSystemOverlayStyle(DI.themeService.isDarkMode);

  runApp(const ClimateStorytellerApp());
}

void _updateSystemOverlayStyle(bool isDark) {
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: AppColors.bg1,
    systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
  ));
}

class ClimateStorytellerApp extends StatelessWidget {
  const ClimateStorytellerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ThemeMode>(
      stream: DI.themeService.themeStream,
      initialData: DI.themeService.currentThemeMode,
      builder: (context, snapshot) {
        final themeMode = snapshot.data ?? ThemeMode.light;
        _updateSystemOverlayStyle(DI.themeService.isDarkMode);

        return MaterialApp(
          title: 'Climate Storyteller',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          initialRoute: AppRoutes.onboarding,
          onGenerateRoute: _generateRoute,
        );
      },
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    final name = settings.name;

    switch (name) {
      case AppRoutes.onboarding:
        return _slide(const OnboardingScreen());

      case AppRoutes.shell:
        return _fade(const ShellScreen());

      case AppRoutes.regionDetail:
        final region = settings.arguments as ClimateRegion?;
        if (region == null) return _slide(const ShellScreen());
        return _slide(RegionDetailScreen(region: region));

      default:
        return _fade(const ShellScreen());
    }
  }

  static PageRoute _slide(Widget page) => PageRouteBuilder(
        pageBuilder: (_, animation, __) => page,
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      );

  static PageRoute _fade(Widget page) => PageRouteBuilder(
        pageBuilder: (_, animation, __) => page,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      );
}