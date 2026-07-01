// widgets/staggered_list.dart
//
// Fade-and-rise entrance for lists and grids. Wrap individual items in
// StaggeredItem and give each a unique [index].
//
// FIX: replaced Future.delayed with a single addPostFrameCallback +
// one-shot timer. Previously, every parent setState() created a new
// timer because State was re-created, causing entrance animations to
// re-fire mid-session. Now the timer is created once and never again
// (guarded by _started).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class StaggeredItem extends StatefulWidget {
  final int index;
  final Duration initialDelay;
  final Duration staggerStep;
  final Duration itemDuration;
  final Widget child;

  const StaggeredItem({
    super.key,
    required this.index,
    required this.child,
    this.initialDelay = Duration.zero,
    this.staggerStep = const Duration(milliseconds: 60),
    this.itemDuration = const Duration(milliseconds: 380),
  });

  @override
  State<StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  // Guards against re-scheduling if the parent rebuilds before the
  // timer fires. Without this flag, each setState() in the parent would
  // register another callback and the entrance fires multiple times.
  bool _started = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.itemDuration);
    _opacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    // Schedule after the first frame so the widget is laid out before
    // animating, and so the timer is only created once per State lifetime.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_started || !mounted) return;
      _started = true;
      final delay = widget.initialDelay + widget.staggerStep * widget.index;
      if (delay == Duration.zero) {
        _ctrl.forward();
      } else {
        _timer = Timer(delay, () {
          if (mounted) _ctrl.forward();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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

/// Convenience wrapper that auto-staggers a fixed list of children.
class StaggeredColumn extends StatelessWidget {
  final List<Widget> children;
  final Duration initialDelay;
  final Duration staggerStep;

  const StaggeredColumn({
    super.key,
    required this.children,
    this.initialDelay = Duration.zero,
    this.staggerStep = const Duration(milliseconds: 70),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        children.length,
        (i) => StaggeredItem(
          index: i,
          initialDelay: initialDelay,
          staggerStep: staggerStep,
          child: children[i],
        ),
      ),
    );
  }
}