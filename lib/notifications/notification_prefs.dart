// notifications/notification_prefs.dart
//
// A user's notification choices. Stored per user (see BellaService), so two
// people on one device each get their own reminders and quiet hours.
import 'notification_category.dart';

class NotificationPrefs {
  /// Master switch. Off until the user opts in and grants permission, so
  /// nothing is ever scheduled behind their back.
  final bool enabled;

  /// Categories the user wants. All on by default once notifications are on.
  final Set<NotificationCategory> categories;

  /// Quiet hours as minutes after midnight. The window may wrap past
  /// midnight (22:00 to 07:30).
  final int quietStartMinutes;
  final int quietEndMinutes;

  /// Position in each category's shuffled message order, so copy rotates
  /// across days and app restarts instead of repeating.
  final Map<String, int> messageCursors;

  /// The one-time "want gentle nudges?" card on Home has been answered.
  final bool promptDismissed;

  const NotificationPrefs({
    this.enabled = false,
    this.categories = const {
      NotificationCategory.hydration,
      NotificationCategory.movement,
      NotificationCategory.sleep,
      NotificationCategory.checkin,
      NotificationCategory.streak,
    },
    this.quietStartMinutes = 22 * 60,
    this.quietEndMinutes = 7 * 60 + 30,
    this.messageCursors = const {},
    this.promptDismissed = false,
  });

  bool isOn(NotificationCategory c) => enabled && categories.contains(c);

  /// Whether [minutesAfterMidnight] falls inside the quiet window.
  bool isQuiet(int minutesAfterMidnight) {
    final s = quietStartMinutes, e = quietEndMinutes;
    if (s == e) return false;
    return s < e
        ? minutesAfterMidnight >= s && minutesAfterMidnight < e
        : minutesAfterMidnight >= s || minutesAfterMidnight < e;
  }

  NotificationPrefs copyWith({
    bool? enabled,
    Set<NotificationCategory>? categories,
    int? quietStartMinutes,
    int? quietEndMinutes,
    Map<String, int>? messageCursors,
    bool? promptDismissed,
  }) =>
      NotificationPrefs(
        enabled: enabled ?? this.enabled,
        categories: categories ?? this.categories,
        quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
        quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
        messageCursors: messageCursors ?? this.messageCursors,
        promptDismissed: promptDismissed ?? this.promptDismissed,
      );

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'categories': categories.map((c) => c.id).toList(),
        'quietStart': quietStartMinutes,
        'quietEnd': quietEndMinutes,
        'cursors': messageCursors,
        'promptDismissed': promptDismissed,
      };

  factory NotificationPrefs.fromMap(Map<String, dynamic> map) {
    const defaults = NotificationPrefs();
    final rawCategories = map['categories'];
    return NotificationPrefs(
      enabled: map['enabled'] == true,
      categories: rawCategories is List
          ? rawCategories
              .map((e) => NotificationCategory.fromId(e?.toString()))
              .whereType<NotificationCategory>()
              .toSet()
          : defaults.categories,
      quietStartMinutes:
          (map['quietStart'] as num?)?.toInt() ?? defaults.quietStartMinutes,
      quietEndMinutes:
          (map['quietEnd'] as num?)?.toInt() ?? defaults.quietEndMinutes,
      messageCursors: {
        if (map['cursors'] is Map)
          for (final e in (map['cursors'] as Map).entries)
            e.key.toString(): (e.value as num).toInt(),
      },
      promptDismissed: map['promptDismissed'] == true,
    );
  }
}
