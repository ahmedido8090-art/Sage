import 'package:flutter_test/flutter_test.dart';
import 'package:sage/models/bella_data.dart';
import 'package:sage/services/weekly_summary.dart';

void main() {
  final now = DateTime(2026, 3, 10, 20);
  DateTime day(int offset, [int h = 9]) => DateTime(2026, 3, 10 + offset, h);
  WellnessSession s(int offset, int min, {String type = 'walking'}) =>
      WellnessSession(type: type, date: day(offset), durationMinutes: min);

  WeeklySummary run({
    List<WellnessSession> sessions = const [],
    List<CheckinEntry> checkins = const [],
    List<SleepEntry> sleep = const [],
    int variant = 0,
  }) =>
      WeeklySummary.compute(
          sessions: sessions,
          checkins: checkins,
          sleep: sleep,
          now: now,
          variant: variant);

  test('no data at all is calm and has nothing to compare', () {
    final w = run();
    expect(w.hasAnyData, isFalse);
    expect(w.thisWeek.isEmpty, isTrue);
    expect(w.headline, isNotEmpty);
  });

  test('splits the last 14 days into this week and the one before', () {
    final w = run(sessions: [
      s(0, 20), s(-3, 10), s(-6, 30), // this week: days 0..-6
      s(-7, 15), s(-13, 25), // last week
      s(-14, 99), // too old
    ]);
    expect(w.thisWeek.sessions, 3);
    expect(w.thisWeek.minutes, 60);
    expect(w.lastWeek.sessions, 2);
    expect(w.lastWeek.minutes, 40);
    expect(w.minutesDelta, 20);
  });

  test('active days count each calendar day once', () {
    final w = run(sessions: [s(0, 10), s(0, 20, type: 'meditation'), s(-1, 5)]);
    expect(w.thisWeek.activeDays, 2);
    expect(w.thisWeek.sessions, 3);
  });

  test('sleep average ignores naps and other weeks', () {
    final w = run(sleep: [
      SleepEntry(id: 'a', date: day(0), quality: 4),
      SleepEntry(id: 'b', date: day(-1), quality: 2),
      SleepEntry(id: 'n', date: day(-1), quality: 1, isNap: true),
      SleepEntry(id: 'c', date: day(-9), quality: 5),
    ]);
    expect(w.thisWeek.avgSleepQuality, 3.0);
    expect(w.lastWeek.avgSleepQuality, 5.0);
  });

  test('check-ins are counted with their average wellbeing', () {
    final w = run(checkins: [
      CheckinEntry(time: day(0), mood: 5, stress: 1, energy: 5),
      CheckinEntry(time: day(-2), mood: 3, stress: 3, energy: 3),
    ]);
    expect(w.thisWeek.checkins, 2);
    expect(w.thisWeek.avgWellbeing, isNotNull);
  });

  group('headline', () {
    const guilt = [
      'lazy',
      'fail',
      'disappoint',
      'you missed',
      'you forgot',
      'should have',
      'behind',
      'give up',
      'shame',
      'guilt',
      'neglect',
      'only ',
      'just ',
      'worse',
      'fell',
      'dropped',
      'slacked',
    ];

    test('is encouraging in every situation, including a quiet week', () {
      final situations = <WeeklySummary Function(int)>[
        (v) => run(variant: v),
        (v) => run(sessions: [s(-8, 30)], variant: v), // nothing this week
        (v) =>
            run(sessions: [s(0, 5), s(-8, 60)], variant: v), // less than last
        (v) => run(sessions: [s(0, 50), s(-8, 10)], variant: v), // more
        (v) =>
            run(sessions: [for (var i = 0; i < 6; i++) s(-i, 10)], variant: v),
        (v) => run(checkins: [
              CheckinEntry(time: day(0), mood: 3, stress: 3, energy: 3)
            ], variant: v),
      ];
      for (final make in situations) {
        for (var v = 0; v < 4; v++) {
          final text = make(v).headline.toLowerCase();
          for (final w in guilt) {
            expect(text.contains(w), isFalse, reason: '"$w" in "$text"');
          }
          expect(text.length, lessThanOrEqualTo(95), reason: text);
        }
      }
    });

    test('varies with the variant', () {
      final lines = {
        for (var v = 0; v < 3; v++)
          run(sessions: [for (var i = 0; i < 6; i++) s(-i, 10)], variant: v)
              .headline,
      };
      expect(lines.length, greaterThan(1));
    });

    test('fills in real numbers', () {
      final w = run(sessions: [for (var i = 0; i < 6; i++) s(-i, 10)]);
      expect(w.headline, contains('6'));
      expect(w.headline, isNot(contains(r'$')));
    });
  });
}
