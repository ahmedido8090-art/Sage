// band/band_history.dart
//
// Turns stored band readings into per-day numbers for the history screen:
// steps for each day, and the heart-rate range and average. Pure and I/O-free.
// Days the band said nothing about stay null: they are shown as gaps, never
// as zeros.
import 'step_tally.dart';

class BandReading {
  final int heartRate;
  final int steps;
  final DateTime at;
  const BandReading(
      {required this.heartRate, required this.steps, required this.at});
}

class DayStats {
  final DateTime day;

  /// Steps taken that day, or null if the band did not report enough to tell.
  final int? steps;
  final int? avgHeartRate;
  final int? minHeartRate;
  final int? maxHeartRate;
  final int readings;

  const DayStats({
    required this.day,
    this.steps,
    this.avgHeartRate,
    this.minHeartRate,
    this.maxHeartRate,
    this.readings = 0,
  });

  bool get hasData => readings > 0;
}

class HrPoint {
  final DateTime at;
  final int bpm;
  const HrPoint(this.at, this.bpm);
}

class BandHistory {
  BandHistory._();

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// One entry per day for the last [days] days, oldest first, ending today.
  static List<DayStats> compute(
    List<BandReading> readings, {
    required DateTime now,
    int days = 7,
  }) {
    final sorted = [...readings]..sort((a, b) => a.at.compareTo(b.at));

    // Steps: one tally across the whole stretch so overnight continuity and
    // counter resets are handled the same way as on the Home screen.
    final tally = StepTally();
    final stepTotals = <DateTime, int>{};
    final stepReadings = <DateTime, int>{};
    for (final r in sorted) {
      if (r.steps <= 0) continue;
      tally.add(r.steps, r.at);
      final day = _midnight(r.at);
      stepTotals[day] = tally.today ?? 0;
      stepReadings[day] = (stepReadings[day] ?? 0) + 1;
    }

    final hrByDay = <DateTime, List<int>>{};
    final countByDay = <DateTime, int>{};
    for (final r in sorted) {
      final day = _midnight(r.at);
      countByDay[day] = (countByDay[day] ?? 0) + 1;
      if (r.heartRate > 0) (hrByDay[day] ??= []).add(r.heartRate);
    }

    final today = _midnight(now);
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final day = DateTime(today.year, today.month, today.day - i);
          final hrs = hrByDay[day];
          return DayStats(
            day: day,
            // A single reading is only a baseline: not enough to call a total.
            steps: (stepReadings[day] ?? 0) >= 2 ? stepTotals[day] : null,
            avgHeartRate: hrs == null
                ? null
                : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
            minHeartRate: hrs?.reduce((a, b) => a < b ? a : b),
            maxHeartRate: hrs?.reduce((a, b) => a > b ? a : b),
            readings: countByDay[day] ?? 0,
          );
        }(),
    ];
  }

  /// Today's heart rate as at most [maxPoints] points, averaged into equal
  /// time buckets so a long day stays cheap to draw.
  static List<HrPoint> todaySeries(
    List<BandReading> readings, {
    required DateTime now,
    int maxPoints = 48,
  }) {
    final today = _midnight(now);
    final pts = readings
        .where((r) => r.heartRate > 0 && !r.at.isBefore(today))
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (pts.length <= maxPoints) {
      return [for (final r in pts) HrPoint(r.at, r.heartRate)];
    }
    final span = pts.last.at.difference(pts.first.at).inMilliseconds;
    if (span <= 0) return [HrPoint(pts.first.at, pts.first.heartRate)];
    final buckets = List.generate(maxPoints, (_) => <BandReading>[]);
    for (final r in pts) {
      final f = r.at.difference(pts.first.at).inMilliseconds / span;
      buckets[(f * (maxPoints - 1)).round()].add(r);
    }
    return [
      for (final b in buckets)
        if (b.isNotEmpty)
          HrPoint(
            b[b.length ~/ 2].at,
            (b.map((r) => r.heartRate).reduce((a, c) => a + c) / b.length)
                .round(),
          ),
    ];
  }

  /// Average steps over days that have a total, or null if none do.
  static int? averageSteps(List<DayStats> days) {
    final totals = [
      for (final d in days)
        if (d.steps != null) d.steps!
    ];
    if (totals.isEmpty) return null;
    return (totals.reduce((a, b) => a + b) / totals.length).round();
  }
}
