// services/wellness_score_service.dart
//
// Single source of truth for the overall wellness score and its five
// pillars (sleep / nutrition / check-in / activity / chronic care).
//
// Why this exists: WellnessScreen and InsightsScreen each had their own
// copy of this formula. They drifted — different chronic-care baseline
// (100 vs 85), different per-condition flag thresholds for Asthma/
// Cholesterol/Arthritis, and completely different score→label breakpoints
// ("Needs Care" at 40 vs "Take it easy" at 35 with different wording).
// That's why the same user could see a 43 labeled "Needs Care" on one
// screen and a 44 labeled "Take it easy" on another — two different
// formulas computing two different numbers with two different label sets,
// not a rounding quirk.
//
// Both screens now call `WellnessScoreService.compute(...)`. There is
// exactly one formula, one set of chronic-flag thresholds, and one set of
// label/color breakpoints. If this needs to change, change it here once.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/bella_data.dart';
import 'bella_service.dart';

class WellnessScoreResult {
  final int sleepScore;
  final int nutritionScore;
  final int checkinScore;
  final int activityScore;
  final int chronicScore;
  final int overallScore;

  /// Conditions whose most recent reading is outside the typical range.
  final List<String> flaggedConditions;

  const WellnessScoreResult({
    required this.sleepScore,
    required this.nutritionScore,
    required this.checkinScore,
    required this.activityScore,
    required this.chronicScore,
    required this.overallScore,
    required this.flaggedConditions,
  });
}

class WellnessScoreService {
  WellnessScoreService._();

