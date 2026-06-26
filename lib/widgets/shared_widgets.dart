import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/app_models.dart';

// ─────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title.toUpperCase(), style: AppTypography.label),
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
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
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
    final isConnected = rigState.isConnected;
    final dotColor = switch (rigState.status) {
      LGConnectionStatus.connected => AppColors.good,
      LGConnectionStatus.connecting => AppColors.warning,
      LGConnectionStatus.error => AppColors.critical,
      LGConnectionStatus.disconnected => AppColors.textMuted,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isConnected
                ? AppColors.primary.withOpacity(0.3)
                : const Color(0xFF1E2235),
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
                    isConnected ? 'LG Rig · Connected' : 'LG Rig · Disconnected',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isConnected && rigState.currentKml != null)
                    Text(
                      rigState.currentKml!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                        letterSpacing: 0,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isConnected && rigState.latencyMs != null)
              Text(
                '${rigState.latencyMs}ms',
                style: AppTypography.caption.copyWith(color: AppColors.good),
              ),
          ],
        ),
      ),
    );
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
              ? [BoxShadow(color: widget.color.withOpacity(0.6), blurRadius: 6)]
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.15) : AppColors.bg3,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xFF252840),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          era.label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
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
                color: active ? AppColors.primary.withOpacity(0.15) : AppColors.bg3,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? AppColors.primary : const Color(0xFF252840),
                ),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.primary : AppColors.textSecondary,
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
        icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
        label: Text(label),
      );
    }
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: icon != null
          ? Icon(icon, size: 18, color: AppColors.bg0)
          : const SizedBox.shrink(),
      label: Text(label),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: AppTypography.dataValue.copyWith(
                  fontSize: 22,
                  color: valueColor ?? AppColors.textPrimary,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(unit!, style: AppTypography.caption),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}