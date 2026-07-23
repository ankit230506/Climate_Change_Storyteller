import 'package:flutter/material.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/features/explore/explore_screen.dart';
import 'package:climate_storyteller/features/explore/timeline_screen.dart';
import 'package:climate_storyteller/features/narrator/narrator_screen.dart';
import 'package:climate_storyteller/features/climate_data/data_insight_screen.dart';
import 'package:climate_storyteller/features/explore/story_mode_screen.dart';
import 'package:climate_storyteller/features/climate_data/forest_watch_screen.dart';
import 'package:climate_storyteller/features/explore/settings_screen.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/core/localization/language_service.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const ExploreScreen(),       // 0 - Map + regions
    const TimelineScreen(),      // 1 - 1900/2026/2100 + NOAA stats
    const NarratorScreen(),      // 2 - Gemini + Flutter TTS
    const DataInsightsScreen(),  // 3 - fl_chart graphs
    const StoryModeScreen(),     // 4 - Auto-play chapters
    const ForestWatchScreen(),   // 5 - GFW deforestation
    const SettingsScreen(),      // 6 - LG connect + API keys
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg1,
        border: Border(top: BorderSide(color: Color(0xFF1A1E2E), width: 1)),
      ),
      child: StreamBuilder<AppLanguage>(
        stream: DI.languageService.languageStream,
        initialData: DI.languageService.currentLanguage,
        builder: (context, langSnap) {
          return SafeArea(
            top: false,
            child: BottomNavigationBar(
              currentIndex: currentIndex,
              onTap: onTap,
              backgroundColor: Colors.transparent,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppColors.primary,
              unselectedItemColor: AppColors.textMuted,
              selectedLabelStyle: const TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 9),
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.explore_outlined),
                  activeIcon: const Icon(Icons.explore),
                  label: DI.languageService.translate('nav_explore'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.calendar_month_outlined),
                  activeIcon: const Icon(Icons.calendar_month),
                  label: DI.languageService.translate('nav_timeline'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.record_voice_over_outlined),
                  activeIcon: const Icon(Icons.record_voice_over),
                  label: DI.languageService.translate('nav_narrator'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.bar_chart_outlined),
                  activeIcon: const Icon(Icons.bar_chart),
                  label: DI.languageService.translate('nav_insights'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.auto_stories_outlined),
                  activeIcon: const Icon(Icons.auto_stories),
                  label: DI.languageService.translate('nav_story'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.forest_outlined),
                  activeIcon: const Icon(Icons.forest),
                  label: DI.languageService.translate('nav_forest'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.settings_outlined),
                  activeIcon: const Icon(Icons.settings),
                  label: DI.languageService.translate('nav_settings'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
