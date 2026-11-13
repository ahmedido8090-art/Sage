import 'package:flutter_test/flutter_test.dart';
import 'package:sage/band/step_tally.dart';

void main() {
  final day = DateTime(2026, 3, 10, 9);
  DateTime at(int h, [int m = 0, int d = 0]) => DateTime(2026, 3, 10 + d, h, m);

  test('is unknown until the band reports', () {
    expect(StepTally().today, isNull);
    expect(StepTally().deviceCounter, isNull);
  });

  test('the first reading is a baseline, not a pile of steps', () {
    final t = StepTally()..add(48000, day);
    expect(t.today, 0);
    expect(t.deviceCounter, 48000);
  });

  test('counts the growth in the counter', () {
    final t = StepTally()
      ..add(1000, at(9))
      ..add(1400, at(10))
      ..add(2600, at(12));
    expect(t.today, 1600);
  });

  test('a counter reset counts the new steps from zero', () {
    final t = StepTally()
      ..add(5000, at(9))
      ..add(5300, at(10))
      ..add(120, at(11)) // band was switched off and on
      ..add(420, at(12));
    expect(t.today, 300 + 120 + 300);
  });

  test('ignores nonsense readings', () {
    final t = StepTally()
      ..add(100, at(9))
      ..add(-5, at(10))
      ..add(160, at(11));
    expect(t.today, 60);
  });

  test('a new day starts from zero and carries the counter over', () {
    final t = StepTally()
      ..add(1000, at(21))
      ..add(1800, at(23, 30))
      ..add(1850, at(7, 0, 1));
    expect(t.today, 50); // only the steps taken after midnight
    expect(t.deviceCounter, 1850);
  });

  group('fromHistory', () {
    test('rebuilds today from stored readings', () {
      final t = StepTally.fromHistory([
        StepReading(900, at(8)),
        StepReading(1500, at(10)),
        StepReading(2100, at(13)),
      ], now: at(14));
      expect(t.today, 1200);
    });

    test('readings from yesterday do not count as today', () {
      final t = StepTally.fromHistory([
        StepReading(900, at(20, 0, -1)),
        StepReading(1500, at(22, 0, -1)),
      ], now: at(8));
      expect(t.today, isNull);
      expect(t.deviceCounter, 1500);
    });

    test('is order independent', () {
      final t = StepTally.fromHistory([
        StepReading(2100, at(13)),
        StepReading(900, at(8)),
        StepReading(1500, at(10)),
      ], now: at(14));
      expect(t.today, 1200);
    });
  });
}
