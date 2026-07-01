// widgets/health_card.dart

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HealthCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final Color color; // Background tint color
  final Color? iconColor; // Specific color for the icon (optional)
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
    this.iconColor, // Added parameter
    this.onTap,
    this.showActionButton = false,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    // Use the provided iconColor, or fallback to the main color
    final effectiveIconColor = iconColor ?? color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SageColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
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
                    // Use the main color for the background tint
                    color: color.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: effectiveIconColor, // Use the effective icon color
                    size: 22,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: SageColors.moss,
                  ),
                ),
                Text(
                  unit,
                  style: TextStyle(fontSize: 12, color: SageColors.inkSoft),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: SageColors.inkSoft,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (showActionButton && actionIcon != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(actionIcon, size: 14, color: color),
                    onPressed: onTap,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}