// widgets/animated_pillar_row.dart
//
// Animates a labeled progress bar from 0 (or its previous value) to
// [score]. Duration now comes from SageMotion so it's not an isolated
// 800ms with no relationship to the rest of the entrance system.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';

class AnimatedPillarRow extends StatefulWidget {
  final String label;
  final int score;
  final bool hasData;
  final IconData icon;
  final Color color;

  const AnimatedPillarRow({
    super.key,
    required this.label,
    required this.score,
    required this.hasData,
    required this.icon,
    required this.color,
  });

  @override
  State<AnimatedPillarRow> createState() => _AnimatedPillarRowState();
}

class _AnimatedPillarRowState extends State<AnimatedPillarRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _progress;
  late Animation<double> _labelOpacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: SageMotion.revealLarge);
    _rebuildAnimation(from: 0, to: widget.hasData ? widget.score / 100.0 : 0);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedPillarRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score || oldWidget.hasData != widget.hasData) {
      final prevProgress = _progress.value;
      _rebuildAnimation(
        from: prevProgress,
        to: widget.hasData ? widget.score / 100.0 : 0,
      );
      _ctrl
        ..reset()
        ..forward();
    }
  }

  void _rebuildAnimation({required double from, required double to}) {
    _progress = Tween<double>(begin: from, end: to).animate(
      CurvedAnimation(parent: _ctrl, curve: SageMotion.revealCurve),
    );
    _labelOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        children: [
          Icon(widget.icon, size: 13, color: widget.color),
          const SizedBox(width: 5),
          SizedBox(
            width: 60,
            child: FadeTransition(
              opacity: _labelOpacity,
              child: Text(
                widget.label,
                style: TextStyle(fontSize: 11, color: SageColors.inkSoft),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress.value,
                minHeight: 5,
                backgroundColor: SageColors.line,
                valueColor: AlwaysStoppedAnimation<Color>(widget.color),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 26,
            child: FadeTransition(
              opacity: _labelOpacity,
              child: Text(
                widget.hasData ? '${widget.score}' : '--',
                style: SageText.mono(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: SageColors.inkSoft,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }
}