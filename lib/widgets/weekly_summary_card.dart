// widgets/weekly_summary_card.dart
//
// "Your week" at the top of Insights: a warm headline and three numbers that
// count up gently, with a plain comparison to last week.
import 'package:material_ui/material_ui.dart';
import '../services/weekly_summary.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'animated_number.dart';
import 'sage_card.dart';
import 'sage_illustration.dart';
import 'sage_states.dart';
import 'state_copy.dart';

class WeeklySummaryCard extends StatelessWidget {
  final WeeklySummary summary;

  const WeeklySummaryCard({super.key, required this.summary});

  String? _deltaText() {
    if (summary.lastWeek.minutes == 0 && summary.thisWeek.minutes == 0) {
      return null;
    }
    final d = summary.minutesDelta;
    if (d == 0) return 'Same as last week';
    return d > 0
        ? '$d min more than last week'
        : '${-d} min less than last week';
  }

  @override
  Widget build(BuildContext context) {
    if (!summary.hasAnyData) {
      return SageCard(
        child: EmptyState.topic(
          StateTopic.insights,
          art: SageArt.chart,
          compact: true,
        ),
      );
    }
    final t = summary.thisWeek;
    final delta = _deltaText();
    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Your week'),
          const SizedBox(height: SageSpace.sm),
          Text(summary.headline,
              style: SageText.body(color: SageColors.inkSoft)),
          const SizedBox(height: SageSpace.lg),
          // Wraps onto a second line rather than squeezing when the screen is
          // narrow or the text is large.
          Wrap(
            spacing: SageSpace.xl,
            runSpacing: SageSpace.lg,
            children: [
              _stat(context,
                  label: 'Active days', value: t.activeDays, suffix: '/7'),
              _stat(context, label: 'Minutes', value: t.minutes),
              _stat(context, label: 'Check-ins', value: t.checkins),
            ],
          ),
          if (delta != null) ...[
            const SizedBox(height: SageSpace.md),
            Text(delta, style: SageText.caption()),
          ],
        ],
      ),
    );
  }

  Widget _stat(BuildContext context,
      {required String label, required int value, String suffix = ''}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 72),
      child: Semantics(
        label: '$label: $value$suffix',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedNumber(
                  value: value,
                  style: SageText.mono(size: 26, color: SageColors.moss),
                ),
                if (suffix.isNotEmpty) Text(suffix, style: SageText.caption()),
              ],
            ),
            const SizedBox(height: 2),
            Text(label, style: SageText.caption()),
          ],
        ),
      ),
    );
  }
}
