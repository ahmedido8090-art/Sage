// widgets/quote_section.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Editorial quote treatment — a hairline rule and italic Fraunces serif,
/// replacing the green gradient quote box (which repeated almost
/// verbatim between the dashboard and wellness hub).
class QuoteSection extends StatelessWidget {
  final String text;
  final String author;
  final VoidCallback onRefresh;

  const QuoteSection({
    super.key,
    required this.text,
    required this.author,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRefresh,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(top: 18),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: SageColors.line)),
        ),
        child: Column(
          children: [
            Text('"$text"',
                textAlign: TextAlign.center, style: SageText.quote()),
            const SizedBox(height: 10),
            Text(
              author.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.6,
                color: SageColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
