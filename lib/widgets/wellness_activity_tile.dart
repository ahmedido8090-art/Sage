// widgets/wellness_activity_tile.dart
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'pressable.dart';

/// Card in the dashboard's horizontally scrolling care row (PurePlate,
/// ZZZify, Chronic Care, Daily check-in). The accent is a stripe on top.
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
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title, $subtitle',
      child: ExcludeSemantics(
        child: Container(
          width: 132,
          padding: const EdgeInsets.fromLTRB(
              SageSpace.md + 2, SageSpace.md, SageSpace.md + 2, SageSpace.md),
          decoration: BoxDecoration(
            color: SageColors.card,
            borderRadius: SageRadius.tile,
            border: Border(top: BorderSide(color: accent, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: accent),
              const Spacer(),
              Text(title,
                  style: SageText.label(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: SageText.caption(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
