import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/shell_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/region_detail_screen.dart';
import 'utils/app_routes.dart';
import 'models/app_models.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait orientation (smartphone controller)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Set system overlay style to match dark theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg1,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const ClimateStorytellerApp());
}

class ClimateStorytellerApp extends StatelessWidget {
  const ClimateStorytellerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Climate Storyteller',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      initialRoute: AppRoutes.onboarding,
      onGenerateRoute: _generateRoute,
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