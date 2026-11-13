// theme/tokens.dart
//
// Sage's personality in numbers: spacing, shape and motion in one place, so
// the whole app can be made softer, tighter or livelier by changing a few
// constants here. Colors live in SageColors, type in SageText.
import 'package:material_ui/material_ui.dart';

/// Spacing scale (logical pixels). Airy by default: use these instead of ad
/// hoc numbers.
class SageSpace {
  SageSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal gutter for scrolling screens.
  static const double gutter = 22;
}

/// Shape language: soft and friendly. Nothing is sharp, and every surface
/// carries one slightly tighter corner (top-left), like the tip of a leaf.
class SageRadius {
  SageRadius._();

  /// Scales every rounded corner of 8px or more. The single knob for "how
  /// soft is Sage": raise it for pillowier shapes, lower it for crisper ones.
  static const double softness = 1.3;

  /// Radius of the leaf-tip corner.
  static const double notch = 10;

  /// Corners at or below this stay as written: they belong to thin things
  /// (progress bars, dots) that would turn into capsules if scaled.
  static const double _scaleFloor = 8;

  /// A uniformly rounded corner, softened by [softness].
  static BorderRadius round(double radius) =>
      BorderRadius.circular(radius >= _scaleFloor ? radius * softness : radius);

  /// The leaf-tip shape: one tighter corner, the rest soft.
  static BorderRadius notched(double radius) {
    final r = Radius.circular(radius * softness);
    return BorderRadius.only(
      topLeft: const Radius.circular(notch),
      topRight: r,
      bottomLeft: r,
      bottomRight: r,
    );
  }

  /// Large content surfaces.
  static final BorderRadius card = notched(20);

  /// Compact tiles in horizontal rows.
  static final BorderRadius tile = notched(14);

  /// Form fields and buttons (as a plain radius for theme APIs).
  static double get control => 14 * softness;

  /// Fully round, for pills and chips.
  static const double pill = 999;
}

/// Minimum interactive size recommended by Material and Apple guidelines.
const double kSageMinTapTarget = 48;
