// widgets/animated_number.dart
//
// Counts up from the previous value to a new one whenever [value]
// changes — never on initial mount (mounting snaps directly to the
// current value; only changes animate). Uses SageMotion.numberCountUp
// as its default so every count-up in the app (BPM, steps, score) moves
// at the same speed unless a call site has a specific reason to differ.
import 'package:flutter/material.dart';
import '../theme/motion.dart';

class AnimatedNumber extends StatefulWidget {
  final int value;
  final String Function(int v)? formatter;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  const AnimatedNumber({
    super.key,
    required this.value,
    this.formatter,
    this.style,
    this.duration = SageMotion.numberCountUp,
    this.curve = SageMotion.revealCurve,
  });

  @override
  State<AnimatedNumber> createState() => _AnimatedNumberState();
}

class _AnimatedNumberState extends State<AnimatedNumber>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    // Snap to current value on creation — animation only plays on
    // value changes (see didUpdateWidget), never on initial mount.
    _anim = Tween<double>(
      begin: widget.value.toDouble(),
      end: widget.value.toDouble(),
    ).animate(CurvedAnimation(parent: _ctrl, curve: widget.curve));
  }

  @override
  void didUpdateWidget(covariant AnimatedNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _anim = Tween<double>(
        begin: oldWidget.value.toDouble(),
        end: widget.value.toDouble(),
      ).animate(CurvedAnimation(parent: _ctrl, curve: widget.curve));
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final displayVal = _anim.value.round();
        final text = widget.formatter != null
            ? widget.formatter!(displayVal)
            : '$displayVal';
        return Text(text, style: widget.style);
      },
    );
  }
}

/// Double variant — same model as AnimatedNumber.
class AnimatedDouble extends StatefulWidget {
  final double value;
  final String Function(double v)? formatter;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  const AnimatedDouble({
    super.key,
    required this.value,
    this.formatter,
    this.style,
    this.duration = SageMotion.numberCountUp,
    this.curve = SageMotion.revealCurve,
  });

  @override
  State<AnimatedDouble> createState() => _AnimatedDoubleState();
}

class _AnimatedDoubleState extends State<AnimatedDouble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween<double>(begin: widget.value, end: widget.value)
        .animate(CurvedAnimation(parent: _ctrl, curve: widget.curve));
  }

  @override
  void didUpdateWidget(covariant AnimatedDouble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _anim = Tween<double>(begin: oldWidget.value, end: widget.value)
          .animate(CurvedAnimation(parent: _ctrl, curve: widget.curve));
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final text = widget.formatter != null
            ? widget.formatter!(_anim.value)
            : _anim.value.toStringAsFixed(0);
        return Text(text, style: widget.style);
      },
    );
  }
}