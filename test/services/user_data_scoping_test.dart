import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sage/models/bella_data.dart';
import 'package:sage/models/user.dart';
import 'package:sage/services/bella_service.dart';
import 'package:sage/services/data_storage_service.dart';
import 'package:sage/services/user_service.dart';

User _profile(String name) => User(
      username: name,
      age: 30,
      gender: 'F',
      height: 170,
      weight: 65,
    );

void main() {
  late Directory dir;
  late UserService users;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sage_test_');
    Hive.init(dir.path);
    await Hive.openBox('users');
    await Hive.openBox('userDetails');
    await Hive.openBox('session');
    await BellaService.openBox();
    users = UserService();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    users.logout();
  });

  group('accounts', () {
    test('passwords are stored hashed, never as plaintext', () {
      users.register(_profile('ana'), 'secret-pass');
      final stored = Hive.box('users').get('ana') as String;
      expect(stored, isNot('secret-pass'));
      expect(users.authenticate('ana', 'secret-pass'), isNull);
      expect(users.authenticate('ana', 'wrong'), 'Incorrect password');
      expect(Hive.box('userDetails').get('ana').toString(),
          isNot(contains('secret-pass')));
    });

    test('duplicate usernames are rejected', () {
      users.register(_profile('dup'), 'a');
      expect(users.register(_profile('dup'), 'b'), 'Username already exists');
    });

    test('legacy plaintext accounts are migrated and still sign in', () async {
      Hive.box('users').put('old', 'plainpw');
      Hive.box('userDetails').put('old', {
        ..._profile('old').toMap(),
        'password': 'plainpw',
      });

      await users.migrateLegacyCredentials();

      expect(Hive.box('users').get('old'), isNot('plainpw'));
      expect(Hive.box('userDetails').get('old'), isNot(contains('password')));
      expect(users.authenticate('old', 'plainpw'), isNull);
    });
  });

  group('per-user data', () {
    test('band data is not shared between accounts', () async {
      users.register(_profile('u1'), 'p');
      users.register(_profile('u2'), 'p');
      final storage = DataStorageService();

      users.authenticate('u1', 'p');
      await storage.saveBandData(
          heartRate: 70, steps: 10, timestamp: DateTime.now());

      users.authenticate('u2', 'p');
      expect(await storage.getBandData(daysBack: 1), isEmpty);

      users.authenticate('u1', 'p');
      expect(await storage.getBandData(daysBack: 1), hasLength(1));
    });

    test('band data written with nobody signed in is dropped', () async {
      final storage = DataStorageService();
      await storage.saveBandData(
          heartRate: 70, steps: 10, timestamp: DateTime.now());
      users.register(_profile('late'), 'p');
      users.authenticate('late', 'p');
      expect(await storage.getBandData(daysBack: 1), isEmpty);
    });

    test('legacy global band data is adopted by the first user, once',
        () async {
      SharedPreferences.setMockInitialValues({
        'sage_band_data': [
          '{"hr":"60","steps":"5","time":"${DateTime.now().millisecondsSinceEpoch}"}'
        ],
      });
      users.register(_profile('first'), 'p');
      users.register(_profile('second'), 'p');
      final storage = DataStorageService();

      users.authenticate('first', 'p');
      expect(await storage.getBandData(daysBack: 1), hasLength(1));

      users.authenticate('second', 'p');
      expect(await storage.getBandData(daysBack: 1), isEmpty);
    });

    test('Bella data is isolated and nothing is stored without a user',
        () async {
      users.register(_profile('b1'), 'p');
      users.register(_profile('b2'), 'p');
      final bella = BellaService();

      await bella.addWater(250); // nobody signed in: dropped
      users.authenticate('b1', 'p');
      expect(bella.todayWaterMl(), 0);

      await bella.addWater(300);
      users.authenticate('b2', 'p');
      expect(bella.todayWaterMl(), 0);

      users.authenticate('b1', 'p');
      expect(bella.todayWaterMl(), 300);
    });

    test('rapid writes are all kept', () async {
      users.register(_profile('fast'), 'p');
      users.authenticate('fast', 'p');
      final bella = BellaService();

      await Future.wait([
        for (var i = 0; i < 20; i++) bella.addWater(100),
      ]);
      expect(bella.todayWaterMl(), 2000);
    });

    test('simultaneous achievement unlocks are all recorded', () async {
      users.register(_profile('ach'), 'p');
      users.authenticate('ach', 'p');
      final bella = BellaService();

      await bella.recordAchievementUnlocks({
        'a': DateTime(2026, 1, 1),
        'b': DateTime(2026, 1, 2),
        'c': DateTime(2026, 1, 3),
      });
      await bella.recordAchievementUnlocks({'a': DateTime(2026, 6, 1)});

      final unlocks = bella.getAchievementUnlocks();
      expect(unlocks.keys.toSet(), {'a', 'b', 'c'});
      expect(unlocks['a'], DateTime(2026, 1, 1)); // first date is kept
    });

    test('reset clears only my logs, keeps goals, and tells listeners',
        () async {
      users.register(_profile('r1'), 'p');
      users.register(_profile('r2'), 'p');
      final bella = BellaService();

      users.authenticate('r2', 'p');
      await bella.addWater(400);

      users.authenticate('r1', 'p');
      await bella.addWater(300);
      await bella.logSession('walking', 20);
      await bella.addCheckin(
          CheckinEntry(time: DateTime.now(), mood: 4, stress: 2, energy: 4));
      await bella.setTarget('waterMl', 2600);

      var notified = 0;
      void onChange() => notified++;
      BellaUserData.dataVersion.addListener(onChange);
      await bella.clearLoggedData();
      BellaUserData.dataVersion.removeListener(onChange);

      expect(bella.todayWaterMl(), 0);
      expect(bella.getSessions(), isEmpty);
      expect(bella.getCheckins(), isEmpty);
      expect(bella.getTarget<int>('waterMl'), 2600); // goals stay
      expect(notified, 1);

      users.authenticate('r2', 'p');
      expect(bella.todayWaterMl(), 400); // someone else's data is untouched
    });

    test('export contains what was logged and never a password', () async {
      users.register(_profile('exp'), 'sup3r-secret');
      users.authenticate('exp', 'sup3r-secret');
      final bella = BellaService();
      await bella.addWater(500);
      await bella.logSession('breathwork', 7);

      final data = bella.exportAll();
      expect((data['water'] as List), hasLength(1));
      expect((data['sessions'] as List), hasLength(1));
      expect(data.toString(), isNot(contains('sup3r-secret')));
      expect(data.containsKey('password'), isFalse);
    });
  });
}
