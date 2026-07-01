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
import 'package:flutter/material.dart';
import '../theme/motion.dart';

class Pressable extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;

  const Pressable({super.key, required this.onTap, required this.child});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? SageMotion.pressScale : 1.0,
        duration: SageMotion.pressDuration,
        curve: SageMotion.pressCurve,
        child: widget.child,
      ),
    );
  }
}