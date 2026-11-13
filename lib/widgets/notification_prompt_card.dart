// widgets/notification_prompt_card.dart
//
// A one-time invitation on Home to turn on Sage's nudges. Uses the shared
// card and tokens so it matches the app in light and dark.
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'sage_card.dart';

class NotificationPromptCard extends StatelessWidget {
  final VoidCallback onEnable;
  final VoidCallback onDismiss;

  const NotificationPromptCard({
    super.key,
    required this.onEnable,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_outlined,
                  size: 20, color: SageColors.moss),
              const SizedBox(width: SageSpace.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Want a gentle nudge now and then?',
                      style: SageText.title()),
                ),
              ),
            ],
          ),
          const SizedBox(height: SageSpace.sm),
          Text(
            'Sage can remind you to sip water, stretch and wind down. A few '
            'friendly pings a day at most, and you choose what and when.',
            style: SageText.body(color: SageColors.inkSoft),
          ),
          const SizedBox(height: SageSpace.lg),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onEnable,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(kSageMinTapTarget),
                  ),
                  child: const Text('Turn on'),
                ),
              ),
              const SizedBox(width: SageSpace.md),
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  minimumSize: const Size(kSageMinTapTarget, kSageMinTapTarget),
                ),
                child: const Text('Not now'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
