// notifications/schedule_planner.dart
//
// Decides what to schedule, with no I/O: given the user's choices, "now" and
// a snapshot of how today is going, returns the notifications for the next
// few days. Keeping this pure makes the rules (quiet hours, spacing, daily
// cap, message rotation) easy to test.
import 'message_bank.dart';
import 'notification_category.dart';
import 'notification_prefs.dart';

/// How today is going, so Sage does not nudge about things already done.
class TodayState {
  final bool waterGoalMet;
  final bool movedToday;

  /// Any wellness session today, which is what keeps a streak alive.
  final bool activeToday;
  final bool checkedInToday;
  final int streakDays;
  final String name;

  const TodayState({
    this.waterGoalMet = false,
    this.movedToday = false,
    this.activeToday = false,
    this.checkedInToday = false,
    this.streakDays = 0,
    this.name = 'friend',
  });
}

class PlannedNotification {
  final int id;
  final NotificationCategory category;
  final DateTime at;
  final NotificationMessage message;

  const PlannedNotification({
    required this.id,
    required this.category,
    required this.at,
    required this.message,
  });
}

class PlanResult {
  final List<PlannedNotification> notifications;

  /// Message cursors after planning, to be saved so copy keeps rotating.
  final Map<String, int> cursors;

  const PlanResult(this.notifications, this.cursors);
}

class SchedulePlanner {
  SchedulePlanner._();

  /// Never more than this many nudges in one day.
  static const int maxPerDay = 4;

  /// Nudges closer together than this are thinned out (lower priority loses).
  static const Duration minGap = Duration(minutes: 70);

  /// Skip anything due in the next minute so it cannot fire while the user is
  /// still changing a setting.
  static const Duration lead = Duration(minutes: 1);

  static PlanResult plan({
    required NotificationPrefs prefs,
    required DateTime now,
    required TodayState today,
    int days = 7,
  }) {
    final cursors = Map<String, int>.of(prefs.messageCursors);
    if (!prefs.enabled) return PlanResult(const [], cursors);

    final out = <PlannedNotification>[];
    final todayDate = DateTime(now.year, now.month, now.day);

    for (var d = 0; d < days; d++) {
      final date = DateTime(todayDate.year, todayDate.month, todayDate.day + d);
      final candidates = <_Candidate>[];

      for (final category in NotificationCategory.values) {
        if (!prefs.isOn(category)) continue;
        if (d == 0 && _alreadyDone(category, today)) continue;
        if (category == NotificationCategory.streak &&
            d == 0 &&
            today.streakDays < 2) {
          continue; // nothing to cheer about yet
        }

        for (final offset in category.defaultTimes) {
          final at = date.add(offset);
          if (!at.isAfter(now.add(lead))) continue;
          if (prefs.isQuiet(offset.inMinutes)) continue;
          candidates.add(_Candidate(category, at));
        }
      }

      candidates.sort((a, b) => a.at.compareTo(b.at));
      final kept = <_Candidate>[];
      for (final c in candidates) {
        if (kept.isNotEmpty && c.at.difference(kept.last.at) < minGap) {
          // Too close: keep whichever matters more.
          if (c.category.priority < kept.last.category.priority) {
            kept[kept.length - 1] = c;
          }
          continue;
        }
        kept.add(c);
      }
      // Over the daily cap: drop the least important first (later wins ties
      // for removal), so wind-down and check-in outlast a second water nudge.
      while (kept.length > maxPerDay) {
        var drop = 0;
        for (var i = 1; i < kept.length; i++) {
          final worse =
              kept[i].category.priority > kept[drop].category.priority;
          final tie = kept[i].category.priority == kept[drop].category.priority;
          if (worse || (tie && kept[i].at.isAfter(kept[drop].at))) drop = i;
        }
        kept.removeAt(drop);
      }

      for (final c in kept) {
        final key = c.category.id;
        final cursor = cursors[key] ?? 0;
        cursors[key] = cursor + 1;

        final useStreakCount = c.category == NotificationCategory.streak &&
            d == 0 &&
            today.streakDays >= 2;
        final message =
            c.category == NotificationCategory.streak && !useStreakCount
                ? MessageBank.pick(c.category, cursor,
                    pool: MessageBank.streakGeneric, seedSalt: 7)
                : MessageBank.pick(c.category, cursor);

        out.add(PlannedNotification(
          id: _idFor(d, c.category, c.at),
          category: c.category,
          at: c.at,
          message: MessageBank.fill(
            message,
            name: today.name,
            streak: useStreakCount ? today.streakDays : null,
          ),
        ));
      }
    }
    return PlanResult(out, cursors);
  }

  static bool _alreadyDone(NotificationCategory c, TodayState t) {
    switch (c) {
      case NotificationCategory.hydration:
        return t.waterGoalMet;
      case NotificationCategory.movement:
        return t.movedToday;
      case NotificationCategory.checkin:
        return t.checkedInToday;
      case NotificationCategory.streak:
        return t.activeToday || t.movedToday; // any activity keeps the streak
      case NotificationCategory.sleep:
        return false;
    }
  }

  /// Stable, collision-free id: day offset, category and time of day.
  static int _idFor(int dayOffset, NotificationCategory c, DateTime at) =>
      dayOffset * 10000 + c.index * 1000 + at.hour * 10 + (at.minute ~/ 6);
}

class _Candidate {
  final NotificationCategory category;
  final DateTime at;
  const _Candidate(this.category, this.at);
}
