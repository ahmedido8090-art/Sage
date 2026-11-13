import 'package:flutter_test/flutter_test.dart';
import 'package:sage/band/band_history.dart';

void main() {
  final now = DateTime(2026, 3, 10, 18);
  DateTime at(int dayOffset, int h, [int m = 0]) =>
      DateTime(2026, 3, 10 + dayOffset, h, m);
  BandReading r(DateTime t, {int hr = 70, int steps = 0}) =>
      BandReading(heartRate: hr, steps: steps, at: t);

  test('returns one entry per day, oldest first, ending today', () {
    final days = BandHistory.compute(const [], now: now, days: 7);
    expect(days, hasLength(7));
    expect(days.last.day, DateTime(2026, 3, 10));
    expect(days.first.day, DateTime(2026, 3, 4));
    expect(days.every((d) => !d.hasData), isTrue);
  });

  test('days without readings are gaps, not zeros', () {
    final days = BandHistory.compute(
        [r(at(0, 9), steps: 100), r(at(0, 12), steps: 600)],
        now: now);
    final quiet = days.firstWhere((d) => d.day.day == 8);
    expect(quiet.steps, isNull);
    expect(quiet.avgHeartRate, isNull);
    expect(quiet.readings, 0);
  });

  test('steps per day come from growth in the counter', () {
    final days = BandHistory.compute([
      r(at(-1, 9), steps: 1000),
      r(at(-1, 20), steps: 4000),
      r(at(0, 8), steps: 4200),
      r(at(0, 15), steps: 7000),
    ], now: now);
    expect(days[5].steps, 3000); // yesterday
    expect(days[6].steps,
        3000); // today: 4000 -> 7000 (the 200 overnight is today's)
  });

  test('a single reading is a baseline, not a day total', () {
    final days = BandHistory.compute([r(at(0, 9), steps: 5000)], now: now);
    expect(days.last.steps, isNull);
    expect(days.last.readings, 1);
  });

  test('a counter reset does not produce a negative day', () {
    final days = BandHistory.compute([
      r(at(0, 8), steps: 9000),
      r(at(0, 10), steps: 9500),
      r(at(0, 12), steps: 200), // band switched off and on
      r(at(0, 14), steps: 700),
    ], now: now);
    expect(days.last.steps, 500 + 200 + 500);
  });

  test('heart rate range and average ignore 0 readings', () {
    final days = BandHistory.compute([
      r(at(0, 8), hr: 60),
      r(at(0, 9), hr: 0),
      r(at(0, 10), hr: 100),
      r(at(0, 11), hr: 80),
    ], now: now);
    final d = days.last;
    expect(d.minHeartRate, 60);
    expect(d.maxHeartRate, 100);
    expect(d.avgHeartRate, 80);
  });

  test('readings outside the window are ignored', () {
    final days = BandHistory.compute(
        [r(at(-30, 9), hr: 90, steps: 100), r(at(-30, 10), hr: 90, steps: 900)],
        now: now);
    expect(days.every((d) => !d.hasData), isTrue);
  });

  test('averageSteps skips gap days', () {
    final days = BandHistory.compute([
      r(at(-2, 9), steps: 1000),
      r(at(-2, 18), steps: 3000),
      r(at(0, 9), steps: 3100),
      r(at(0, 18), steps: 4100),
    ], now: now);
    // Day -2: 3000-1000 = 2000. Today: 100 carried over from overnight plus
    // 1000 = 1100. Average of the two days that have a total.
    expect(BandHistory.averageSteps(days), 1550);
    expect(BandHistory.averageSteps(BandHistory.compute(const [], now: now)),
        isNull);
  });

  group('todaySeries', () {
    test('only today, only real heart rates', () {
      final series = BandHistory.todaySeries([
        r(at(-1, 23), hr: 55),
        r(at(0, 8), hr: 0),
        r(at(0, 9), hr: 70),
        r(at(0, 10), hr: 75),
      ], now: now);
      expect(series.map((p) => p.bpm), [70, 75]);
    });

    test('long days are downsampled but keep their shape', () {
      final readings = [
        for (var i = 0; i < 600; i++)
          r(DateTime(2026, 3, 10, 6).add(Duration(seconds: i * 60)),
              hr: 60 + (i ~/ 100) * 10),
      ];
      final series = BandHistory.todaySeries(readings, now: now, maxPoints: 40);
      expect(series.length, lessThanOrEqualTo(40));
      expect(series.first.bpm, lessThan(series.last.bpm));
      for (var i = 1; i < series.length; i++) {
        expect(series[i].at.isAfter(series[i - 1].at), isTrue);
      }
    });
  });
}
