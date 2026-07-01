// widgets/quote_card.dart
import 'package:flutter/material.dart';
import '../models/health_data.dart';
import '../theme/app_theme.dart';

class QuoteCard extends StatelessWidget {
  final Quote quote;
  final VoidCallback onRefresh;

  const QuoteCard({super.key, required this.quote, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SageColors.moss.withValues(alpha: 0.85),
            SageColors.mossLight.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: SageColors.moss.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.spa, color: Colors.white.withValues(alpha: 0.8), size: 32),
          const SizedBox(height: 12),
          Text(
            '"${quote.text}"',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '- ${quote.author}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRefresh,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('New Inspiration'),
          ),
        ],
      ),
    );
  }
}