// band/step_tally.dart
//
// Turns the band's raw step counter into "steps today". The band reports a
// running total that does not reset on its own schedule (or may reset when it
// is switched off), so today's steps are the sum of positive changes since
// midnight, with a counter reset counted as new steps from zero.
//
// Pure and I/O-free so the tricky cases are testable.
class StepReading {
  final int steps;
  final DateTime at;
  const StepReading(this.steps, this.at);
}

class StepTally {
  StepTally();

  int? _previous;
  DateTime? _day;
  int _total = 0;
  bool _hasToday = false;

  /// Steps taken today, or null until the band has reported something today.
  int? get today => _hasToday ? _total : null;

  /// The band's latest raw counter, or null if none seen.
  int? get deviceCounter => _previous;

  /// Replays stored readings (oldest first) to rebuild today's total after a
  /// restart.
  factory StepTally.fromHistory(List<StepReading> readings, {DateTime? now}) {
    final tally = StepTally();
    final sorted = [...readings]..sort((a, b) => a.at.compareTo(b.at));
    for (final r in sorted) {
      tally.add(r.steps, r.at);
    }
    // History may end yesterday: today has nothing yet.
    final today = now ?? DateTime.now();
    if (tally._day != null && !_sameDay(tally._day!, today)) {
      tally._startNewDay(today);
    }
    return tally;
  }

  void add(int counter, DateTime at) {
    if (counter < 0) return;
    if (_day == null) {
      // The first reading ever is a baseline: steps before it are unknown.
      _day = at;
      _previous = counter;
      _hasToday = true;
      _total = 0;
      return;
    }
    if (!_sameDay(_day!, at)) _startNewDay(at);

    final prev = _previous!;
    if (counter >= prev) {
      _total += counter - prev;
    } else {
      // The counter went backwards: the band was reset, so everything it now
      // shows is new.
      _total += counter;
    }
    _previous = counter;
    _hasToday = true;
  }

  void _startNewDay(DateTime at) {
    _day = at;
    _total = 0;
    _hasToday = false;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
