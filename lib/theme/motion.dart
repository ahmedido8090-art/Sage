// theme/motion.dart
//
// Sage's animation design system — the single source of truth for every
// duration, curve, and distance used in motion across the app.
//
// WHY THIS EXISTS
// Before this file, every screen invented its own numbers: entrance fades
// ranged from 380–600ms with no logic behind the differences, slide
// distances were 0.04/0.06/0.08/0.10/0.12/0.18 used interchangeably for
// the same visual intent, curves were a mix of easeOut/easeOutCubic
// picked at random, and there were three near-duplicate "guard" patterns
// for making sure an entrance animation only fires once. The result felt
// inconsistent even after individual widgets were fixed, because there
// was no shared vocabulary — every fix was still a one-off.
//
// THE RULE GOING FORWARD
// Nothing in this app should write a raw `Duration(milliseconds: ...)` or
// `Curves.easeXxx` for entrance, press-feedback, or section-transition
// purposes. Use a constant from here. If a new situation doesn't fit an
// existing token, add a token — don't invent a number inline.
import 'package:flutter/material.dart';

class SageMotion {
  SageMotion._();

  // ── Entrance (Reveal / Stagger) ──────────────────────────────────────────
  // Used whenever new content appears: a card mounting, a screen's body
  // loading in, a list item arriving. Exactly two speeds exist —
  // "small" for compact widgets (tiles, chips, rows) and "large" for
  // big surfaces (whole screen bodies, hero cards). Don't add a third.
  static const Duration revealSmall = Duration(milliseconds: 380);
  static const Duration revealLarge = Duration(milliseconds: 480);
  static const Curve revealCurve = Curves.easeOutCubic;

  // Rise distance is expressed as a fraction of the widget's own height,
  // consumed by SlideTransition's fractional offset. One distance for
  // small widgets, one for large surfaces — large surfaces rise less
  // because a big card or screen moving a large % of its own height
  // looks like a glitch, not a polish.
  static const double riseSmall = 0.08;
  static const double riseLarge = 0.04;

  // Stagger: the delay between consecutive items in a list/column.
  // One value used everywhere a group of items enters together.
  static const Duration staggerStep = Duration(milliseconds: 70);

  // ── Press feedback (Pressable) ───────────────────────────────────────────
  // Every tappable card/tile in the app scales down by the same amount,
  // for the same duration. No more 120ms here, 130ms there, 0.94 here,
  // 0.96 there — one feel for "this is tappable" everywhere.
  static const Duration pressDuration = Duration(milliseconds: 120);
  static const Curve pressCurve = Curves.easeOut;
  static const double pressScale = 0.96;

  // ── Value changes (AnimatedSwitcher / count-ups) ─────────────────────────
  // Used when a number or short text cross-fades to a new value (bpm
  // chip, score badge, "Done" pill) — separate from entrance because
  // it's a much quicker, subtler motion.
  static const Duration valueChange = Duration(milliseconds: 250);
  static const Duration numberCountUp = Duration(milliseconds: 700);

  // ── Screen-level transitions (page_transitions.dart) ─────────────────────
  // Centralized here too so a route push and an in-screen reveal can be
  // reasoned about together — e.g. slideUp's duration vs Reveal's delay
  // is intentional (see ScreenReveal below), not a coincidence.
  static const Duration routeSlideUp = Duration(milliseconds: 340);
  static const Duration routeSlideUpReverse = Duration(milliseconds: 280);
  static const Duration routeFade = Duration(milliseconds: 350);
}