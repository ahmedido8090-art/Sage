// Prints how long the read paths behind Insights/Wellness take with a
// realistic year of data. Not an assertion on speed, just a measurement to
// compare before/after performance work (run with `flutter test
// test/perf --reporter expanded`).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sage/models/bella_data.dart';
import 'package:sage/models/user.dart';
import 'package:sage/services/bella_service.dart';
import 'package:sage/services/user_service.dart';
import 'package:sage/services/wellness_score_service.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sage_perf_');
    Hive.init(dir.path);
    await Hive.openBox('users');
    await Hive.openBox('userDetails');
    await Hive.openBox('session');
    await BellaService.openBox();
    final users = UserService();
    users.register(
        User(username: 'perf', age: 30, gender: 'F', height: 170, weight: 65),
        'p');
    users.authenticate('perf', 'p');

    final bella = BellaService();
    final now = DateTime.now();
    for (var d = 0; d < 365; d++) {
      final day = now.subtract(Duration(days: d));
      for (final type in ['meditation', 'walking', 'breathwork']) {
        await bella.logSession(type, 10);
      }
      await bella.addWater(500);
      await bella.addFood(FoodEntry(time: day, description: 'meal $d'));
      await bella.addCheckin(
          CheckinEntry(time: day, mood: 3, stress: 3, energy: 3));
      await bella.saveSleepEntry(SleepEntry(
          id: 's$d',
          date: DateTime(day.year, day.month, day.day),
          quality: 4));
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('read path timings', () {
    final bella = BellaService();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 22; i++) {
      bella.getSessions();
    }
    final sessions = sw.elapsedMilliseconds;

    sw
      ..reset()
      ..start();
    WellnessScoreService.compute(bella: bella, chronicConditions: const []);
    WellnessScoreService.compute(
        bella: bella,
        chronicConditions: const [],
        asOf: DateTime.now().subtract(const Duration(days: 1)));
    final scores = sw.elapsedMilliseconds;

    sw
      ..reset()
      ..start();
    for (var i = 0; i < 10; i++) {
      bella.getSleepEntries();
      bella.getFoodEntries();
      bella.getCheckins();
      bella.getWaterEntries();
    }
    final others = sw.elapsedMilliseconds;

    // ignore: avoid_print
    print('BENCH getSessions x22: ${sessions}ms | '
        'score x2: ${scores}ms | sleep/food/checkin/water x10: ${others}ms');
  });
}
