// widgets/shimmer_loader.dart
//
// A lightweight shimmer skeleton that requires zero external packages —
// it's a pure Flutter AnimationController + a custom gradient sweep.
// Use SageShimmer as a drop-in placeholder wherever a card would normally
// appear while data is loading. ShimmerCard and ShimmerRow are convenience
// wrappers for the two most common shapes in Sage Health.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Wraps any child with a sweeping shimmer overlay.
///
/// Usage:
/// ```dart
/// SageShimmer(child: ShimmerCard(width: double.infinity, height: 100))
/// ```
class SageShimmer extends StatefulWidget {
  final Widget child;

  const SageShimmer({super.key, required this.child});

  @override
  State<SageShimmer> createState() => _SageShimmerState();
}

class _SageShimmerState extends State<SageShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = SageColors.isDark
        ? SageColors.card
        : const Color(0xFFEEECE6);
    final highlight = SageColors.isDark
        ? SageColors.line
        : const Color(0xFFF7F5EF);

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [base, highlight, base],
          stops: const [0.0, 0.5, 1.0],
          transform: _SweepTransform(_anim.value),
        ).createShader(bounds),
        child: widget.child,
      ),
    );
  }
}

class _SweepTransform extends GradientTransform {
  final double offset;
  const _SweepTransform(this.offset);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * offset, 0, 0);
  }
}

/// A rounded rectangle placeholder block — the building block for skeletons.
class ShimmerBlock extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const ShimmerBlock({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final color = SageColors.isDark
        ? SageColors.card
        : const Color(0xFFEEECE6);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius ?? BorderRadius.circular(8),
      ),
    );
  }
}

/// Skeleton mimicking the SageHeroCard shape.
class ShimmerHeroCard extends StatelessWidget {
  const ShimmerHeroCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SageShimmer(
      child: Container(
        width: double.infinity,
        height: 170,
        decoration: BoxDecoration(
          color: SageColors.isDark ? SageColors.card : const Color(0xFFEEECE6),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBlock(width: 150, height: 16, borderRadius: BorderRadius.circular(8)),
            const SizedBox(height: 16),
            ShimmerBlock(width: 90, height: 48, borderRadius: BorderRadius.circular(8)),
            const SizedBox(height: 8),
            ShimmerBlock(width: double.infinity, height: 20, borderRadius: BorderRadius.circular(6)),
          ],
        ),
      ),
    );
  }
}

/// Skeleton mimicking a MetricTile.
class ShimmerMetricTile extends StatelessWidget {
  const ShimmerMetricTile({super.key});

  @override
  Widget build(BuildContext context) {
    return SageShimmer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: SageColors.isDark ? SageColors.card : const Color(0xFFEEECE6),
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
            ShimmerBlock(width: 18, height: 18, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 10),
            ShimmerBlock(width: 64, height: 22, borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 6),
            ShimmerBlock(width: 48, height: 12, borderRadius: BorderRadius.circular(4)),
          ],
        ),
      ),
    );
  }
}

/// Skeleton mimicking a WellnessActivityTile.
class ShimmerActivityTile extends StatelessWidget {
  const ShimmerActivityTile({super.key});

  @override
  Widget build(BuildContext context) {
    return SageShimmer(
      child: Container(
        width: 124,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: SageColors.isDark ? SageColors.card : const Color(0xFFEEECE6),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBlock(width: 20, height: 20, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 14),
            ShimmerBlock(width: 80, height: 13, borderRadius: BorderRadius.circular(5)),
            const SizedBox(height: 5),
            ShimmerBlock(width: 55, height: 10, borderRadius: BorderRadius.circular(4)),
          ],
        ),
      ),
    );
  }
}