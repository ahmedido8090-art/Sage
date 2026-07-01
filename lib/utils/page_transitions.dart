// utils/page_transitions.dart
//
// A small set of named route transitions, now driven by SageMotion tokens
// instead of inline magic numbers — slideUpRoute's distance/curve match
// Reveal's small-size tokens exactly, which matters because pushed
// screens (PurePlate, ZZZify, etc.) use slideUpRoute for the route itself
// AND Reveal for their body content; using the same curve/distance for
// both makes the two motions read as one continuous gesture instead of
// "slide, then separately fade."
import 'package:flutter/material.dart';
import '../theme/motion.dart';

/// Slides a new screen up from the bottom — good for modal-feeling destinations
/// (PurePlate, ZZZify, ChronicCare, DailyCheckin, activity screens).
Route<T> slideUpRoute<T>(Widget page,
    {Duration duration = SageMotion.routeSlideUp}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: SageMotion.routeSlideUpReverse,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final slide = Tween<Offset>(
        begin: Offset(0, SageMotion.riseSmall),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: SageMotion.revealCurve));
      final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: animation, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
      );
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

/// Horizontal slide — good for lateral navigation (Login → Signup).
Route<T> slideRightRoute<T>(Widget page, {Duration duration = const Duration(milliseconds: 300)}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final slide = Tween<Offset>(
        begin: const Offset(1.0, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: SageMotion.revealCurve));
      return SlideTransition(position: slide, child: child);
    },
  );
}

/// Simple cross-fade — for lightweight context changes (e.g. dashboard tab
/// body swap, or Login → Dashboard after successful auth).
Route<T> fadeRoute<T>(Widget page, {Duration duration = SageMotion.routeFade}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}