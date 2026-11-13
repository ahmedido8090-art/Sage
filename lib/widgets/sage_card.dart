// widgets/sage_card.dart
//
// The shared content surface and section heading. Screens used to carry their
// own private copies of these.
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/soften_caps.dart';

/// A bordered surface with Sage's notched corner.
class SageCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SageCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: SageColors.card,
        borderRadius: SageRadius.card,
        border: Border.all(color: SageColors.line),
      ),
      child: child,
    );
  }
}

/// A section heading in sentence case, exposed to screen readers as a header.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// A quieter label for grouping lists and forms (sentence case, small, in
  /// the secondary color) instead of a full card title.
  final bool dense;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            softenCaps(title),
            style: dense
                ? SageText.label(color: SageColors.inkSoft)
                    .copyWith(fontSize: 13.5)
                : SageText.title(),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: SageSpace.xs),
            Text(subtitle!, style: SageText.caption()),
          ],
        ],
      ),
    );
  }
}
