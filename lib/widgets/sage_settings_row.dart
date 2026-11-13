// widgets/sage_settings_row.dart
//
// One row in a settings card: tinted icon, title, optional subtitle, and a
// trailing control (a switch, a chevron, a value). Shared by Profile and
// Notification settings so they look and behave the same.
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'pressable.dart';

class SageSettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? accent;

  const SageSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? SageColors.moss;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kSageMinTapTarget),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: SageSpace.md + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SageText.label().copyWith(fontSize: 14.5)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: SageText.caption()),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: SageSpace.sm),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Pressable(
      onTap: onTap,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      child: ExcludeSemantics(child: row),
    );
  }
}