  /// Computes every pillar + the blended overall score for a given day.
  /// Pass the user's chronic conditions (or an empty list) — the service
  /// does not read UserService itself so callers stay in control of
  /// exactly whose data this is.
  ///
  /// [asOf] defaults to now ("today's" live score, as seen on both
  /// screens). Pass a past date (e.g. yesterday) to get that day's score
  /// computed the same way — this is what backs the "+6 vs yesterday"
  /// delta on the Insights score hero. Each pillar reads straight from
  /// Bella's raw timestamped records filtered to that calendar day, rather
  /// than Bella's `...Today()` convenience methods (which only ever mean
  /// the literal current day), so the same formula works for any date.
  static WellnessScoreResult compute({
    required BellaService bella,
    required List<String> chronicConditions,
    DateTime? asOf,
  }) {
    final date = asOf ?? DateTime.now();
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    // Sleep (30%) — 7-night window ending on this day, non-nap entries.
    final sleepWindowStart = dayStart.subtract(const Duration(days: 6));
    final sleepEntries = bella
        .getSleepEntries()
        .where((e) =>
            !e.isNap &&
            !e.date.isBefore(sleepWindowStart) &&
            e.date.isBefore(dayEnd))
        .toList();
    final avgSleep = sleepEntries.isEmpty
        ? null
        : sleepEntries.map((e) => e.quality).reduce((a, b) => a + b) /
            sleepEntries.length;
    final sleepScore =
        avgSleep != null ? ((avgSleep / 5.0) * 100).round().clamp(0, 100) : 0;

    // Nutrition (20%) — food logging + calorie range + hydration, that day.
    final foodOnDate = bella
        .getFoodEntries()
        .where((f) => !f.time.isBefore(dayStart) && f.time.isBefore(dayEnd))
        .toList();
    final caloriesOnDate = foodOnDate.fold(0, (s, f) => s + (f.calories ?? 0));
    final waterOnDateRaw = bella
        .getWaterEntries()
        .where((w) => !w.time.isBefore(dayStart) && w.time.isBefore(dayEnd))
        .fold(0, (s, w) => s + w.milliliters);
    final waterOnDate = waterOnDateRaw < 0 ? 0 : waterOnDateRaw;

    final loggingScore = (foodOnDate.length / 3).clamp(0.0, 1.0) * 50;
    double calScore = 0;
    if (caloriesOnDate >= 1200 && caloriesOnDate <= 3000) {
      calScore = 30;
    } else if (caloriesOnDate > 0) {
      calScore = 15;
    }
    final waterTarget = bella.getTarget<int>('waterMl') ?? 2000;
    final waterScore = (waterOnDate / waterTarget).clamp(0.0, 1.0) * 20;
    final nutritionScore =
        (loggingScore + calScore + waterScore).round().clamp(0, 100);

    // Check-in (20%) — most recent check-in at or before this day, "fresh"
    // if within 36 hours of `date`. Explicitly sorted newest-first after
    // filtering so this is robust even if BellaService's source order changes.
    final checkinsUpToDate = bella
        .getCheckins()
        .where((c) => c.time.isBefore(dayEnd))
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    final checkinAsOf = checkinsUpToDate.isEmpty ? null : checkinsUpToDate.first;
    final checkinAge =
        checkinAsOf != null ? date.difference(checkinAsOf.time).inHours : 999;
    final checkinScore = (checkinAge <= 36 && checkinAsOf != null)
        ? (checkinAsOf.wellbeingScore * 10).round().clamp(0, 100)
        : 50; // neutral when there's no recent check-in

    // Activity (20%) — meditation, breathwork, walking vs targets, that day.
    final sessionsOnDate = bella
        .getSessions()
        .where((s) => !s.date.isBefore(dayStart) && s.date.isBefore(dayEnd))
        .toList();
    int minutesOf(String type) => sessionsOnDate
        .where((s) => s.type == type)
        .fold(0, (s, e) => s + e.durationMinutes);
    int countOf(String type) =>
        sessionsOnDate.where((s) => s.type == type).length;

    final medTarget = bella.getTarget<int>('meditationMinutes') ?? 10;
    final bwTarget = bella.getTarget<int>('breathworkSessions') ?? 1;
    final walkTarget = bella.getTarget<int>('walkMinutes') ?? 30;
    final medPct = (minutesOf('meditation') / medTarget).clamp(0.0, 1.0);
    final bwPct = (countOf('breathwork') / bwTarget).clamp(0.0, 1.0);
    final walkPct = (minutesOf('walking') / walkTarget).clamp(0.0, 1.0);
    final activityScore =
        ((medPct + bwPct + walkPct) / 3 * 100).round().clamp(0, 100);

    // Chronic care (10%) — latest reading at or before this day, per condition.
    int chronicScore = 100;
    final flagged = <String>[];
    if (chronicConditions.isNotEmpty) {
      for (final cond in chronicConditions) {
        final readings = bella
            .getReadings(condition: cond)
            .where((r) => r.time.isBefore(dayEnd))
            .toList();
        if (readings.isEmpty) continue;
        if (isReadingFlagged(cond, readings.first)) flagged.add(cond);
      }
      chronicScore = flagged.isEmpty ? 85 : 40;
    }

    final overallScore = ((sleepScore * 0.30) +
            (nutritionScore * 0.20) +
            (checkinScore * 0.20) +
            (activityScore * 0.20) +
            (chronicScore * 0.10))
        .round()
        .clamp(0, 100);

    return WellnessScoreResult(
      sleepScore: sleepScore,
      nutritionScore: nutritionScore,
      checkinScore: checkinScore,
      activityScore: activityScore,
      chronicScore: chronicScore,
      overallScore: overallScore,
      flaggedConditions: flagged,
    );
  }

  /// The one and only set of per-condition "is this reading concerning"
  /// thresholds. Mirrors CareRules' notion of a flagged reading exactly —
  /// kept here too so the score can be computed without round-tripping
  /// through CareRules' private helpers.
  static bool isReadingFlagged(String condition, ReadingEntry r) {
    switch (condition) {
      case 'Diabetes':
        return r.value < 70 || r.value > 180;
      case 'Hypertension':
      case 'Heart Disease':
      case 'Chronic Kidney Disease':
        return r.value >= 140 || (r.secondaryValue ?? 0) >= 90;
      case 'High Cholesterol':
        return r.value >= 200;
      case 'Asthma':
        return r.value < 200;
      case 'Arthritis':
        return r.value >= 7;
      default:
        return false;
    }
  }

  /// The one and only label/breakpoint set. 80/60/40 — matches what
  /// shipped on WellnessScreen, since that's the one the user sees first
  /// and most often (the dashboard hub), so it is treated as canonical.
  static String label(int score) {
    if (score >= 80) return 'Thriving';
    if (score >= 60) return 'On Track';
    if (score >= 40) return 'Needs Care';
    return 'Low';
  }

  static Color color(int score) {
    if (score >= 80) return SageColors.sage;
    if (score >= 60) return SageColors.moss;
    if (score >= 40) return SageColors.amber;
    return SageColors.clay;
  }
}