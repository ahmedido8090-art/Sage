import 'package:flutter/material.dart';
import '../models/health_data.dart';
import '../theme/bella_theme.dart';

class QuoteCard extends StatelessWidget {
  final Quote quote;
  final VoidCallback onRefresh;

  const QuoteCard({
    super.key,
    required this.quote,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF232742),
            Color(0xFF171926),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: BellaColors.primary.withOpacity(0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: BellaColors.primary.withOpacity(0.15),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome,
            color: BellaColors.primary.withOpacity(0.95),
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            '"${quote.text}"',
            style: const TextStyle(
              color: BellaColors.textPrimary,
              fontSize: 16,
              fontStyle: FontStyle.italic,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '- ${quote.author}',
            style: const TextStyle(
              color: BellaColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onRefresh,
            style: OutlinedButton.styleFrom(
              foregroundColor: BellaColors.textPrimary,
              side: BorderSide(
                color: BellaColors.primary.withOpacity(0.45),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text('New Inspiration'),
          ),
        ],
      ),
    );
  }
}
