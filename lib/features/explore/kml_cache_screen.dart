import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';
import 'package:climate_storyteller/features/explore/climate_region.dart';
import 'package:climate_storyteller/features/explore/climate_era.dart';

class KmlCacheScreen extends StatefulWidget {
  const KmlCacheScreen({super.key});
  @override
  State<KmlCacheScreen> createState() => _KmlCacheScreenState();
}

class _KmlCacheScreenState extends State<KmlCacheScreen> {

  final Map<String, _KmlStatus> _statusMap = {};
  bool   _isDownloadingAll = false;
  int    _cacheSize        = 0;
  int    _cachedCount      = 0;

  static const _totalFiles = 18;

  @override
  void initState() {
    super.initState();
    _initStatusMap();
    _checkExistingCache();
  }

  void _initStatusMap() {
    for (final region in kDefaultRegions) {
      for (final era in ClimateEra.values) {
        final key = '${region.id}_${era.label}';
        _statusMap[key] = _KmlStatus.notDownloaded;
      }
    }
  }

  Future<void> _checkExistingCache() async {
    final dir     = await _cacheDir();
    int   size    = 0;
    int   count   = 0;

    for (final region in kDefaultRegions) {
      for (final era in ClimateEra.values) {
        final key      = '${region.id}_${era.label}';
        final filename = '${region.id}_${era.label}_${region.category}.kml';
        final file     = File('${dir.path}/$filename');

        if (file.existsSync()) {
          size  += file.lengthSync();
          count++;
          if (mounted) setState(() => _statusMap[key] = _KmlStatus.cached);
        }
      }
    }

    if (mounted) setState(() { _cacheSize = size; _cachedCount = count; });
  }

  Future<Directory> _cacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir    = Directory('${appDir.path}/kmls');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<void> _downloadOne(ClimateRegion region, ClimateEra era) async {
    final key = '${region.id}_${era.label}';
    setState(() => _statusMap[key] = _KmlStatus.downloading);

    try {
      await DI.lgService.buildKml(
        region: region, era: era);
      setState(() {
        _statusMap[key] = _KmlStatus.cached;
        _cachedCount++;
      });
      await _checkExistingCache();
    } catch (e) {
      setState(() => _statusMap[key] = _KmlStatus.error);
    }
  }

  Future<void> _downloadAll() async {
    setState(() => _isDownloadingAll = true);

    for (final region in kDefaultRegions) {
      for (final era in ClimateEra.values) {
        final key = '${region.id}_${era.label}';
        if (_statusMap[key] != _KmlStatus.cached) {
          await _downloadOne(region, era);
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    setState(() => _isDownloadingAll = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('All KML files cached — app ready for offline use'),
        backgroundColor: AppColors.good,
      ));
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: const Text('Clear KML Cache',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Delete all $_totalFiles cached KML files?\n'
          'You\'ll need to re-download them for offline use.',
          style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear',
                style: TextStyle(color: AppColors.critical))),
        ],
      ),
    );

    if (confirmed != true) return;

    await DI.lgService.clearCache();
    _initStatusMap();
    setState(() { _cacheSize = 0; _cachedCount = 0; });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cache cleared'),
        backgroundColor: AppColors.bg2,
      ));
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024)       return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _cachedCount / _totalFiles;

    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('KML Cache'),
        backgroundColor: AppColors.bg0,
        actions: [
          if (_cachedCount > 0)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.critical),
              onPressed: _clearCache,
              tooltip: 'Clear cache',
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.bg2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1E2235)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.folder_outlined,
                          color: AppColors.primary, size: 22),
                      const SizedBox(width: 10),
                      const Text('Offline KML Cache',
                        style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                      const Spacer(),
                      Text(_formatBytes(_cacheSize),
                        style: AppTypography.caption),
                    ]),
                    const SizedBox(height: 14),

                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: AppColors.bg3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              progress == 1.0
                                  ? AppColors.good
                                  : AppColors.primary),
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$_cachedCount / $_totalFiles',
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: progress == 1.0
                              ? AppColors.good : AppColors.primary),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      progress == 1.0
                          ? '✅ All files cached — app works offline'
                          : '${_totalFiles - _cachedCount} files remaining',
                      style: AppTypography.bodySmall.copyWith(
                        color: progress == 1.0
                            ? AppColors.good : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: _isDownloadingAll ||
                    _cachedCount == _totalFiles
                    ? null : _downloadAll,
                icon: _isDownloadingAll
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.bg0))
                    : const Icon(Icons.download,
                        size: 18, color: AppColors.bg0),
                label: Text(_isDownloadingAll
                    ? 'Downloading… $_cachedCount/$_totalFiles'
                    : _cachedCount == _totalFiles
                        ? 'All Files Cached ✓'
                        : 'Download All $_totalFiles KML Files'),
              ),
              const SizedBox(height: 24),

              const SectionHeader(title: 'Files'),
              ...kDefaultRegions.map((region) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      region.name.toUpperCase(),
                      style: AppTypography.caption,
                    ),
                  ),

                  ...ClimateEra.values.map((era) {
                    final key    = '${region.id}_${era.label}';
                    final status = _statusMap[key]
                        ?? _KmlStatus.notDownloaded;
                    final filename =
                        '${region.id}_${era.label}_'
                        '${region.category}.kml';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: status == _KmlStatus.cached
                            ? AppColors.good.withValues(alpha: 0.05)
                            : AppColors.bg2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: status == _KmlStatus.cached
                              ? AppColors.good.withValues(alpha: 0.3)
                              : const Color(0xFF1E2235),
                        ),
                      ),
                      child: Row(children: [
                        _statusIcon(status),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(filename,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: AppColors.textPrimary,
                                )),
                              Text(
                                '${era.subtitle} · ${region.category}',
                                style: AppTypography.caption
                                    .copyWith(letterSpacing: 0)),
                            ],
                          ),
                        ),

                        if (status == _KmlStatus.notDownloaded ||
                            status == _KmlStatus.error)
                          GestureDetector(
                            onTap: () => _downloadOne(region, era),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.3)),
                              ),
                              child: const Text('Download',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                )),
                            ),
                          ),
                      ]),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              )),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusIcon(_KmlStatus status) {
    return switch (status) {
      _KmlStatus.cached => const Icon(Icons.check_circle,
          color: AppColors.good, size: 18),
      _KmlStatus.downloading => const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.primary)),
      _KmlStatus.error => const Icon(Icons.error_outline,
          color: AppColors.critical, size: 18),
      _KmlStatus.notDownloaded => const Icon(Icons.download_outlined,
          color: AppColors.textMuted, size: 18),
    };
  }
}

enum _KmlStatus { notDownloaded, downloading, cached, error }
