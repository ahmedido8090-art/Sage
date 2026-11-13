import 'package:flutter_test/flutter_test.dart';
import 'package:sage/utils/health_metrics.dart';

void main() {
  final today = DateTime(2026, 3, 10, 14);
  String daysAgo(int n) => dayKey(today.subtract(Duration(days: n)));

  test('bmiCategory uses WHO bands', () {
    expect(bmiCategory(18.4), 'Underweight');
    expect(bmiCategory(18.5), 'Normal');
    expect(bmiCategory(25), 'Overweight');
    expect(bmiCategory(30), 'Obese');
  });

  test('dayKey is zero padded', () {
    expect(dayKey(DateTime(2026, 3, 7)), '2026-03-07');
  });

  group('streakEndingToday', () {
    test('is zero with no activity', () {
      expect(streakEndingToday({}, now: today), 0);
    });

    test('counts consecutive days including today', () {
      final days = {daysAgo(0), daysAgo(1), daysAgo(2)};
      expect(streakEndingToday(days, now: today), 3);
    });

    test('still counts from yesterday when nothing is logged yet today', () {
      final days = {daysAgo(1), daysAgo(2)};
      expect(streakEndingToday(days, now: today), 2);
    });

    test('a gap ends the streak', () {
      final days = {daysAgo(0), daysAgo(2), daysAgo(3)};
      expect(streakEndingToday(days, now: today), 1);
    });

    test('two quiet days reset it', () {
      expect(streakEndingToday({daysAgo(2), daysAgo(3)}, now: today), 0);
    });
  });
}
