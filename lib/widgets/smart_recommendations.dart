// widgets/smart_recommendations.dart

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SmartRecommendations extends StatelessWidget {
  final int heartRate;
  final int steps;
  final int sleepHours;

  const SmartRecommendations({
    super.key,
    required this.heartRate,
    required this.steps,
    required this.sleepHours,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SageColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: SageColors.moss.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: SageColors.moss),
              const SizedBox(width: 8),
              Text(
                'Smart Recommendations',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: SageColors.moss,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Dynamic recommendations based on passed data
          if (steps < 3000)
            _buildRecommendationItem(
              'Movement Break',
              'You\'ve been sedentary for a while. Take a walk!',
              Icons.directions_walk,
              const Color(0xFF4CAF50),
            ),

          if (heartRate > 100)
            _buildRecommendationItem(
              'Relaxation Time',
              'Your heart rate is high. Try a breathing exercise.',
              Icons.favorite,
              const Color(0xFFE91E63),
            ),

          // Default items if no alerts
          if (steps >= 3000 && heartRate <= 100)
            _buildRecommendationItem(
              'Hydration Reminder',
              'Your activity level suggests increased fluid intake',
              Icons.water_drop,
              const Color(0xFF2196F3),
            ),

          const SizedBox(height: 12),
          _buildRecommendationItem(
            'Evening Wind-down',
            'Consider a 5-min breathing session before bed',
            Icons.nightlight_round,
            const Color(0xFF9C27B0),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationItem(
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: SageColors.inkSoft, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey[400]),
        ],
      ),
    );
  }
}