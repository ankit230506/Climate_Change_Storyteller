import 'dart:async';
import 'package:flutter/material.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/features/climate_data/climate_alert.dart';
import 'package:climate_storyteller/features/climate_data/climate_alert_service.dart';

/// Horizontal scrolling banner showing real-time climate alerts.
/// Fires [onAlertTap] when the user taps an alert card.
class ClimateAlertBanner extends StatefulWidget {
  final void Function(ClimateAlert alert)? onAlertTap;

  const ClimateAlertBanner({super.key, this.onAlertTap});

  @override
  State<ClimateAlertBanner> createState() => _ClimateAlertBannerState();
}

class _ClimateAlertBannerState extends State<ClimateAlertBanner> {
  List<ClimateAlert> _alerts = [];
  bool _isLoading = true;
  StreamSubscription<List<ClimateAlert>>? _sub;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _sub = ClimateAlertService.instance.alertsStream.listen((alerts) {
      if (mounted) setState(() => _alerts = alerts);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    try {
      final alerts = await ClimateAlertService.instance.fetchAlerts();
      if (mounted) {
        setState(() {
          _alerts = alerts;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.cardBorder),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: colors.textMuted),
                ),
                const SizedBox(width: 10),
                Text(
                  DI.languageService.translate('loading_alerts'),
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.critical,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                DI.languageService.translate('live_climate_alerts'),
                style: AppTypography.label.copyWith(color: AppColors.critical),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  setState(() => _isLoading = true);
                  await ClimateAlertService.instance
                      .fetchAlerts(forceRefresh: true);
                  if (mounted) setState(() => _isLoading = false);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, color: colors.textMuted, size: 14),
                    const SizedBox(width: 4),
                    Text(DI.languageService.translate('btn_refresh'),
                        style: TextStyle(
                            color: colors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 98,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _alerts.length,
            itemBuilder: (context, index) {
              final alert = _alerts[index];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _AlertCard(
                  alert: alert,
                  onTap: () => widget.onAlertTap?.call(alert),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final ClimateAlert alert;
  final VoidCallback? onTap;

  const _AlertCard({required this.alert, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final severityColor = _severityColor(alert.severity);
    final typeEmoji = alert.type.emoji;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: severityColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: severityColor.withValues(alpha: 0.3),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(typeEmoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    alert.severity.label.toUpperCase(),
                    style: TextStyle(
                      color: severityColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.open_in_new, color: colors.textMuted, size: 12),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                alert.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (alert.source != null) ...[
                  Icon(Icons.satellite_alt,
                      color: colors.textMuted, size: 10),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      alert.source!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textMuted, fontSize: 9),
                    ),
                  ),
                ] else
                  const Spacer(),
                Text(
                  _timeAgo(alert.timestamp),
                  style: TextStyle(color: colors.textMuted, fontSize: 9),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _severityColor(AlertSeverity severity) => switch (severity) {
        AlertSeverity.extreme => AppColors.critical,
        AlertSeverity.high => AppColors.warning,
        AlertSeverity.moderate => AppColors.ready,
        AlertSeverity.low => AppColors.good,
      };

  String _timeAgo(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
