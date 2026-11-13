// widgets/sage_skeleton.dart
//
// Loading placeholders shaped like the content that is coming, so nothing
// jumps when data arrives. All the blocks in one skeleton share a single
// shimmer sweep (one controller), and it is cheap enough to leave running.
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'shimmer_loader.dart';

class SageSkeleton extends StatelessWidget {
  final Widget child;
  const SageSkeleton._(this.child);

  /// A card with a title line and [lines] lines of text, like most SageCards.
  factory SageSkeleton.card({int lines = 3, double? height}) =>
      SageSkeleton._(_SkeletonCard(lines: lines, height: height));

  /// A vertical stack of [count] row placeholders (icon, two text lines).
  factory SageSkeleton.list({int count = 4}) => SageSkeleton._(Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            const _SkeletonRow(),
            if (i != count - 1) const SizedBox(height: SageSpace.md),
          ],
        ],
      ));

  /// A whole screen body: a header, a hero block and a few cards.
  factory SageSkeleton.screen({int cards = 3}) => SageSkeleton._(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBlock(
              width: 180, height: 28, borderRadius: SageRadius.round(10)),
          const SizedBox(height: SageSpace.lg),
          ShimmerBlock(
              width: double.infinity,
              height: 150,
              borderRadius: SageRadius.notched(20)),
          for (var i = 0; i < cards; i++) ...[
            const SizedBox(height: SageSpace.lg),
            const _SkeletonCard(lines: 2),
          ],
        ],
      ));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      liveRegion: true,
      excludeSemantics: true,
      child: SageShimmer(child: child),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final int lines;
  final double? height;
  const _SkeletonCard({required this.lines, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(SageSpace.xl - 4),
      decoration: BoxDecoration(
        color: SageColors.card,
        borderRadius: SageRadius.card,
        border: Border.all(color: SageColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBlock(
              width: 140, height: 18, borderRadius: SageRadius.round(9)),
          for (var i = 0; i < lines; i++) ...[
            const SizedBox(height: SageSpace.md),
            ShimmerBlock(
              width: i == lines - 1 ? 200 : double.infinity,
              height: 12,
              borderRadius: SageRadius.round(8),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ShimmerBlock(width: 44, height: 44, borderRadius: SageRadius.round(22)),
        const SizedBox(width: SageSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBlock(
                  width: 160, height: 14, borderRadius: SageRadius.round(8)),
              const SizedBox(height: SageSpace.sm),
              ShimmerBlock(
                  width: 100, height: 11, borderRadius: SageRadius.round(8)),
            ],
          ),
        ),
      ],
    );
  }
}
