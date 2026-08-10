import 'package:flutter/material.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/features/explore/climate_era.dart';
import 'package:climate_storyteller/features/lg_connection/lg_rig_state.dart';

// ─────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title.toUpperCase(), style: AppTypography.label.copyWith(color: colors.textSecondary)),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Status Pill
// ─────────────────────────────────────────────

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const StatusPill({super.key, required this.label, required this.color});

  factory StatusPill.critical() =>
      const StatusPill(label: 'Critical', color: AppColors.critical);

  factory StatusPill.active() =>
      const StatusPill(label: 'Active', color: AppColors.primary);

  factory StatusPill.loaded() =>
      const StatusPill(label: 'Loaded', color: AppColors.good);

  factory StatusPill.ready() =>
      const StatusPill(label: 'Ready', color: AppColors.ready);

  factory StatusPill.loading() =>
      const StatusPill(label: 'Loading', color: AppColors.loading);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// LG Connection Status Card
// ─────────────────────────────────────────────

class LGStatusCard extends StatelessWidget {
  final LGRigState rigState;
  final VoidCallback? onTap;

  const LGStatusCard({super.key, required this.rigState, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isConnected = rigState.isConnected;
    final dotColor = switch (rigState.status) {
      LGConnectionStatus.connected => AppColors.good,
      LGConnectionStatus.connecting => AppColors.warning,
      LGConnectionStatus.error => AppColors.critical,
      LGConnectionStatus.disconnected => colors.textMuted,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isConnected
                ? AppColors.primary.withValues(alpha: 0.3)
                : colors.cardBorder,
          ),
        ),
        child: Row(
          children: [
            _PulsingDot(color: dotColor, active: isConnected),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConnected ? 'LG Rig · Connected (port: ${rigState.webPort})' : 'LG Rig · Disconnected',
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isConnected && rigState.currentKml != null)
                    Text(
                      rigState.currentKml!,
                      style: AppTypography.caption.copyWith(
                        color: colors.textMuted,
                        letterSpacing: 0,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isConnected) ...[
              if (rigState.latencyMs != null) ...[
                Text(
                  '${rigState.latencyMs}ms',
                  style: AppTypography.caption.copyWith(color: AppColors.good),
                ),
                const SizedBox(width: 8),
              ],
              const _ClearKmlIconButton(),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClearKmlIconButton extends StatefulWidget {
  const _ClearKmlIconButton();

  @override
  State<_ClearKmlIconButton> createState() => _ClearKmlIconButtonState();
}

class _ClearKmlIconButtonState extends State<_ClearKmlIconButton> {
  bool _clearing = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Remove all KMLs from LG',
      child: InkWell(
        onTap: _clearing ? null : _clearKmls,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.critical.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.critical.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_clearing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.critical,
                  ),
                )
              else
                const Icon(Icons.delete_sweep, color: AppColors.critical, size: 16),
              const SizedBox(width: 4),
              const Text(
                'Clear KML',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.critical,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearKmls() async {
    setState(() => _clearing = true);
    try {
      await DI.lgService.clearKml();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('All KMLs removed from Liquid Galaxy in one go!'),
          ]),
          backgroundColor: AppColors.good,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to remove KMLs: $e'),
          backgroundColor: AppColors.critical,
        ));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  final bool active;
  const _PulsingDot({required this.color, required this.active});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.active) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.active && oldWidget.active) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: widget.active
              ? [BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Era Chip (1900 / 2026 / 2100)
// ─────────────────────────────────────────────

class EraChip extends StatelessWidget {
  final ClimateEra era;
  final bool isSelected;
  final VoidCallback onTap;

  const EraChip({
    super.key,
    required this.era,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : colors.bg3,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : colors.cardBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          era.label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            color: isSelected ? AppColors.primary : colors.textSecondary,
            letterSpacing: isSelected ? -0.2 : 0,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Category Filter Pills (All / Glaciers / Sea Level / Forests)
// ─────────────────────────────────────────────

class CategoryFilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  static const _categories = ['All', 'Glaciers', 'Sea Level', 'Forests', 'Heat'];

  const CategoryFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final active = cat == selected;
          return GestureDetector(
            onTap: () => onChanged(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.primary.withValues(alpha: 0.15) : colors.bg3,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? AppColors.primary : colors.cardBorder,
                ),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.primary : colors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Primary CTA Button
// ─────────────────────────────────────────────

class CTAButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isSecondary;

  const CTAButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isSecondary) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon, size: 18, color: AppColors.primary) : const SizedBox.shrink(),
        label: Text(label, style: const TextStyle(color: AppColors.primary)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: icon != null
          ? Icon(icon, size: 18, color: Colors.white)
          : const SizedBox.shrink(),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Stat Card
// ─────────────────────────────────────────────

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? valueColor;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption.copyWith(color: colors.textMuted)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: AppTypography.dataValue.copyWith(
                  fontSize: 22,
                  color: valueColor ?? colors.textPrimary,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(unit!, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}