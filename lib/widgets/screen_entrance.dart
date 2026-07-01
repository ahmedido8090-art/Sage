// widgets/screen_entrance.dart
//
// Why this exists: PurePlate, ZZZify, Chronic Care, and Daily Check-in
// are reached via slideUpRoute (a 340ms slide+fade transition), but their
// own body content has zero animation of its own — it just appears the
// instant the route transition finishes. Next to a dashboard and wellness
// hub that animate almost everything, these screens feel like they were
// teleported in rather than opened.
//
// ScreenEntrance is a single, reusable wrapper: drop it around any
// Scaffold's `body:` and the content fades + rises in once, the moment
// the screen is first built. It uses the same one-shot guard pattern as
// MetricTile/WellnessGridCard/etc. (addPostFrameCallback + a _started
// flag) so it never re-fires on a parent setState(), and it's cheap
// enough to wrap a TabBarView, a SingleChildScrollView, or any other
// body without needing per-screen animation code.
//
// Usage:
//   body: ScreenEntrance(child: TabBarView(...)),
//   body: ScreenEntrance(child: SingleChildScrollView(...)),
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class ScreenEntrance extends StatefulWidget {
  final Widget child;

  /// How far the content rises from, as a fraction of its own height.
  /// Kept small and consistent with the rest of the app's entrance
  /// vocabulary (MetricTile uses 0.10, WellnessGridCard uses 0.10).
  final double riseFraction;

  final Duration duration;

  const ScreenEntrance({
    super.key,
    required this.child,
    this.riseFraction = 0.04,
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<ScreenEntrance> createState() => _ScreenEntranceState();
}

class _ScreenEntranceState extends State<ScreenEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(
      begin: Offset(0, widget.riseFraction),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    // One-shot: fires exactly once per State lifetime, regardless of how
    // many times the parent rebuilds before or after.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_started || !mounted) return;
      _started = true;
      _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}