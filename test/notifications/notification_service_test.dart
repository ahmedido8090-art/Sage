import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sage/models/bella_data.dart';
import 'package:sage/models/user.dart';
import 'package:sage/notifications/notification_prefs.dart';
import 'package:sage/notifications/message_bank.dart';
import 'package:sage/notifications/notification_category.dart';
import 'package:sage/notifications/notification_gateway.dart';
import 'package:sage/notifications/notification_service.dart';
import 'package:sage/notifications/schedule_planner.dart';
import 'package:sage/services/bella_service.dart';
import 'package:sage/services/user_service.dart';

class FakeGateway implements NotificationGateway {
  NotificationPermission granted = NotificationPermission.granted;
  final List<PlannedNotification> scheduled = [];
  int cancelCalls = 0;
  int tests = 0;
  void Function(String?)? onTap;

  @override
  Future<void> init({required void Function(String? payload) onTap}) async =>
      this.onTap = onTap;
  @override
  Future<String?> launchPayload() async => null;
  @override
  Future<NotificationPermission> permission() async => granted;
  @override
  Future<NotificationPermission> requestPermission() async => granted;
  @override
  Future<void> schedule(PlannedNotification n) async => scheduled.add(n);
  @override
  Future<void> showNow(NotificationCategory c, NotificationMessage m) async =>
      tests++;
  @override
  Future<void> cancelAll() async {
    cancelCalls++;
    scheduled.clear();
  }

  @override
  Future<int> pendingCount() async => scheduled.length;
}

void main() {
  late Directory dir;
  late UserService users;
  late FakeGateway gateway;
  late NotificationService service;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sage_notif_');
    Hive.init(dir.path);
    await Hive.openBox('users');
    await Hive.openBox('userDetails');
    await Hive.openBox('session');
    await BellaService.openBox();
    users = UserService();
    for (final name in ['ana', 'ben']) {
      users.register(
          User(username: name, age: 30, gender: 'F', height: 170, weight: 65),
          'p');
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async {
    users.logout();
    users.authenticate('ana', 'p');
    gateway = FakeGateway();
    service = NotificationService(gateway: gateway);
    await service.init();
    await service.savePrefs(const NotificationPrefs());
  });

  test('nothing is scheduled until the user opts in', () async {
    await service.refresh();
    expect(gateway.scheduled, isEmpty);
    expect(service.prefs.enabled, isFalse);
  });

  test('enabling with permission schedules a week of nudges', () async {
    expect(await service.enable(), isTrue);
    expect(service.prefs.enabled, isTrue);
    expect(gateway.scheduled, isNotEmpty);
    expect(
        gateway.scheduled.every((n) => n.at.isAfter(DateTime.now())), isTrue);
  });

  test('denied permission leaves everything off', () async {
    gateway.granted = NotificationPermission.notGranted;
    expect(await service.enable(), isFalse);
    expect(service.prefs.enabled, isFalse);
    expect(gateway.scheduled, isEmpty);
  });

  test('refreshing twice does not duplicate (it rebuilds from scratch)',
      () async {
    await service.enable();
    final first = gateway.scheduled.length;
    await service.refresh();
    await service.refresh();
    expect(gateway.scheduled.length, first);
  });

  test('concurrent refreshes are serialised', () async {
    await service.enable();
    final first = gateway.scheduled.length;
    await Future.wait([for (var i = 0; i < 5; i++) service.refresh()]);
    expect(gateway.scheduled.length, first);
  });

  test('turning a category off removes it from the schedule', () async {
    await service.enable();
    final without = service.prefs.categories
        .where((c) => c != NotificationCategory.hydration)
        .toSet();
    await service.savePrefs(service.prefs.copyWith(categories: without));
    expect(
        gateway.scheduled
            .any((n) => n.category == NotificationCategory.hydration),
        isFalse);
    expect(gateway.scheduled, isNotEmpty);
  });

  test('disabling cancels everything', () async {
    await service.enable();
    await service.disable();
    expect(gateway.scheduled, isEmpty);
  });

  test('signing out cancels and a different user starts from their own choices',
      () async {
    await service.enable();
    users.logout();
    await service.refresh();
    expect(gateway.scheduled, isEmpty);

    users.authenticate('ben', 'p');
    expect(service.prefs.enabled, isFalse);
    await service.refresh();
    expect(gateway.scheduled, isEmpty);
  });

  test('rotation continues across rebuilds', () async {
    await service.enable();
    final cursor = service.prefs.messageCursors['hydration'] ?? 0;
    await service.refresh();
    expect(service.prefs.messageCursors['hydration'],
        greaterThanOrEqualTo(cursor));
  });

  test('already-done activity today is not nudged about', () async {
    await BellaService().addCheckin(
        CheckinEntry(time: DateTime.now(), mood: 4, stress: 2, energy: 4));
    await service.enable();
    final now = DateTime.now();
    expect(
        gateway.scheduled.any((n) =>
            n.category == NotificationCategory.checkin && n.at.day == now.day),
        isFalse);
  });

  test('tapping a notification publishes its category', () async {
    gateway.onTap!('sleep');
    expect(service.tapped.value, NotificationCategory.sleep);
    gateway.onTap!('nonsense');
    expect(service.tapped.value, NotificationCategory.sleep);
  });

  test('send a test goes through the gateway', () async {
    await service.sendTest();
    expect(gateway.tests, 1);
  });
}
