// widgets/pulse_wave_painter.dart
//
// FIX: _syncAnimationState now always updates _controller.duration before
// calling repeat(). Previously, if heartRate was 0 when the controller
// stopped, it kept the stale clamped duration (1600ms). On reconnect,
// repeat() would run at that wrong speed for one cycle before the next
// didUpdateWidget corrected it — causing a visible lurch the moment
// the band connected.
import 'package:flutter/material.dart';

class PulseWavePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double phase;
  final bool dimmed;

  const PulseWavePainter({
    this.color = const Color(0xFF7FA889),
    this.strokeWidth = 1.6,
    this.phase = 0,
    this.dimmed = false,
  });

  double _waveY(double tRaw) {
    final double t = tRaw - tRaw.floorToDouble();

    double hump(double start, double width, double height) {
      final double local = (t - start) / width;
      if (local < 0 || local > 1) return 0;
      return height * (1 - (2 * local - 1) * (2 * local - 1));
    }

    double y = 0;
    y += hump(0.06, 0.085, -0.32);
    y += hump(0.145, 0.09, 0.5);

    if (t > 0.40 && t < 0.46) {
      final double local = (t - 0.40) / 0.06;
      y += local < 0.5
          ? -1.05 * (local / 0.5)
          : -1.05 * (1 - (local - 0.5) / 0.5);
    } else if (t >= 0.46 && t < 0.50) {
      final double local = (t - 0.46) / 0.04;
      y += 0.32 * (1 - (2 * local - 1) * (2 * local - 1));
    }

    y += hump(0.62, 0.085, -0.32);
    y += hump(0.705, 0.09, 0.5);
    return y;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dimmed ? color.withValues(alpha: 0.4) : color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (dimmed) {
      final double y = size.height * 0.6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }

    final double midY = size.height * 0.6;
    final double amp = size.height * 0.42;
    const int samples = 160;

    final path = Path();
    for (int i = 0; i <= samples; i++) {
      final double xNorm = i / samples;
      final double y = midY + _waveY(xNorm + phase) * amp;
      final double x = xNorm * size.width;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant PulseWavePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.phase != phase ||
      oldDelegate.dimmed != dimmed;
}

class PulseWave extends StatefulWidget {
  final double height;
  final Color color;
  final int heartRate;
  final bool isLive;

  const PulseWave({
    super.key,
    this.height = 46,
    this.color = const Color(0xFF7FA889),
    this.heartRate = 0,
    this.isLive = false,
  });

  @override
  State<PulseWave> createState() => _PulseWaveState();
}

class _PulseWaveState extends State<PulseWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Returns a cycle duration clamped to a sensible range.
  // Called both on init and before every repeat() so the controller
  // is always running at the right speed for the current heart rate.
  Duration _cycleDuration() {
    if (widget.heartRate < 30) return const Duration(milliseconds: 1000);
    final int ms = (60000 / widget.heartRate).clamp(420, 1600).round();
    return Duration(milliseconds: ms);
  }

  bool get _shouldAnimate => widget.isLive && widget.heartRate >= 30;

  void _syncAnimationState() {
    if (_shouldAnimate) {
      // Always update duration FIRST so repeat() runs at the correct
      // speed immediately — not at whatever stale duration it had before.
      _controller.duration = _cycleDuration();
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: _cycleDuration());
    _syncAnimationState();
  }

  @override
  void didUpdateWidget(covariant PulseWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heartRate != widget.heartRate ||
        oldWidget.isLive != widget.isLive) {
      _syncAnimationState();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: PulseWavePainter(
            color: widget.color,
            phase: _controller.value,
            dimmed: !widget.isLive,
          ),
        ),
      ),
    );
  }
}
