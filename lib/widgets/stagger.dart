// widgets/stagger.dart
//
// Staggered entrance for lists/columns/grids — every item Reveals with an
// increasing delay. Built directly on Reveal so staggered items use the
// exact same duration/curve/distance tokens as every other entrance in
// the app; this replaces the old staggered_list.dart (StaggeredItem /
// StaggeredColumn), whose Future.delayed-in-initState pattern could stack
// duplicate timers across rebuilds, and whose distance/duration constants
// didn't match Reveal's.
import 'package:flutter/material.dart';
import '../theme/motion.dart';
import 'reveal.dart';

/// Wrap a single item in a staggered group. [index] determines its delay.
class StaggerItem extends StatelessWidget {
  final int index;
  final Widget child;
  final RevealSize size;
  final Duration initialDelay;
  final Duration step;

  const StaggerItem({
    super.key,
    required this.index,
    required this.child,
    this.size = RevealSize.small,
    this.initialDelay = Duration.zero,
    this.step = SageMotion.staggerStep,
  });

  @override
  Widget build(BuildContext context) {
    return Reveal(
      size: size,
      delay: initialDelay + step * index,
      child: child,
    );
  }
}

/// Convenience wrapper for a fixed list of children laid out in a Column.
/// For ListView.builder or GridView, use [StaggerItem] directly per item.
class StaggerColumn extends StatelessWidget {
  final List<Widget> children;
  final RevealSize size;
  final Duration initialDelay;
  final Duration step;
  final CrossAxisAlignment crossAxisAlignment;

  const StaggerColumn({
    super.key,
    required this.children,
    this.size = RevealSize.small,
    this.initialDelay = Duration.zero,
    this.step = SageMotion.staggerStep,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: List.generate(
        children.length,
        (i) => StaggerItem(
          index: i,
          size: size,
          initialDelay: initialDelay,
          step: step,
          child: children[i],
        ),
      ),
    );
  }
}