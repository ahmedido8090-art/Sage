// widgets/wellness_activity_tile.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Activity card used in the dashboard's horizontal-scrolling
/// "Wellness practices" row (Breathwork, Meditation, Walking, Sleep sounds).
/// Replaces the old static 2x2 GridView tile pattern.
class WellnessActivityTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const WellnessActivityTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 124,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // reduced vertical padding
        decoration: BoxDecoration(
          color: SageColors.card,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
          border: Border(top: BorderSide(color: accent, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(height: 12), // reduced from 22
            Text(
              title,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis, // prevent horizontal overflow
              maxLines: 1,
            ),
            const SizedBox(height: 0), // removed extra gap (was 2)
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: SageColors.inkSoft),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}