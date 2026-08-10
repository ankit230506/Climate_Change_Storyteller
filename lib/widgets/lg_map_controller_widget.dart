import 'package:flutter/material.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';

class LGMapControllerWidget extends StatelessWidget {
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onToggleTilt;
  final bool is3DTilt;

  const LGMapControllerWidget({
    super.key,
    this.onZoomIn,
    this.onZoomOut,
    this.onToggleTilt,
    this.is3DTilt = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.bg1.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zoom In
            _ControllerIconButton(
              icon: Icons.add,
              tooltip: 'Zoom In LG Rig',
              onPressed: onZoomIn,
            ),
            const SizedBox(height: 4),

            // Zoom Out
            _ControllerIconButton(
              icon: Icons.remove,
              tooltip: 'Zoom Out LG Rig',
              onPressed: onZoomOut,
            ),
            const SizedBox(height: 4),

            // Tilt 3D Toggle
            _ControllerIconButton(
              icon: is3DTilt ? Icons.threed_rotation : Icons.map_outlined,
              tooltip: is3DTilt ? 'Switch to 0° Overhead' : 'Switch to 45° 3D Tilt',
              iconColor: is3DTilt ? AppColors.primary : null,
              onPressed: onToggleTilt,
            ),
          ],
        ),
      ),
    );
  }
}

class _ControllerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? iconColor;
  final VoidCallback? onPressed;

  const _ControllerIconButton({
    required this.icon,
    required this.tooltip,
    this.iconColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: iconColor ?? colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
