// notifications/notification_category.dart
//
// The kinds of nudge Sage can send. Each one is its own Android channel, so
// the user can also fine-tune them from system settings.
import 'package:material_ui/material_ui.dart';

enum NotificationCategory {
  hydration(
    id: 'hydration',
    label: 'Hydration',
    description: 'Gentle reminders to sip some water',
    icon: Icons.water_drop_outlined,
    defaultTimes: [Duration(hours: 11), Duration(hours: 15)],
    priority: 3,
  ),
  movement(
    id: 'movement',
    label: 'Movement',
    description: 'A friendly nudge to stretch or take a walk',
    icon: Icons.directions_walk,
    defaultTimes: [Duration(hours: 16, minutes: 45)],
    priority: 4,
  ),
  sleep(
    id: 'sleep',
    label: 'Wind-down',
    description: 'An evening cue to start easing into sleep',
    icon: Icons.nights_stay_outlined,
    defaultTimes: [Duration(hours: 21, minutes: 30)],
    priority: 0,
  ),
  checkin(
    id: 'checkin',
    label: 'Daily check-in',
    description: 'A moment to notice how you are doing',
    icon: Icons.mood_outlined,
    defaultTimes: [Duration(hours: 19)],
    priority: 1,
  ),
  streak(
    id: 'streak',
    label: 'Streaks',
    description: 'A cheer when you are on a roll',
    icon: Icons.local_fire_department_outlined,
    defaultTimes: [Duration(hours: 20, minutes: 15)],
    priority: 2,
  );

  const NotificationCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.defaultTimes,
    required this.priority,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;

  /// Local times of day (offset from midnight) when this category fires.
  final List<Duration> defaultTimes;

  /// Lower wins when two nudges land close together.
  final int priority;

  static NotificationCategory? fromId(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}
