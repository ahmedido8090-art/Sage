// utils/health_metrics.dart
//
// Small pure helpers shared across screens and services: BMI category, day
// keys and streak counting. One implementation each, so every screen agrees.

/// WHO adult BMI band for [bmi].
String bmiCategory(double bmi) {
  if (bmi < 18.5) return 'Underweight';
  if (bmi < 25) return 'Normal';
  if (bmi < 30) return 'Overweight';
  return 'Obese';
}

/// Calendar-day key (`2026-03-07`) in local time, safe to use as a set member.
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Consecutive active days counting back from today. A day without activity
/// ends the streak, except that today is still open: if nothing has been
/// logged yet today, the streak counts from yesterday instead of dropping to
/// zero.
int streakEndingToday(Set<String> activeDays,
    {DateTime? now, int maxDays = 365}) {
  var cursor = now ?? DateTime.now();
  if (!activeDays.contains(dayKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  for (var i = 0; i < maxDays; i++) {
    if (!activeDays.contains(dayKey(cursor))) break;
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}
