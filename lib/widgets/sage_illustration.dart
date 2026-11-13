// widgets/sage_illustration.dart
//
// Sage's one illustration style: a soft organic blob, a rounded icon, and a
// couple of tiny sparkles. Built from existing Material icons and a single
// painted path, so there are no assets or dependencies to carry.
//
// Playful moods (empty, success) can sway or breathe; calm moods (errors,
// permissions, health data) stand still. The animation is one controller in
// a RepaintBoundary, pauses automatically when its screen is offstage, and
// is skipped entirely when the system asks for reduced motion.
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';

enum SageArt {
  leaf(Icons.eco_rounded),
  water(Icons.water_drop_rounded),
  moon(Icons.nights_stay_rounded),
  heart(Icons.favorite_rounded),
  mood(Icons.mood_rounded),
  bell(Icons.notifications_rounded),
  band(Icons.watch_rounded),
  chart(Icons.insights_rounded),
  trophy(Icons.emoji_events_rounded),
  calm(Icons.spa_rounded),
  check(Icons.check_rounded),
  plate(Icons.restaurant_rounded);

  const SageArt(this.icon);
  final IconData icon;
}

enum SageArtMotion { still, sway, breathe }

class SageIllustration extends StatefulWidget {
  final SageArt art;
  final double size;
  final Color? accent;
  final SageArtMotion motion;

  const SageIllustration({
    super.key,
    required this.art,
    this.size = 132,
    this.accent,
    this.motion = SageArtMotion.still,
  });

  @override
  State<SageIllustration> createState() => _SageIllustrationState();
}

class _SageIllustrationState extends State<SageIllustration>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = widget.motion != SageArtMotion.still &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: widget.motion == SageArtMotion.sway
            ? SageMotion.swayPeriod
            : SageMotion.pulsePeriod,
      )..repeat(reverse: true);
    } else if (!animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = SageColors.legible(widget.accent ?? SageColors.moss);
    final size = widget.size;

    Widget icon = Icon(widget.art.icon, size: size * 0.4, color: accent);
    Widget blob = CustomPaint(
      size: Size.square(size),
      painter: _BlobPainter(
        color: accent.withValues(alpha: SageColors.isDark ? 0.2 : 0.15),
        echo: accent.withValues(alpha: SageColors.isDark ? 0.1 : 0.08),
      ),
    );

    final controller = _controller;
    if (controller != null) {
      final curved =
          CurvedAnimation(parent: controller, curve: SageMotion.softCurve);
      if (widget.motion == SageArtMotion.sway) {
        icon = AnimatedBuilder(
          animation: curved,
          builder: (_, child) => Transform.rotate(
            angle: (curved.value * 2 - 1) * SageMotion.swayAngle,
            child: child,
          ),
          child: icon,
        );
      } else {
        blob = ScaleTransition(
          scale: Tween<double>(begin: 1, end: SageMotion.pulseScale)
              .animate(curved),
          child: blob,
        );
      }
    }

    return Semantics(
      excludeSemantics: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              blob,
              icon,
              _sparkle(size * 0.16, size * 0.2, size * 0.07, accent),
              _sparkle(size * 0.84, size * 0.3, size * 0.05, accent),
              _sparkle(size * 0.78, size * 0.84, size * 0.06, accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sparkle(double x, double y, double r, Color color) => Positioned(
        left: x - r,
        top: y - r,
        child: Container(
          width: r * 2,
          height: r * 2,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
        ),
      );
}

/// A pebble-like closed shape: a circle with a gentle three-lobed wobble, plus
/// a faint offset copy behind it for depth. Static, so painted once.
class _BlobPainter extends CustomPainter {
  final Color color;
  final Color echo;
  const _BlobPainter({required this.color, required this.echo});

  Path _path(Size size, {double wobble = 0.07, double phase = 0}) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide * 0.44;
    const steps = 56;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * math.pi * 2;
      final r = base * (1 + wobble * math.sin(3 * t + phase));
      final p = c + Offset(math.cos(t) * r, math.sin(t) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width * 0.04, size.height * 0.05);
    canvas.drawPath(
        _path(size, wobble: 0.1, phase: 1.4), Paint()..color = echo);
    canvas.restore();
    canvas.drawPath(_path(size), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.color != color || old.echo != echo;
}
