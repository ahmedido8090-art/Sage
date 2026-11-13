// widgets/pressable.dart
//
// The one and only tap-feedback animation in Sage: a subtle scale-down
// while pressed. This replaces the inline GestureDetector + bool _pressed
// + AnimatedScale block that was copy-pasted (with slightly different
// numbers each time — 0.94, 0.95, 0.96 scale; 120ms, 130ms duration)
// across MetricTile, WellnessGridCard, WellnessActivityTile,
// _ProgressMiniCard, and _PracticeCard.
//
// Any tappable card/tile in the app should be built as:
//   Pressable(onTap: ..., child: <the card's visual content>)
// and nothing else needs to manage press state.
import 'package:material_ui/material_ui.dart';
import '../theme/motion.dart';

class Pressable extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;

  /// Spoken label for screen readers. Defaults to the visible text of [child].
  final String? semanticLabel;

  const Pressable({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: _buildGesture(),
    );
  }

  Widget _buildGesture() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp:
          widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel:
          widget.onTap == null ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed && !MediaQuery.disableAnimationsOf(context)
            ? SageMotion.pressScale
            : 1.0,
        duration: SageMotion.pressDuration,
        curve: SageMotion.pressCurve,
        child: widget.child,
      ),
    );
  }
}
