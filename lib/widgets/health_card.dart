import 'package:flutter/material.dart';
import '../theme/bella_theme.dart';

class HealthCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final Color color;
  final Color? iconColor;
  final VoidCallback? onTap;
  final bool showActionButton;
  final IconData? actionIcon;

  const HealthCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    required this.color,
    this.iconColor,
    this.onTap,
    this.showActionButton = false,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: BellaColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BellaColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: effectiveIconColor, size: 22),
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: BellaColors.textPrimary,
                  ),
                ),
                if (unit.isNotEmpty)
                  Text(
                    unit,
                    style: const TextStyle(
                        fontSize: 12, color: BellaColors.textMuted),
                  ),
                const SizedBox(height: 6),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: BellaColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (showActionButton && actionIcon != null)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: onTap,
                    padding: EdgeInsets.zero,
                    icon: Icon(actionIcon, size: 14, color: effectiveIconColor),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
