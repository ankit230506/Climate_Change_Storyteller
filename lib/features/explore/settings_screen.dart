import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';
import 'package:climate_storyteller/features/lg_connection/lg_rig_state.dart';
import 'package:climate_storyteller/features/explore/kml_cache_screen.dart';
import 'package:climate_storyteller/features/explore/api_setup_screen.dart';
import 'package:climate_storyteller/core/storage/secure_storage_service.dart';
import 'package:climate_storyteller/core/localization/language_service.dart';
import 'package:climate_storyteller/core/theme/theme_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _runDiagnostics(BuildContext context) {
    final colors = AppColors.of(context);
    if (!DI.lgService.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected to LG Rig — connect first'),
        backgroundColor: AppColors.critical,
      ));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          color: colors.bg1,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text('Running Diagnostics...', style: TextStyle(color: colors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );

    DI.lgService.runDiagnostics().then((result) {
      if (!context.mounted) return;
      Navigator.pop(context); // Dismiss loading dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: colors.bg1,
          title: Text('LG Rig Diagnostic Report', style: TextStyle(color: colors.textPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                result,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: result));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Copied report to clipboard!'),
                  backgroundColor: AppColors.primary,
                ));
              },
              child: const Text('Copy Report'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }).catchError((e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Dismiss loading dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: colors.bg1,
          title: Text('Diagnostics Failed', style: TextStyle(color: colors.textPrimary)),
          content: Text(e.toString(), style: TextStyle(color: colors.textPrimary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    });
  }

  void _setupNetworkLink(BuildContext context) {
    final colors = AppColors.of(context);
    if (!DI.lgService.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected to LG Rig — connect first'),
        backgroundColor: AppColors.critical,
      ));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          color: colors.bg1,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text('Configuring NetworkLink...', style: TextStyle(color: colors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );

    DI.lgService.setupNetworkLink().then((_) {
      if (!context.mounted) return;
      Navigator.pop(context); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('NetworkLink configured and Google Earth relaunched!'),
        backgroundColor: AppColors.good,
      ));
    }).catchError((e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Dismiss loading dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: colors.bg1,
          title: Text('Setup Failed', style: TextStyle(color: colors.textPrimary)),
          content: Text(e.toString(), style: TextStyle(color: colors.textPrimary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    });
  }

  void _openConnect(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LGConnectScreen()));
  }

  void _showLanguageSelector(BuildContext context) {
    final colors = AppColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: colors.cardBorder, width: 1.5)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                DI.languageService.translate('tile_language'),
                style: AppTypography.heading2,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: LanguageService.supportedLanguages.map((lang) {
                    final isSelected = DI.languageService.currentLanguage.code == lang.code;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      title: Text(
                        lang.nativeName,
                        style: TextStyle(
                          color: isSelected ? AppColors.primary : colors.textPrimary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        lang.name,
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: AppColors.primary)
                          : null,
                      onTap: () {
                        DI.languageService.setLanguage(lang.code);
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showThemeSelector(BuildContext context) {
    final colors = AppColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StreamBuilder<ThemeMode>(
        stream: DI.themeService.themeStream,
        initialData: DI.themeService.currentThemeMode,
        builder: (context, themeSnap) {
          final currentMode = DI.themeService.currentAppThemeMode;
          return Container(
            decoration: BoxDecoration(
              color: colors.bg1,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: colors.cardBorder, width: 1.5),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textMuted.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    DI.languageService.translate('tile_theme'),
                    style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.wb_sunny_outlined, color: AppColors.warning),
                    title: Text(
                      DI.languageService.translate('theme_light'),
                      style: TextStyle(
                        color: currentMode == AppThemeMode.light ? AppColors.primary : colors.textPrimary,
                        fontWeight: currentMode == AppThemeMode.light ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text('Clean light mode', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                    trailing: currentMode == AppThemeMode.light ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                    onTap: () {
                      DI.themeService.setThemeMode(AppThemeMode.light);
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.dark_mode_outlined, color: AppColors.secondary),
                    title: Text(
                      DI.languageService.translate('theme_dark'),
                      style: TextStyle(
                        color: currentMode == AppThemeMode.dark ? AppColors.primary : colors.textPrimary,
                        fontWeight: currentMode == AppThemeMode.dark ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text('Default dark mode', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                    trailing: currentMode == AppThemeMode.dark ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                    onTap: () {
                      DI.themeService.setThemeMode(AppThemeMode.dark);
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.brightness_auto_outlined, color: AppColors.primary),
                    title: Text(
                      DI.languageService.translate('theme_system'),
                      style: TextStyle(
                        color: currentMode == AppThemeMode.system ? AppColors.primary : colors.textPrimary,
                        fontWeight: currentMode == AppThemeMode.system ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text('Match system settings', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                    trailing: currentMode == AppThemeMode.system ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                    onTap: () {
                      DI.themeService.setThemeMode(AppThemeMode.system);
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDataSourcesModal(BuildContext context) {
    final colors = AppColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: colors.cardBorder, width: 1.5),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.storage_outlined, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DI.languageService.translate('data_sources_title'),
                            style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                          ),
                          Text(
                            DI.languageService.translate('data_sources_sub'),
                            style: AppTypography.bodySmall.copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: colors.textMuted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    _buildDataSourceCard(
                      context,
                      name: 'NASA GIBS',
                      tag: 'Satellite WMTS Tiles',
                      icon: Icons.satellite_alt,
                      accentColor: AppColors.secondary,
                      description: DI.languageService.translate('ds_nasa_gibs_desc'),
                      howWeGetIt: DI.languageService.translate('ds_nasa_gibs_how'),
                      endpoint: 'gibs.earthdata.nasa.gov/wmts/epsg4326/best',
                    ),
                    const SizedBox(height: 14),
                    _buildDataSourceCard(
                      context,
                      name: 'NOAA NCEI & Tides',
                      tag: 'REST API v2',
                      icon: Icons.water,
                      accentColor: AppColors.glacier,
                      description: DI.languageService.translate('ds_noaa_desc'),
                      howWeGetIt: DI.languageService.translate('ds_noaa_how'),
                      endpoint: 'ncei.noaa.gov/cdo-web/api/v2',
                    ),
                    const SizedBox(height: 14),
                    _buildDataSourceCard(
                      context,
                      name: 'IPCC AR6',
                      tag: 'CMIP6 Multi-Model',
                      icon: Icons.public,
                      accentColor: AppColors.primary,
                      description: DI.languageService.translate('ds_ipcc_desc'),
                      howWeGetIt: DI.languageService.translate('ds_ipcc_how'),
                      endpoint: 'ipcc.ch / CMIP6 Climate Scenarios',
                    ),
                    const SizedBox(height: 14),
                    _buildDataSourceCard(
                      context,
                      name: 'OpenAQ Platform',
                      tag: 'Live Air Quality API',
                      icon: Icons.air,
                      accentColor: AppColors.heat,
                      description: DI.languageService.translate('ds_openaq_desc'),
                      howWeGetIt: DI.languageService.translate('ds_openaq_how'),
                      endpoint: 'api.openaq.org/v2/measurements',
                    ),
                    const SizedBox(height: 14),
                    _buildDataSourceCard(
                      context,
                      name: 'Global Forest Watch / NASA FIRMS',
                      tag: 'Active Fire & Deforestation',
                      icon: Icons.forest,
                      accentColor: AppColors.forest,
                      description: DI.languageService.translate('ds_gfw_desc'),
                      howWeGetIt: DI.languageService.translate('ds_gfw_how'),
                      endpoint: 'firms.modaps.eosdis.nasa.gov / GFW API',
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataSourceCard(
    BuildContext context, {
    required String name,
    required String tag,
    required IconData icon,
    required Color accentColor,
    required String description,
    required String howWeGetIt,
    required String endpoint,
  }) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: AppTypography.heading3.copyWith(fontSize: 16, color: colors.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            DI.languageService.translate('ds_data_provided').toUpperCase(),
            style: AppTypography.label.copyWith(fontSize: 10, color: colors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: AppTypography.bodySmall.copyWith(color: colors.textPrimary, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text(
            DI.languageService.translate('ds_how_we_get_it').toUpperCase(),
            style: AppTypography.label.copyWith(fontSize: 10, color: AppColors.primary),
          ),
          const SizedBox(height: 4),
          Text(
            howWeGetIt,
            style: AppTypography.bodySmall.copyWith(color: colors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.bg3,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link, size: 14, color: colors.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    endpoint,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    final colors = AppColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: colors.cardBorder, width: 1.5)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.public,
                    size: 38,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Climate Change Storyteller',
                  style: AppTypography.heading2.copyWith(fontSize: 22, color: colors.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  DI.languageService.translate('tile_about_sub'),
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.bg2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DI.languageService.translate('sec_about').toUpperCase(),
                        style: AppTypography.label.copyWith(
                          fontSize: 10,
                          color: colors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        DI.languageService.translate('about_description'),
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(color: colors.cardBorder, height: 1),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        DI.languageService.translate('about_org'),
                        'Liquid Galaxy Project',
                        colors,
                      ),
                      const SizedBox(height: 10),
                      _buildDetailRow(
                        DI.languageService.translate('about_prog'),
                        'Google Summer of Code 2026',
                        colors,
                      ),
                      const SizedBox(height: 10),
                      _buildDetailRow(
                        DI.languageService.translate('about_sys'),
                        'Liquid Galaxy (5-Screen Rig)',
                        colors,
                      ),
                      const SizedBox(height: 10),
                      _buildDetailRow(
                        DI.languageService.translate('about_tech'),
                        'Flutter, Gemini AI, SSH Client',
                        colors,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(DI.languageService.translate('btn_close')),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, AppColorScheme colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppLanguage>(
      stream: DI.languageService.languageStream,
      initialData: DI.languageService.currentLanguage,
      builder: (context, langSnap) {
        final currentLang = langSnap.data!;
        final colors = AppColors.of(context);
        return Scaffold(
          backgroundColor: colors.bg0,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    DI.languageService.translate('settings_title'),
                    style: AppTypography.heading1,
                  ),
                  const SizedBox(height: 24),

                  // LG connection
                  StreamBuilder<LGRigState>(
                    stream: DI.lgService.stateStream,
                    initialData: DI.lgService.state,
                    builder: (context, snap) {
                      final rig = snap.data!;
                      return Column(children: [
                        LGStatusCard(rigState: rig,
                            onTap: () => _openConnect(context)),
                        const SizedBox(height: 8),
                        if (rig.isConnected)
                          OutlinedButton.icon(
                            onPressed: () async {
                              await DI.lgService.disconnect();
                            },
                            icon: const Icon(Icons.link_off,
                                size: 18, color: AppColors.critical),
                            label: Text(DI.languageService.translate('btn_disconnect')),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.critical,
                              side: const BorderSide(
                                  color: AppColors.critical, width: 1),
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: () => _openConnect(context),
                            icon: const Icon(Icons.cable,
                                size: 18, color: AppColors.bg0),
                            label: Text(DI.languageService.translate('btn_connect_lg')),
                          ),
                      ]);
                    },
                  ),
                  const SizedBox(height: 28),

                  SectionHeader(title: DI.languageService.translate('sec_application')),
                  _Tile(
                    icon: Icons.language,
                    title: DI.languageService.translate('tile_language'),
                    subtitle: currentLang.nativeName,
                    onTap: () => _showLanguageSelector(context),
                  ),
                  _Tile(
                    icon: Icons.contrast,
                    title: DI.languageService.translate('tile_theme'),
                    subtitle: switch (DI.themeService.currentAppThemeMode) {
                      AppThemeMode.light => DI.languageService.translate('theme_light'),
                      AppThemeMode.dark => DI.languageService.translate('theme_dark'),
                      AppThemeMode.system => DI.languageService.translate('theme_system'),
                    },
                    onTap: () => _showThemeSelector(context),
                  ),
                  _Tile(
                    icon: Icons.storage_outlined,
                    title: DI.languageService.translate('tile_data_sources'),
                    subtitle: 'NASA GIBS, NOAA, IPCC AR6, OpenAQ',
                    onTap: () => _showDataSourcesModal(context),
                  ),

                  // KML Cache
                  _Tile(
                    icon: Icons.folder_outlined,
                    title: DI.languageService.translate('tile_kml_cache'),
                    subtitle: DI.languageService.translate('tile_kml_cache_sub'),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const KmlCacheScreen())),
                  ),
                  // Diagnostics
                  _Tile(
                    icon: Icons.build_circle_outlined,
                    title: DI.languageService.translate('tile_lg_diagnostics'),
                    subtitle: DI.languageService.translate('tile_lg_diagnostics_sub'),
                    onTap: () => _runDiagnostics(context),
                  ),
                  // Set up NetworkLink (manual re-run, kept as a fallback —
                  // this now also runs automatically right after connecting)
                  _Tile(
                    icon: Icons.sync,
                    title: 'Set up NetworkLink on LG',
                    subtitle: 'Fix Google Earth connection / sync configuration',
                    onTap: () => _setupNetworkLink(context),
                  ),
                  const SizedBox(height: 20),

                  SectionHeader(title: DI.languageService.translate('sec_api_keys')),
                  _Tile(
                    icon: Icons.vpn_key_outlined,
                    title: DI.languageService.translate('tile_api_setup'),
                    subtitle: DI.languageService.translate('tile_api_setup_sub'),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const ApiSetupScreen())),
                  ),
                  const SizedBox(height: 20),

                  SectionHeader(title: DI.languageService.translate('sec_about')),
                  _Tile(
                    icon: Icons.info_outline,
                    title: 'Climate Change Storyteller',
                    subtitle: DI.languageService.translate('tile_about_sub'),
                    onTap: () => _showAboutDialog(context),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  const _Tile({required this.icon, required this.title,
      required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.cardBorder),
        ),
        child: Row(children: [
          Icon(icon, color: colors.textSecondary, size: 22),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.bodyLarge.copyWith(color: colors.textPrimary)),
              Text(subtitle, style: AppTypography.bodySmall.copyWith(color: colors.textSecondary)),
            ],
          )),
          Icon(Icons.chevron_right,
              color: colors.textMuted, size: 20),
        ]),
      ),
    );
  }
}

class LGConnectScreen extends StatefulWidget {
  const LGConnectScreen({super.key});
  @override
  State<LGConnectScreen> createState() => _LGConnectScreenState();
}

class _LGConnectScreenState extends State<LGConnectScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _ipCtrl   = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController(text: 'lg');
  final _passCtrl = TextEditingController(text: 'lg');
  final _screenCtrl= TextEditingController(text: '3');
  final _webPortCtrl = TextEditingController(text: '81');
  bool _obscurePass  = true;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final creds = await SecureStorageService.instance.getLgCredentials();
    if (creds['ip'] != null) _ipCtrl.text = creds['ip']!;
    if (creds['port'] != null) _portCtrl.text = creds['port']!;
    if (creds['username'] != null) _userCtrl.text = creds['username']!;
    if (creds['password'] != null) _passCtrl.text = creds['password']!;
    if (creds['screen'] != null) _screenCtrl.text = creds['screen']!;
    if (creds['webPort'] != null) {
      _webPortCtrl.text = creds['webPort']!;
    } else {
      _webPortCtrl.text = '81';
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    _ipCtrl.dispose(); _portCtrl.dispose();
    _userCtrl.dispose(); _passCtrl.dispose();
    _screenCtrl.dispose(); _webPortCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ip   = _ipCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    final user = _userCtrl.text.trim().isEmpty ? 'lg' : _userCtrl.text.trim();
    final pass = _passCtrl.text.isEmpty ? 'lg' : _passCtrl.text;
    final screens = int.tryParse(_screenCtrl.text.trim()) ?? 5;
    final webPort = int.tryParse(_webPortCtrl.text.trim());

    if (ip.isEmpty) { _showError('Please enter an IP address'); return; }

    setState(() => _isConnecting = true);
    try {
      final ok = await DI.lgService.connect(
        ipAddress: ip,
        port: port,
        username: user,
        password: pass,
        screenCount: screens,
        webPort: webPort,
      );
      if (!mounted) return;

      if (ok) {
        final screens = DI.lgService.state.screenCount;
        final latency = DI.lgService.state.latencyMs;
        final wPort = DI.lgService.state.webPort;

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Connected! $screens screens · Web Port: $wPort · ${latency}ms'),
          ]),
          backgroundColor: AppColors.good,
        ));
        Navigator.pop(context);
      } else {
        _showError('Connection refused — check IP, port and credentials');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _onQrScanned(String raw) {
    String ip = raw.trim();
    int port = 22;
    if (ip.startsWith('lg://')) ip = ip.replaceFirst('lg://', '');
    if (ip.contains(':')) {
      final parts = ip.split(':');
      ip = parts[0]; port = int.tryParse(parts[1]) ?? 22;
    }
    final ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
    if (!ipPattern.hasMatch(ip)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Invalid IP in QR: $raw'),
        backgroundColor: AppColors.critical));
      return;
    }
    _ipCtrl.text = ip; _portCtrl.text = port.toString();
    _tabs.animateTo(0);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Scanned: $ip:$port'),
      backgroundColor: AppColors.primary.withValues(alpha: 0.9)));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.critical));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg0,
      appBar: AppBar(
        title: const Text('Connect to LG Rig'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: colors.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.edit_outlined), text: 'Manual'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'QR Scan'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _ManualTab(ipCtrl: _ipCtrl, portCtrl: _portCtrl, webPortCtrl: _webPortCtrl,
          userCtrl: _userCtrl, passCtrl: _passCtrl, screenCtrl: _screenCtrl,
          obscurePass: _obscurePass, isConnecting: _isConnecting,
          onTogglePass: () => setState(() => _obscurePass = !_obscurePass),
          onConnect: _connect),
        _QrTab(onScanned: _onQrScanned),
      ]),
    );
  }
}

class _ManualTab extends StatelessWidget {
  final TextEditingController ipCtrl, portCtrl, webPortCtrl, userCtrl, passCtrl, screenCtrl;
  final bool obscurePass, isConnecting;
  final VoidCallback onTogglePass, onConnect;

  const _ManualTab({required this.ipCtrl, required this.portCtrl, required this.webPortCtrl,
      required this.userCtrl, required this.passCtrl, required this.screenCtrl,
      required this.obscurePass, required this.isConnecting,
      required this.onTogglePass, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<LGRigState>(
            stream: DI.lgService.stateStream,
            initialData: DI.lgService.state,
            builder: (_, s) => LGStatusCard(rigState: s.data!)),
          const SizedBox(height: 24),
          const SectionHeader(title: 'LG Rig Address'),
          Row(children: [
            Expanded(flex: 3, child: TextField(controller: ipCtrl,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'IP Address', hintText: '192.168.x.x'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: portCtrl,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(labelText: 'SSH Port'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: screenCtrl,
              style: TextStyle(color: colors.textPrimary),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Screens'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: webPortCtrl,
              style: TextStyle(color: colors.textPrimary),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Web Server Port (80/81)',
                hintText: '81 (auto-detect if 0 or empty)'))),
          ]),
          const SizedBox(height: 16),
          const SectionHeader(title: 'SSH Credentials'),
          TextField(controller: userCtrl,
            style: TextStyle(color: colors.textPrimary),
            decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 12),
          TextField(controller: passCtrl, obscureText: obscurePass,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(obscurePass ? Icons.visibility_off
                    : Icons.visibility, size: 18, color: colors.textMuted),
                onPressed: onTogglePass))),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: isConnecting ? null : onConnect,
            icon: isConnecting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.link, size: 18, color: Colors.white),
            label: Text(isConnecting ? 'Connecting…' : 'Connect to LG Rig')),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _QrTab extends StatefulWidget {
  final ValueChanged<String> onScanned;
  const _QrTab({required this.onScanned});
  @override
  State<_QrTab> createState() => _QrTabState();
}

class _QrTabState extends State<_QrTab> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanning = false, _hasScanned = false;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _startScanning() {
    setState(() { _scanning = true; _hasScanned = false; });
    _controller.start();
  }

  void _stopScanning() {
    setState(() => _scanning = false);
    _controller.stop();
  }

  void _handleDetection(BarcodeCapture capture) {
    if (_hasScanned) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _hasScanned = true;
    _stopScanning();
    widget.onScanned(raw);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 280,
            decoration: BoxDecoration(
              color: colors.bg2,
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.5), width: 2),
              borderRadius: BorderRadius.circular(20)),
            child: _scanning
                ? MobileScanner(controller: _controller,
                    onDetect: _handleDetection)
                : Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_2, size: 80,
                          color: colors.textMuted),
                      const SizedBox(height: 16),
                      Text('Tap Start Scan to open camera',
                          style: TextStyle(fontSize: 13,
                              color: colors.textSecondary)),
                    ])),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _scanning ? _stopScanning : _startScanning,
          icon: Icon(_scanning ? Icons.stop : Icons.qr_code_scanner,
              size: 18, color: Colors.white),
          label: Text(_scanning ? 'Stop Scanning' : 'Start Scan'),
          style: _scanning
              ? ElevatedButton.styleFrom(backgroundColor: AppColors.critical)
              : null),
        const SizedBox(height: 32),
      ]),
    );
  }
}