// services/weekly_summary.dart
//
// "Your week": the last seven days against the seven before, plus a short
// headline in Sage's voice. Pure and I/O-free. The wording is encouraging in
// every case, including a quiet week.
import '../models/bella_data.dart';
import '../utils/health_metrics.dart';

class WeekTotals {
  final int activeDays;
  final int sessions;
  final int minutes;
  final int checkins;
  final double? avgSleepQuality;
  final double? avgWellbeing;

  const WeekTotals({
    this.activeDays = 0,
    this.sessions = 0,
    this.minutes = 0,
    this.checkins = 0,
    this.avgSleepQuality,
    this.avgWellbeing,
  });

  bool get isEmpty => sessions == 0 && checkins == 0 && avgSleepQuality == null;
}

class WeeklySummary {
  final WeekTotals thisWeek;
  final WeekTotals lastWeek;
  final String headline;

  const WeeklySummary(this.thisWeek, this.lastWeek, this.headline);

  /// Minutes more (positive) or fewer than last week.
  int get minutesDelta => thisWeek.minutes - lastWeek.minutes;

  bool get hasAnyData => !thisWeek.isEmpty || !lastWeek.isEmpty;

  static WeeklySummary compute({
    required List<WellnessSession> sessions,
    required List<CheckinEntry> checkins,
    required List<SleepEntry> sleep,
    required DateTime now,
    int variant = 0,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final thisStart = today.subtract(const Duration(days: 6));
    final lastStart = today.subtract(const Duration(days: 13));
    final end = today.add(const Duration(days: 1));

    WeekTotals totals(DateTime from, DateTime to) {
      bool within(DateTime d) => !d.isBefore(from) && d.isBefore(to);
      final s = sessions.where((x) => within(x.date)).toList();
      final c = checkins.where((x) => within(x.time)).toList();
      final sl = sleep.where((x) => !x.isNap && within(x.date)).toList();
      return WeekTotals(
        activeDays: s.map((x) => dayKey(x.date)).toSet().length,
        sessions: s.length,
        minutes: s.fold(0, (a, x) => a + x.durationMinutes),
        checkins: c.length,
        avgSleepQuality: sl.isEmpty
            ? null
            : sl.map((x) => x.quality).reduce((a, b) => a + b) / sl.length,
        avgWellbeing: c.isEmpty
            ? null
            : c.map((x) => x.wellbeingScore).reduce((a, b) => a + b) / c.length,
      );
    }

    final thisWeek = totals(thisStart, end);
    final lastWeek = totals(lastStart, thisStart);
    return WeeklySummary(
        thisWeek, lastWeek, _headline(thisWeek, lastWeek, variant));
  }

  static String _pick(List<String> options, int variant) =>
      options[variant.abs() % options.length];

  static String _headline(WeekTotals t, WeekTotals l, int variant) {
    if (t.isEmpty && l.isEmpty) {
      return 'Your week will take shape as you log things.';
    }
    if (t.isEmpty) {
      return _pick(const [
        'A fresh week is waiting. Any small session is a lovely start.',
        'New week, clean slate. Start whenever it suits you.',
      ], variant);
    }
    final active = t.activeDays;
    if (active >= 5) {
      return _pick([
        'You showed up on $active of 7 days. That is a real rhythm.',
        '$active active days this week. Look at you go.',
        'A steady week: $active days of caring for yourself.',
      ], variant);
    }
    if (t.minutes > l.minutes && l.minutes > 0) {
      return _pick([
        'You did ${t.minutes - l.minutes} more minutes than last week. Nice.',
        'A little more than last week, and every minute counts.',
      ], variant);
    }
    if (active >= 1) {
      return _pick([
        'You were active on $active ${active == 1 ? 'day' : 'days'}. '
            'Gentle and steady wins.',
        'A calmer week, and that is perfectly fine. $active '
            '${active == 1 ? 'day' : 'days'} counted.',
        'Every session matters. This week you had ${t.sessions}.',
      ], variant);
    }
    return _pick(const [
      'You checked in this week. Noticing how you feel counts.',
      'Logging is a practice too. Nice work keeping track.',
    ], variant);
  }
}
