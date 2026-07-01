// widgets/recommendation_banner.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Single, most-relevant recommendation — replaces the old
/// SmartRecommendations widget's stacked list with one focused card.
class RecommendationBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? accent;
  final VoidCallback? onTap;

  const RecommendationBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accent ?? SageColors.clay;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SageColors.card,
          border: Border.all(color: SageColors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: effectiveAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: effectiveAccent),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: SageColors.inkSoft)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: SageColors.inkSoft),
          ],
        ),
      ),
    );
  }
}