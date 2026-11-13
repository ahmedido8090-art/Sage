import 'package:flutter_test/flutter_test.dart';
import 'package:sage/notifications/notification_category.dart';
import 'package:sage/notifications/notification_prefs.dart';
import 'package:sage/notifications/schedule_planner.dart';

void main() {
  // A Tuesday morning, before any of the default times.
  final now = DateTime(2026, 3, 10, 7, 45);
  const on = NotificationPrefs(enabled: true);

  PlanResult plan(NotificationPrefs prefs,
          {TodayState today = const TodayState(),
          DateTime? at,
          int days = 7}) =>
      SchedulePlanner.plan(
          prefs: prefs, now: at ?? now, today: today, days: days);

  test('plans nothing while notifications are off', () {
    expect(plan(const NotificationPrefs()).notifications, isEmpty);
  });

  test('only plans categories the user turned on', () {
    final prefs = on.copyWith(categories: {NotificationCategory.hydration});
    final result = plan(prefs);
    expect(result.notifications, isNotEmpty);
    expect(result.notifications.map((n) => n.category).toSet(),
        {NotificationCategory.hydration});
  });

  test('everything is in the future', () {
    for (final n in plan(on).notifications) {
      expect(n.at.isAfter(now), isTrue);
    }
  });

  test('nothing lands inside quiet hours, including wrap past midnight', () {
    // Quiet 09:00-23:00 (daytime) would swallow every default time.
    final daytime =
        on.copyWith(quietStartMinutes: 9 * 60, quietEndMinutes: 23 * 60);
    expect(plan(daytime).notifications, isEmpty);

    // Default quiet 22:00-07:30 keeps the 21:30 wind-down.
    final result = plan(on);
    for (final n in result.notifications) {
      expect(on.isQuiet(n.at.hour * 60 + n.at.minute), isFalse);
    }
    expect(
        result.notifications
            .any((n) => n.category == NotificationCategory.sleep),
        isTrue);
  });

  test('isQuiet handles windows that wrap midnight', () {
    const prefs =
        NotificationPrefs(quietStartMinutes: 22 * 60, quietEndMinutes: 7 * 60);
    expect(prefs.isQuiet(23 * 60), isTrue);
    expect(prefs.isQuiet(2 * 60), isTrue);
    expect(prefs.isQuiet(7 * 60), isFalse);
    expect(prefs.isQuiet(12 * 60), isFalse);
    expect(
        const NotificationPrefs(quietStartMinutes: 0, quietEndMinutes: 0)
            .isQuiet(3 * 60),
        isFalse);
  });

  test('never more than the daily cap, and spaced apart', () {
    final result = plan(on);
    final byDay = <int, List<PlannedNotification>>{};
    for (final n in result.notifications) {
      byDay.putIfAbsent(n.at.day, () => []).add(n);
    }
    for (final list in byDay.values) {
      expect(list.length, lessThanOrEqualTo(SchedulePlanner.maxPerDay));
      list.sort((a, b) => a.at.compareTo(b.at));
      for (var i = 1; i < list.length; i++) {
        expect(list[i].at.difference(list[i - 1].at),
            greaterThanOrEqualTo(SchedulePlanner.minGap));
      }
    }
  });

  test('skips what today already covers', () {
    final done = plan(
      on,
      today: const TodayState(
          waterGoalMet: true,
          movedToday: true,
          checkedInToday: true,
          streakDays: 5),
    );
    final todays =
        done.notifications.where((n) => n.at.day == now.day).toList();
    expect(todays.map((n) => n.category).toSet(),
        {NotificationCategory.sleep}); // wind-down still welcome
    // Tomorrow is a fresh day: everything is back.
    final tomorrow =
        done.notifications.where((n) => n.at.day == now.day + 1).toList();
    expect(tomorrow.map((n) => n.category).toSet().length, greaterThan(2));
  });

  test('a streak cheer only appears today when there is a streak to cheer', () {
    final none = plan(on, today: const TodayState(streakDays: 0));
    expect(
        none.notifications.any((n) =>
            n.category == NotificationCategory.streak && n.at.day == now.day),
        isFalse);

    final active =
        plan(on, today: const TodayState(streakDays: 6, name: 'Ana'));
    final todaysStreak = active.notifications.firstWhere((n) =>
        n.category == NotificationCategory.streak && n.at.day == now.day);
    expect(todaysStreak.message.title + todaysStreak.message.body,
        isNot(contains('{')));
  });

  test('future streak cheers never invent a streak number', () {
    final result = plan(on, today: const TodayState(streakDays: 9));
    final future = result.notifications.where((n) =>
        n.category == NotificationCategory.streak && n.at.day != now.day);
    expect(future, isNotEmpty);
    for (final n in future) {
      expect(n.message.title + n.message.body, isNot(contains('9')));
    }
  });

  test('no unfilled placeholders anywhere', () {
    final result =
        plan(on, today: const TodayState(streakDays: 3, name: 'Sam'), days: 14);
    for (final n in result.notifications) {
      expect('${n.message.title} ${n.message.body}', isNot(contains('{')));
    }
  });

  test('ids are unique', () {
    final ids = plan(on, days: 14).notifications.map((n) => n.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('cursors advance so tomorrow\'s copy differs from today\'s', () {
    final first = plan(on);
    expect(first.cursors['hydration'], greaterThan(0));

    final hydration = first.notifications
        .where((n) => n.category == NotificationCategory.hydration)
        .map((n) => n.message.title)
        .toList();
    for (var i = 1; i < hydration.length; i++) {
      expect(hydration[i], isNot(hydration[i - 1]));
    }

    // Planning again with saved cursors continues the rotation rather than
    // restarting it.
    final second = plan(on.copyWith(messageCursors: first.cursors));
    final secondFirst = second.notifications
        .firstWhere((n) => n.category == NotificationCategory.hydration);
    expect(secondFirst.message.title, isNot(hydration.last));
  });

  test('prefs round-trip through a map', () {
    final prefs = on.copyWith(
      categories: {NotificationCategory.sleep, NotificationCategory.checkin},
      quietStartMinutes: 23 * 60,
      quietEndMinutes: 6 * 60,
      messageCursors: {'sleep': 4},
      promptDismissed: true,
    );
    final restored = NotificationPrefs.fromMap(prefs.toMap());
    expect(restored.enabled, isTrue);
    expect(restored.categories, prefs.categories);
    expect(restored.quietStartMinutes, 23 * 60);
    expect(restored.messageCursors['sleep'], 4);
    expect(restored.promptDismissed, isTrue);
  });
}
