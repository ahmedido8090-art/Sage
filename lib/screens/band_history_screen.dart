// screens/band_history_screen.dart
//
// Steps and heart rate over the last week or two, from what the band has
// actually reported. Days it said nothing about are shown as gaps, never as
// zeros.
import 'package:material_ui/material_ui.dart';
import '../band/band_history.dart';
import '../band/band_monitor.dart';
import '../band/band_picker.dart';
import '../services/data_storage_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/band_offline_notice.dart';
import '../widgets/sage_card.dart';
import '../widgets/sage_illustration.dart';
import '../widgets/sage_screen_header.dart';
import '../widgets/sage_skeleton.dart';
import '../widgets/sage_states.dart';

class BandHistoryScreen extends StatefulWidget {
  const BandHistoryScreen({super.key});

  @override
  State<BandHistoryScreen> createState() => _BandHistoryScreenState();
}

class _BandHistoryScreenState extends State<BandHistoryScreen> {
  List<BandReading> _readings = const [];
  bool _loading = true;
  Object? _error;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await DataStorageService().getBandData(daysBack: 14);
      if (!mounted) return;
      setState(() {
        _readings = [
          for (final r in rows)
            BandReading(
              heartRate: r['hr'] as int,
              steps: r['steps'] as int,
              at: r['time'] as DateTime,
            ),
        ];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SageColors.linen,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SageSpace.sm, SageSpace.sm, SageSpace.gutter, 0),
              child: const SageScreenHeader(title: 'Band history'),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(SageSpace.gutter),
        child: SageSkeleton.screen(cards: 2),
      );
    }
    if (_error != null) {
      return ErrorState(error: _error, onRetry: _load);
    }
    if (_readings.isEmpty) {
      return EmptyState(
        art: SageArt.band,
        title: 'No band readings yet',
        message: 'Once your band syncs, your steps and heart rate will '
            'appear here.',
        actionLabel: 'Connect band',
        onAction: () => showBandPicker(context),
      );
    }

    final now = DateTime.now();
    final days = BandHistory.compute(_readings, now: now, days: _days);
    final series = BandHistory.todaySeries(_readings, now: now);
    final goal = UserService().currentUserObject?.dailyStepGoal ?? 8000;

    return RefreshIndicator(
      color: SageColors.moss,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            SageSpace.gutter, SageSpace.md, SageSpace.gutter, SageSpace.xxl),
        children: [
          _periodChips(),
          const SizedBox(height: SageSpace.lg),
          const BandOfflineNotice(
            featureName: 'Your history',
            compact: true,
            whatWorks: 'Everything below is saved on your phone.',
          ),
          const SizedBox(height: SageSpace.lg),
          _stepsCard(days, goal),
          const SizedBox(height: SageSpace.lg),
          _heartCard(days, series),
          const SizedBox(height: SageSpace.md),
          ValueListenableBuilder<BandSnapshot>(
            valueListenable: BandMonitor.instance.snapshot,
            builder: (_, band, __) => Center(
              child: Text(describeSynced(band.lastReadingAt),
                  style: SageText.caption()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodChips() => Row(
        children: [
          for (final d in const [7, 14]) ...[
            Semantics(
              button: true,
              selected: _days == d,
              label: 'Show last $d days',
              child: ChoiceChip(
                label: Text('$d days'),
                selected: _days == d,
                onSelected: (_) => setState(() => _days = d),
                selectedColor: SageColors.moss.withValues(alpha: 0.18),
              ),
            ),
            const SizedBox(width: SageSpace.sm),
          ],
        ],
      );

  Widget _stepsCard(List<DayStats> days, int goal) {
    final avg = BandHistory.averageSteps(days);
    final summary = avg == null
        ? 'Not enough readings to count steps yet.'
        : 'About ${_thousands(avg)} a day on average';
    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Steps', subtitle: summary),
          const SizedBox(height: SageSpace.lg),
          _AnimatedChart(
            key: ValueKey('steps$_days'),
            height: 150,
            semanticLabel: 'Steps for the last $_days days. $summary.',
            painterFor: (t) => _StepsPainter(
              days: days,
              goal: goal,
              progress: t,
              bar: SageColors.moss,
              goalLine: SageColors.amber,
              text: SageColors.inkSoft,
              track: SageColors.line,
            ),
          ),
          const SizedBox(height: SageSpace.sm),
          Row(
            children: [
              Container(
                  width: 14,
                  height: 2,
                  color: SageColors.legible(SageColors.amber)),
              const SizedBox(width: SageSpace.sm),
              Text('Goal ${_thousands(goal)}', style: SageText.caption()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heartCard(List<DayStats> days, List<HrPoint> series) {
    final today = days.last;
    final summary = today.avgHeartRate == null
        ? 'No heart rate readings today.'
        : 'Today averaged ${today.avgHeartRate} bpm '
            '(${today.minHeartRate}–${today.maxHeartRate})';
    final anyHr = days.any((d) => d.avgHeartRate != null);
    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Heart rate', subtitle: summary),
          if (series.length >= 2) ...[
            const SizedBox(height: SageSpace.lg),
            _AnimatedChart(
              key: const ValueKey('spark'),
              height: 70,
              semanticLabel: 'Heart rate across today. $summary.',
              painterFor: (t) => _SparklinePainter(
                points: series,
                progress: t,
                line: SageColors.clay,
              ),
            ),
          ],
          if (anyHr) ...[
            const SizedBox(height: SageSpace.lg),
            Text('Daily range', style: SageText.caption()),
            const SizedBox(height: SageSpace.sm),
            _AnimatedChart(
              key: ValueKey('range$_days'),
              height: 130,
              semanticLabel: 'Daily heart rate range for the last $_days days.',
              painterFor: (t) => _RangePainter(
                days: days,
                progress: t,
                capsule: SageColors.clay,
                text: SageColors.inkSoft,
                track: SageColors.line,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// Draws a chart in over a moment (or straight away under reduced motion),
/// on its own repaint layer.
class _AnimatedChart extends StatelessWidget {
  final double height;
  final String semanticLabel;
  final CustomPainter Function(double progress) painterFor;

  const _AnimatedChart({
    super.key,
    required this.height,
    required this.semanticLabel,
    required this.painterFor,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduce ? 1 : 0, end: 1),
          duration: SageMotion.revealLarge * 1.6,
          curve: SageMotion.revealCurve,
          builder: (_, t, __) => CustomPaint(
            size: Size(double.infinity, height),
            painter: painterFor(t),
          ),
        ),
      ),
    );
  }
}

const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

void _paintLabel(Canvas canvas, String text, Offset center, Color color) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontSize: 11, color: color)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, 0));
}

class _StepsPainter extends CustomPainter {
  final List<DayStats> days;
  final int goal;
  final double progress;
  final Color bar, goalLine, text, track;

  _StepsPainter({
    required this.days,
    required this.goal,
    required this.progress,
    required this.bar,
    required this.goalLine,
    required this.text,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 18.0;
    final plotH = size.height - labelH;
    final maxSteps = [
          goal,
          for (final d in days)
            if (d.steps != null) d.steps!,
        ].reduce((a, b) => a > b ? a : b) *
        1.1;

    final slot = size.width / days.length;
    final barW = (slot * 0.56).clamp(6.0, 26.0);

    for (var i = 0; i < days.length; i++) {
      final cx = slot * i + slot / 2;
      final steps = days[i].steps;
      final rrectTrack = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barW / 2, 0, barW, plotH),
        Radius.circular(barW / 2),
      );
      canvas.drawRRect(
          rrectTrack, Paint()..color = track.withValues(alpha: 0.5));
      if (steps != null && steps > 0) {
        final h = plotH * (steps / maxSteps) * progress;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barW / 2, plotH - h, barW, h),
            Radius.circular(barW / 2),
          ),
          Paint()..color = bar,
        );
      }
      final letter = _dayLetters[(days[i].day.weekday - 1) % 7];
      _paintLabel(canvas, letter, Offset(cx, plotH + 4), text);
    }

    // Goal line, dashed.
    final y = plotH - plotH * (goal / maxSteps);
    final paint = Paint()
      ..color = goalLine
      ..strokeWidth = 1.5;
    for (var x = 0.0; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, y), Offset(x + 5, y), paint);
    }
  }

  @override
  bool shouldRepaint(_StepsPainter old) =>
      old.progress != progress || old.days != days || old.bar != bar;
}

