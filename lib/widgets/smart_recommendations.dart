import 'package:flutter/material.dart';
import '../theme/bella_theme.dart';

class SmartRecommendations extends StatelessWidget {
  final int heartRate;
  final int steps;
  final double? bmi;
  final int stepGoal;

  const SmartRecommendations({
    super.key,
    required this.heartRate,
    required this.steps,
    this.bmi,
    this.stepGoal = 6000,
  });

  @override
  Widget build(BuildContext context) {
    final tips = _generateTips();
    return Column(
        children: tips
            .map((tip) =>
                Padding(padding: const EdgeInsets.only(bottom: 12), child: tip))
            .toList());
  }

  List<Widget> _generateTips() {
    final cards = <Widget>[];

    if (steps < 100) {
      cards.add(_buildTipCard(
        'Start Moving',
        'You have been mostly inactive so far. A short walk can reset your energy and momentum.',
        Icons.directions_run,
        BellaColors.warning,
      ));
    } else if (steps < stepGoal / 2) {
      cards.add(_buildTipCard(
        'Keep Going',
        'You are making progress today. Reaching 50% of your goal before evening would be a strong checkpoint.',
        Icons.trending_up,
        BellaColors.secondary,
      ));
    } else {
      cards.add(_buildTipCard(
        'Great Engagement',
        'You are building a healthy rhythm. Keep the streak alive with one more intentional session.',
        Icons.star,
        BellaColors.primary,
      ));
    }

    if (bmi != null && bmi! > 0) {
      if (bmi! < 18.5) {
        cards.add(_buildTipCard(
          'Nutrition Tip',
          'Because your BMI is on the lower side, pair movement with nourishing meals and recovery time.',
          Icons.restaurant,
          BellaColors.success,
        ));
      } else if (bmi! >= 25) {
        cards.add(_buildTipCard(
          'Weight Management',
          'Consistent walking, lower stress, and steady sleep habits can support long-term weight balance.',
          Icons.monitor_weight,
          BellaColors.accent,
        ));
      }
    }

    if (heartRate > 100 && steps < 500) {
      cards.add(_buildTipCard(
        'Stress Detection',
        'Your heart rate is elevated while you are relatively inactive. A breathwork session may help regulate it.',
        Icons.favorite,
        BellaColors.danger,
      ));
    }

    return cards;
  }

  Widget _buildTipCard(
      String title, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BellaColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BellaColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: BellaColors.textPrimary)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 13,
                        color: BellaColors.textSecondary,
                        height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
