// widgets/reveal.dart
//
// The one and only entrance animation in Sage: fade + rise, fired exactly
// once per State lifetime. This replaces every other entrance
// implementation in the app — the inline _enterCtrl/_enterOpacity/
// _enterSlide block duplicated across MetricTile, WellnessGridCard,
// WellnessActivityTile, SageHeroCard, _ProgressMiniCard, _PracticeCard,
// and the separate ScreenEntrance widget. All of those had slightly
// different durations, distances, and curves, plus three different
// "only fire once" guard implementations. There is now exactly one.
//
// Two sizes only — pass [size] to pick which. Don't introduce a third
// size or hand-roll a custom duration; if neither size fits, that's a
// signal to reconsider the design rather than add a one-off number.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/motion.dart';

enum RevealSize { small, large }

class Reveal extends StatefulWidget {
  final Widget child;
  final RevealSize size;

  /// Extra delay before this Reveal starts, on top of its own one-shot
  /// guard. Used by [Stagger] to offset list items; most call sites
  /// should leave this at zero.
  final Duration delay;

  const Reveal({
    super.key,
    required this.child,
    this.size = RevealSize.small,
    this.delay = Duration.zero,
  });

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  // Fires exactly once per State lifetime, no matter how many times the
  // parent rebuilds before or after. This is the single guard pattern —
  // every previous version of this idea (MetricTile, WellnessGridCard,
  // ScreenEntrance, etc.) reimplemented this slightly differently.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final duration = widget.size == RevealSize.large
        ? SageMotion.revealLarge
        : SageMotion.revealSmall;
    final rise = widget.size == RevealSize.large
        ? SageMotion.riseLarge
        : SageMotion.riseSmall;

    _ctrl = AnimationController(vsync: this, duration: duration);
    _opacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: SageMotion.revealCurve));
    _slide = Tween<Offset>(
      begin: Offset(0, rise),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: SageMotion.revealCurve));

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_started || !mounted) return;
      _started = true;
      if (widget.delay == Duration.zero) {
        _ctrl.forward();
      } else {
        Future.delayed(widget.delay, () {
          if (mounted) _ctrl.forward();
        });
      }
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