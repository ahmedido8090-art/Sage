// widgets/metric_tile.dart
//
// Rebuilt on the shared Reveal/Pressable primitives instead of its own
// inline AnimationController — this is what makes its entrance/press feel
// identical to every other tile in the app rather than subtly its own
// thing.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'animated_number.dart';
import 'reveal.dart';
import 'pressable.dart';

class MetricTile extends StatelessWidget {
  final Widget icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  /// When true, the tile tries to parse [value] as an integer and
  /// animates the count-up. Set to false for non-integer strings (e.g. "—").
  final bool animateValue;

  const MetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
    this.animateValue = true,
  });

  @override
  Widget build(BuildContext context) {
    final parsedInt = int.tryParse(value);
    final canAnimate = animateValue && parsedInt != null;

    return Reveal(
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: SageColors.card,
            border: Border.all(color: SageColors.line),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
              bottomLeft: Radius.circular(6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTheme(
                data: IconThemeData(size: 18, color: SageColors.moss),
                child: icon,
              ),
              const SizedBox(height: 10),
              canAnimate
                  ? AnimatedNumber(
                      value: parsedInt,
                      style: SageText.mono(size: 19),
                    )
                  : Text(value, style: SageText.mono(size: 19)),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(fontSize: 11.5, color: SageColors.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
