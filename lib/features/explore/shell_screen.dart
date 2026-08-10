import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/features/explore/explore_screen.dart';
import 'package:climate_storyteller/features/explore/timeline_screen.dart';
import 'package:climate_storyteller/features/narrator/narrator_screen.dart';
import 'package:climate_storyteller/features/explore/story_mode_screen.dart';
import 'package:climate_storyteller/features/explore/settings_screen.dart';
import 'package:climate_storyteller/features/lg_connection/lg_rig_state.dart';
import 'package:climate_storyteller/core/theme/theme_service.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/core/localization/language_service.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<Widget> _screens = [
    const ExploreScreen(),       // 0 - Map + regions
    const TimelineScreen(),      // 1 - 1900/2026/2100 + NOAA stats
    const NarratorScreen(),      // 2 - Gemini + Flutter TTS
    const StoryModeScreen(),     // 3 - Auto-play chapters
    const SettingsScreen(),      // 4 - LG connect + API keys
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colors.bg0,
      endDrawer: _AppNavigationDrawer(
        currentIndex: _currentIndex,
        onSelectScreen: (index) {
          setState(() => _currentIndex = index);
          Navigator.pop(context); // Close drawer
        },
      ),
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _screens),

          // Floating top-right 3-line menu button
          Positioned(
            top: 10,
            right: 12,
            child: SafeArea(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.bg1.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.cardBorder, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.menu, // 3 lines menu icon
                      color: colors.textPrimary,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppNavigationDrawer extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelectScreen;

  const _AppNavigationDrawer({
    required this.currentIndex,
    required this.onSelectScreen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final navItems = [
      (Icons.explore_outlined, Icons.explore, 'nav_explore', 'Interactive Map & Regions'),
      (Icons.calendar_month_outlined, Icons.calendar_month, 'nav_timeline', 'Time Travel 1900 → 2100'),
      (Icons.record_voice_over_outlined, Icons.record_voice_over, 'nav_narrator', 'AI Storyteller Narration'),
      (Icons.auto_stories_outlined, Icons.auto_stories, 'nav_story', 'Automated Story Chapters'),
      (Icons.settings_outlined, Icons.settings, 'nav_settings', 'Liquid Galaxy & Setup'),
    ];

    return Drawer(
      backgroundColor: colors.bg1,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: StreamBuilder<AppLanguage>(
        stream: DI.languageService.languageStream,
        initialData: DI.languageService.currentLanguage,
        builder: (context, langSnap) {
          return SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            child: const Icon(
                              Icons.public,
                              color: AppColors.primary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Climate Storyteller',
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Liquid Galaxy Visualizer',
                                  style: GoogleFonts.nunito(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      StreamBuilder<LGRigState>(
                        stream: DI.lgService.stateStream,
                        initialData: DI.lgService.state,
                        builder: (context, snap) {
                          final connected = snap.data!.isConnected;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: connected
                                  ? AppColors.good.withValues(alpha: 0.15)
                                  : colors.bg3,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: connected
                                    ? AppColors.good.withValues(alpha: 0.4)
                                    : colors.cardBorder,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: connected ? AppColors.good : colors.textMuted,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  connected ? 'LG Rig Connected' : 'LG Rig Disconnected',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: connected ? AppColors.good : colors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Divider(color: colors.cardBorder, height: 1),
                const SizedBox(height: 8),

                // Navigation item list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: navItems.length,
                    itemBuilder: (context, index) {
                      final item = navItems[index];
                      final isSelected = index == currentIndex;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: ListTile(
                            selected: isSelected,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            tileColor: isSelected
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : Colors.transparent,
                            leading: Icon(
                              isSelected ? item.$2 : item.$1,
                              color: isSelected ? AppColors.primary : colors.textSecondary,
                              size: 22,
                            ),
                            title: Text(
                              DI.languageService.translate(item.$3),
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? AppColors.primary : colors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              item.$4,
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                color: colors.textSecondary,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.chevron_right, color: AppColors.primary, size: 20)
                                : null,
                            onTap: () => onSelectScreen(index),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                Divider(color: colors.cardBorder, height: 1),

                // Remove KML Action Tile in Sidebar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      tileColor: AppColors.critical.withValues(alpha: 0.1),
                      leading: const Icon(
                        Icons.layers_clear_outlined,
                        color: AppColors.critical,
                        size: 22,
                      ),
                      title: Text(
                        'Remove KML',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.critical,
                        ),
                      ),
                      subtitle: Text(
                        'Clear active overlays on Liquid Galaxy',
                        style: GoogleFonts.nunito(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                      onTap: () async {
                        Navigator.pop(context); // Close drawer
                        if (!DI.lgService.state.isConnected) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Not connected to LG Rig — connect in Settings'),
                            backgroundColor: AppColors.critical,
                          ));
                          return;
                        }
                        await DI.lgService.cleanKml();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Cleared all KML layers from Liquid Galaxy screens!'),
                            backgroundColor: AppColors.primary,
                          ));
                        }
                      },
                    ),
                  ),
                ),

                Divider(color: colors.cardBorder, height: 1),

                // Theme Quick Toggle Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Icon(
                        isDark ? Icons.dark_mode_outlined : Icons.wb_sunny_outlined,
                        color: isDark ? AppColors.secondary : AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isDark ? 'Dark Theme' : 'Light Theme',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: isDark,
                        activeTrackColor: AppColors.primary,
                        onChanged: (val) {
                          DI.themeService.setThemeMode(
                            val ? AppThemeMode.dark : AppThemeMode.light,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