class _RangePainter extends CustomPainter {
  final List<DayStats> days;
  final double progress;
  final Color capsule, text, track;

  _RangePainter({
    required this.days,
    required this.progress,
    required this.capsule,
    required this.text,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 18.0;
    final plotH = size.height - labelH;
    final withData = days.where((d) => d.minHeartRate != null).toList();
    if (withData.isEmpty) return;
    final lo =
        (withData.map((d) => d.minHeartRate!).reduce((a, b) => a < b ? a : b) -
                8)
            .clamp(30, 200)
            .toDouble();
    final hi =
        (withData.map((d) => d.maxHeartRate!).reduce((a, b) => a > b ? a : b) +
                8)
            .clamp(40, 220)
            .toDouble();
    double yFor(num bpm) => plotH - plotH * ((bpm - lo) / (hi - lo));

    final slot = size.width / days.length;
    final w = (slot * 0.4).clamp(6.0, 18.0);
    for (var i = 0; i < days.length; i++) {
      final cx = slot * i + slot / 2;
      final d = days[i];
      if (d.minHeartRate != null) {
        final top = yFor(d.maxHeartRate!);
        final bottom = yFor(d.minHeartRate!);
        final mid = (top + bottom) / 2;
        final half = (bottom - top) / 2 * progress;
        final rect =
            Rect.fromLTRB(cx - w / 2, mid - half, cx + w / 2, mid + half + 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(w / 2)),
          Paint()..color = capsule.withValues(alpha: 0.45),
        );
        canvas.drawCircle(
          Offset(cx, yFor(d.avgHeartRate!)),
          w / 2 + 1,
          Paint()..color = capsule,
        );
      }
      final letter = _dayLetters[(d.day.weekday - 1) % 7];
      _paintLabel(canvas, letter, Offset(cx, plotH + 4), text);
    }
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.progress != progress || old.days != days || old.capsule != capsule;
}

class _SparklinePainter extends CustomPainter {
  final List<HrPoint> points;
  final double progress;
  final Color line;

  _SparklinePainter({
    required this.points,
    required this.progress,
    required this.line,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final lo = points.map((p) => p.bpm).reduce((a, b) => a < b ? a : b) - 4;
    final hi = points.map((p) => p.bpm).reduce((a, b) => a > b ? a : b) + 4;
    final t0 = points.first.at.millisecondsSinceEpoch;
    final span = points.last.at.millisecondsSinceEpoch - t0;
    if (span <= 0) return;

    Offset at(HrPoint p) => Offset(
          (p.at.millisecondsSinceEpoch - t0) / span * size.width,
          size.height - size.height * ((p.bpm - lo) / (hi - lo)),
        );

    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (var i = 1; i < points.length; i++) {
      final a = at(points[i - 1]), b = at(points[i]);
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.progress != progress || old.points != points || old.line != line;
}
