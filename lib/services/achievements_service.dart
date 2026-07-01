// services/achievements_service.dart
//
// Unified achievement system, derived entirely from BellaService.
//
// Why this version exists: the previous one (and InsightsScreen, which fed
// it) sourced session lists from DataStorageService — a SharedPreferences
// store that breathwork_screen.dart never writes to at all, and that
// sleep_sounds_player_service.dart explicitly stopped writing to (see its
// header comment: "DataStorageService writes are orphaned... removed").
// That meant breathwork and sleep-sounds achievements/stats were
// structurally guaranteed to read as empty, forever, regardless of how
// much the user actually did.
//
// BellaService.getSessions() is the one write path every activity screen
// (meditation, walking, breathwork, sleep sounds) reliably calls via
// `logSession(type, minutes)`. So this service — and Insights — now reads
// only from there. The trade-off: we lose per-session extras that were
// never reliably persisted anyway (steps, technique name, start/end HR).
// Every achievement below is built from fields that are guaranteed to
// exist: session type, date, and duration in minutes.
//
// Design rules (unchanged):
//   • No separate persistence layer. Progress is always computed live from
//     Bella so it can never drift out of sync.
//   • Achievements are immutable value objects; the service is stateless.
import 'package:flutter/material.dart';
import 'bella_service.dart';
import 'user_service.dart';
import '../models/bella_data.dart';

/// A fully computed achievement — no nulls, safe to render directly.
class Achievement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  /// 0–100, clamped.
  final double progress;

  /// progress == 100
  final bool isUnlocked;

  /// Wall-clock time this was first unlocked; null if still locked.
  /// Since we compute live, this is approximated as "now" on first unlock.
  final DateTime? unlockedAt;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.progress,
    required this.isUnlocked,
    this.unlockedAt,
  });
}

class AchievementsService {
  AchievementsService._();
  static final AchievementsService instance = AchievementsService._();

  final BellaService _bella = BellaService();

  /// Read once per compute() call and consulted by _make() below so every
  /// achievement in this pass agrees on what's already been recorded.
  Map<String, DateTime> _unlockLog = const {};

  /// Computes the full achievement list from live Bella data.
  /// [sessions] should be `BellaService().getSessions()` (all types) — the
  /// caller fetches it so this stays synchronous and so the caller (e.g.
  /// InsightsScreen) reuses the exact same list it displays elsewhere.
  List<Achievement> compute(List<WellnessSession> sessions) {
    _unlockLog = _bella.getAchievementUnlocks();
    final meditation = sessions.where((s) => s.type == 'meditation').toList();
    final walking = sessions.where((s) => s.type == 'walking').toList();
    final breathwork = sessions.where((s) => s.type == 'breathwork').toList();
    final sleepSounds =
        sessions.where((s) => s.type == 'sleep_sounds').toList();

    // ── Raw stats ──────────────────────────────────────────────────────────
    final int totalMedMinutes =
        meditation.fold(0, (s, e) => s + e.durationMinutes);
    final int totalWalkMinutes =
        walking.fold(0, (s, e) => s + e.durationMinutes);

    final int breathworkCount = breathwork.length;
    final int sleepSoundsCount = sleepSounds.length;
    final int totalWalkSessions = walking.length;

    final int breathworkDays = _distinctDayCount(breathwork);
    final int walkingDays = _distinctDayCount(walking);

    final int sleepSoundsStreak = _currentStreak(sleepSounds);

    final int currentStreak = _currentStreak(sessions);
    final int longestStreak = _longestStreak(sessions);

    final double? avgSleepQuality = _bella.averageSleepQuality();
    final int checkinCount = _bella.getCheckins().length;
    final int totalActiveSessions = sessions.length;
    final int hydratedDays = _hydratedDayCount();
    final int calmingMinutes = totalMedMinutes + breathwork.fold(
        0, (s, e) => s + e.durationMinutes);

    // Steps (walking sessions carry their step count in `detail`, e.g.
    // '8421' — only present on sessions logged after this field was added,
    // so older sessions without it simply contribute 0 rather than crash).
    final int totalSteps = walking.fold(
        0, (s, e) => s + (int.tryParse(e.detail ?? '') ?? 0));

    // Technique diversity (breathwork sessions carry the technique name in
    // `detail`, e.g. 'Box Breathing' — same caveat: only present going
    // forward, older sessions just don't count toward this one).
    final Set<String> breathTechniques = breathwork
        .map((e) => e.detail)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet();

    // Pose diversity (meditation sessions carry the pose's short name in
    // `detail`, e.g. 'Lotus' — same forward-only caveat as above).
    final Set<String> meditationPoses = meditation
        .map((e) => e.detail)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet();

    // Tiered/ultimate stats
    final double? avgSleepLong = _bella.averageSleepQuality(days: 30);
    final int loggedSleepNights = _bella.getSleepEntries()
        .where((e) => !e.isNap)
        .length;
    final username = UserService().currentUserObject?.username ??
        UserService().currentUser;
    final bool isWellRounded = totalMedMinutes >= 60 &&
        totalWalkMinutes >= 60 &&
        breathworkCount >= 10 &&
        sleepSoundsCount >= 10;
    final bool isLegend = longestStreak >= 30 &&
        totalActiveSessions >= 100 &&
        isWellRounded &&
        (avgSleepLong ?? 0) >= 4.0 &&
        checkinCount >= 20 &&
        hydratedDays >= 14;
    // Progress toward the ultimate achievement, blended evenly across its
    // six gates, so the bar actually moves instead of sitting at 0 until
    // every single condition flips at once.
    final double legendProgress = ((longestStreak / 30).clamp(0.0, 1.0) +
            (totalActiveSessions / 100).clamp(0.0, 1.0) +
            ([
              totalMedMinutes / 60,
              totalWalkMinutes / 60,
              breathworkCount / 10,
              sleepSoundsCount / 10,
            ].map((v) => v.clamp(0.0, 1.0)).reduce((a, b) => a + b) / 4) +
            (((avgSleepLong ?? 0) / 4.0)).clamp(0.0, 1.0) +
            (checkinCount / 20).clamp(0.0, 1.0) +
            (hydratedDays / 14).clamp(0.0, 1.0)) /
        6 *
        100;

    // ── Build achievements ─────────────────────────────────────────────────
    final base = <Achievement>[
      _make(
        id: 'first_breath',
        title: 'First Breath',
        description: 'Complete your first breathwork session',
        icon: Icons.air,
        color: const Color(0xFF5B8DEF),
        progress: breathworkCount >= 1 ? 100 : 0,
        isUnlocked: breathworkCount >= 1,
      ),
      _make(
        id: 'first_meditation',
        title: 'First Step Inward',
        description: 'Complete your first meditation session',
        icon: Icons.self_improvement,
        color: const Color(0xFF9B59B6),
        progress: meditation.isNotEmpty ? 100 : 0,
        isUnlocked: meditation.isNotEmpty,
      ),
      _make(
        id: 'meditation_30min',
        title: 'Mindful Half Hour',
        description: '30 total minutes of meditation',
        icon: Icons.spa,
        color: const Color(0xFF9B59B6),
        progress: (totalMedMinutes / 30 * 100).clamp(0, 100),
        isUnlocked: totalMedMinutes >= 30,
      ),
      _make(
        id: 'meditation_300min',
        title: 'Meditation Master',
        description: '5 hours of meditation logged',
        icon: Icons.spa,
        color: const Color(0xFF6C3483),
        progress: (totalMedMinutes / 300 * 100).clamp(0, 100),
        isUnlocked: totalMedMinutes >= 300,
      ),
      _make(
        id: 'meditation_3poses',
        title: 'Pose Explorer',
        description: 'Try 3 different meditation poses',
        icon: Icons.self_improvement,
        color: const Color(0xFFAF7AC5),
        progress: (meditationPoses.length / 3 * 100).clamp(0, 100),
        isUnlocked: meditationPoses.length >= 3,
      ),
      _make(
        id: 'breathwork_5days',
        title: 'Breathwork Explorer',
        description: 'Practice breathwork on 5 different days',
        icon: Icons.air,
        color: const Color(0xFF5B8DEF),
        progress: (breathworkDays / 5 * 100).clamp(0, 100),
        isUnlocked: breathworkDays >= 5,
      ),
      _make(
        id: 'breathwork_3techniques',
        title: 'Technique Collector',
        description: 'Try 3 different breathwork techniques',
        icon: Icons.air,
        color: const Color(0xFF2E86C1),
        progress: (breathTechniques.length / 3 * 100).clamp(0, 100),
        isUnlocked: breathTechniques.length >= 3,
      ),
      _make(
        id: 'breathwork_20',
        title: 'Breath Pro',
        description: '20 breathwork sessions completed',
        icon: Icons.air,
        color: const Color(0xFF1A5276),
        progress: (breathworkCount / 20 * 100).clamp(0, 100),
        isUnlocked: breathworkCount >= 20,
      ),
      _make(
        id: 'first_walk',
        title: 'First Steps',
        description: 'Complete your first walking session',
        icon: Icons.directions_walk,
        color: const Color(0xFF2E9E6B),
        progress: totalWalkSessions >= 1 ? 100 : 0,
        isUnlocked: totalWalkSessions >= 1,
      ),
      _make(
        id: 'walk_7days',
        title: 'Daily Walker',
        description: 'Walk on 7 different days',
        icon: Icons.directions_walk,
        color: const Color(0xFF2E9E6B),
        progress: (walkingDays / 7 * 100).clamp(0, 100),
        isUnlocked: walkingDays >= 7,
      ),
      _make(
        id: 'walk_150min',
        title: 'On the Move',
        description: '150 total minutes of walking logged',
        icon: Icons.emoji_events,
        color: const Color(0xFFEAAE49),
        progress: (totalWalkMinutes / 150 * 100).clamp(0, 100),
        isUnlocked: totalWalkMinutes >= 150,
      ),
      _make(
        id: 'walk_600min',
        title: 'Distance Champion',
        description: '600 total minutes of walking logged',
        icon: Icons.emoji_events,
        color: const Color(0xFFD4AC0D),
        progress: (totalWalkMinutes / 600 * 100).clamp(0, 100),
        isUnlocked: totalWalkMinutes >= 600,
      ),
      _make(
        id: 'steps_10k',
        title: 'Step Milestone',
        description: '10,000 total steps logged (sessions since step '
            'tracking was added)',
        icon: Icons.directions_walk,
        color: const Color(0xFF229954),
        progress: (totalSteps / 10000 * 100).clamp(0, 100),
        isUnlocked: totalSteps >= 10000,
      ),
      _make(
        id: 'steps_100k',
        title: 'Step Champion',
        description: '100,000 total steps logged (sessions since step '
            'tracking was added)',
        icon: Icons.directions_walk,
        color: const Color(0xFF145A32),
        progress: (totalSteps / 100000 * 100).clamp(0, 100),
        isUnlocked: totalSteps >= 100000,
      ),
      _make(
        id: 'sleep_sounds_10',
        title: 'Night Listener',
        description: 'Use sleep sounds on 10 nights',
        icon: Icons.nightlight_round,
        color: const Color(0xFF5D6D7E),
        progress: (sleepSoundsCount / 10 * 100).clamp(0, 100),
        isUnlocked: sleepSoundsCount >= 10,
      ),
      _make(
        id: 'sleep_sounds_streak_7',
        title: 'Wind-Down Habit',
        description: '7 consecutive nights of relaxation sounds',
        icon: Icons.bedtime_outlined,
        color: const Color(0xFF4A6FA5),
        progress: (sleepSoundsStreak / 7 * 100).clamp(0, 100),
        isUnlocked: sleepSoundsStreak >= 7,
      ),
      _make(
        id: 'sleep_quality',
        title: 'Rest Well',
        description: 'Average sleep quality of 4/5 over 7 nights',
        icon: Icons.nightlight_round,
        color: const Color(0xFF4A235A),
        progress: avgSleepQuality != null
            ? (avgSleepQuality / 4 * 100).clamp(0, 100)
            : 0,
        isUnlocked: (avgSleepQuality ?? 0) >= 4,
      ),
      _make(
        id: 'streak_3',
        title: 'Getting Going',
        description: '3-day activity streak',
        icon: Icons.local_fire_department,
        color: const Color(0xFFE2734B),
        progress: (currentStreak / 3 * 100).clamp(0, 100),
        isUnlocked: currentStreak >= 3 || longestStreak >= 3,
      ),
      _make(
        id: 'streak_7',
        title: 'Week Warrior',
        description: '7-day activity streak',
        icon: Icons.local_fire_department,
        color: const Color(0xFFE74C3C),
        progress: (longestStreak / 7 * 100).clamp(0, 100),
        isUnlocked: longestStreak >= 7,
      ),
      _make(
        id: 'streak_30',
        title: 'Consistency King',
        description: '30-day activity streak',
        icon: Icons.local_fire_department,
        color: const Color(0xFF922B21),
        progress: (longestStreak / 30 * 100).clamp(0, 100),
        isUnlocked: longestStreak >= 30,
      ),
      _make(
        id: 'checkin_7',
        title: 'Self-Aware',
        description: '7 daily check-ins completed',
        icon: Icons.mood,
        color: const Color(0xFFEAAE49),
        progress: (checkinCount / 7 * 100).clamp(0, 100),
        isUnlocked: checkinCount >= 7,
      ),
      _make(
        id: 'all_rounder',
        title: 'All-Rounder',
        description: 'Try meditation, breathwork, walking & sleep sounds',
        icon: Icons.auto_awesome,
        color: const Color(0xFF2E9E6B),
        progress: ([
                  meditation.isNotEmpty,
                  breathworkCount > 0,
                  totalWalkSessions > 0,
                  sleepSoundsCount > 0,
                ].where((v) => v).length /
                4 *
                100)
            .clamp(0, 100),
        isUnlocked: meditation.isNotEmpty &&
            breathworkCount > 0 &&
            totalWalkSessions > 0 &&
            sleepSoundsCount > 0,
      ),
      _make(
        id: 'sessions_50',
        title: 'Dedicated',
        description: '50 total wellness sessions',
        icon: Icons.workspace_premium,
        color: const Color(0xFF2E9E6B),
        progress: (totalActiveSessions / 50 * 100).clamp(0, 100),
        isUnlocked: totalActiveSessions >= 50,
      ),
      _make(
        id: 'hydration_7',
        title: 'Hydration Habit',
        description: 'Hit your water target on 7 different days',
        icon: Icons.water_drop_outlined,
        color: const Color(0xFF2E86C1),
        progress: (hydratedDays / 7 * 100).clamp(0, 100),
        isUnlocked: hydratedDays >= 7,
      ),
      _make(
        id: 'mind_body_balance',
        title: 'Mind-Body Balance',
        description: '60+ calming minutes (meditation + breathwork) with '
            'average sleep quality of 4/5 or better',
        icon: Icons.balance,
        color: const Color(0xFF16A085),
        progress: (((calmingMinutes / 60).clamp(0.0, 1.0) * 0.5 +
                    ((avgSleepQuality ?? 0) / 4).clamp(0.0, 1.0) * 0.5) *
                100)
            .clamp(0, 100),
        isUnlocked: calmingMinutes >= 60 && (avgSleepQuality ?? 0) >= 4,
      ),

      // ── Hardened tiers — built on the basics above but pushed much further ──
      _make(
        id: 'streak_60',
        title: 'Iron Will',
        description: '60-day activity streak',
        icon: Icons.local_fire_department,
        color: const Color(0xFF641E16),
        progress: (longestStreak / 60 * 100).clamp(0, 100),
        isUnlocked: longestStreak >= 60,
      ),
      _make(
        id: 'sessions_150',
        title: 'Wellness Veteran',
        description: '150 total wellness sessions',
        icon: Icons.workspace_premium,
        color: const Color(0xFF1D8348),
        progress: (totalActiveSessions / 150 * 100).clamp(0, 100),
        isUnlocked: totalActiveSessions >= 150,
      ),
      _make(
        id: 'meditation_1000min',
        title: 'Meditation Sage',
        description: '1,000 total minutes of meditation (~16.5 hours)',
        icon: Icons.spa,
        color: const Color(0xFF4A235A),
        progress: (totalMedMinutes / 1000 * 100).clamp(0, 100),
        isUnlocked: totalMedMinutes >= 1000,
      ),
      _make(
        id: 'walk_1500min',
        title: 'Marathon Mindset',
        description: '1,500 total minutes of walking (~25 hours)',
        icon: Icons.emoji_events,
        color: const Color(0xFFB9770E),
        progress: (totalWalkMinutes / 1500 * 100).clamp(0, 100),
        isUnlocked: totalWalkMinutes >= 1500,
      ),
      _make(
        id: 'breathwork_100',
        title: 'Breath Master',
        description: '100 breathwork sessions completed',
        icon: Icons.air,
        color: const Color(0xFF0B5345),
        progress: (breathworkCount / 100 * 100).clamp(0, 100),
        isUnlocked: breathworkCount >= 100,
      ),
      _make(
        id: 'sleep_quality_30',
        title: 'Deep Rester',
        description: '30 nights logged with average quality 4.5/5 or better',
        icon: Icons.nightlight_round,
        color: const Color(0xFF1B2631),
        progress: ((loggedSleepNights / 30).clamp(0.0, 1.0) * 0.5 +
                    ((avgSleepLong ?? 0) / 4.5).clamp(0.0, 1.0) * 0.5) *
                100,
        isUnlocked: loggedSleepNights >= 30 && (avgSleepLong ?? 0) >= 4.5,
      ),
      _make(
        id: 'checkin_30',
        title: 'Mindful Tracker',
        description: '30 daily check-ins completed',
        icon: Icons.mood,
        color: const Color(0xFF7D6608),
        progress: (checkinCount / 30 * 100).clamp(0, 100),
        isUnlocked: checkinCount >= 30,
      ),
      _make(
        id: 'hydration_30',
        title: 'Hydration Master',
        description: 'Hit your water target on 30 different days',
        icon: Icons.water_drop,
        color: const Color(0xFF1A5276),
        progress: (hydratedDays / 30 * 100).clamp(0, 100),
        isUnlocked: hydratedDays >= 30,
      ),
      _make(
        id: 'well_rounded',
        title: 'Well-Rounded',
        description: 'At least 1 hour each of meditation & walking, plus 10+ '
            'breathwork and 10+ sleep-sounds sessions',
        icon: Icons.auto_awesome,
        color: const Color(0xFF117864),
        progress: ([
          totalMedMinutes / 60,
          totalWalkMinutes / 60,
          breathworkCount / 10,
          sleepSoundsCount / 10,
        ].map((v) => v.clamp(0.0, 1.0)).reduce((a, b) => a + b) / 4 * 100),
        isUnlocked: isWellRounded,
      ),

      // ── The ultimate trophy ───────────────────────────────────────────────
      // Requires a 30-day streak, 100 sessions, well-rounded practice across
      // all four activity types, a strong 30-day sleep average, 20 check-ins
      // and 14 hydrated days — essentially "you've actually built the whole
      // habit, everywhere, for a while." Title is personalized with the
      // signed-in username.
      _make(
        id: 'sage_legend',
        title: username != null && username.isNotEmpty
            ? 'You Are a Sage, $username'
            : 'You Are a Sage',
        description: 'The ultimate trophy: 30-day streak, 100+ sessions, '
            'well-rounded practice across every activity, strong sleep, '
            'consistent check-ins, and disciplined hydration — all at once.',
        icon: Icons.military_tech,
        color: const Color(0xFFD4AC0D),
        progress: legendProgress,
        isUnlocked: isLegend,
      ),
    ];

    return base;
  }

  /// Days (any time window in the data) where logged water reached at
  /// least the user's target for that day. Uses whatever target is set
  /// now as a simple, consistent bar rather than reconstructing historical
  /// targets.
  int _hydratedDayCount() {
    final target = _bella.getTarget<int>('waterMl') ?? 2000;
    final entries = _bella.getWaterEntries();
    if (entries.isEmpty) return 0;
    final byDay = <String, int>{};
    for (final w in entries) {
      final key = _dateKey(w.time);
      byDay[key] = (byDay[key] ?? 0) + w.milliliters;
    }
    return byDay.values.where((total) => total >= target).length;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Achievement _make({
    required String id,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required double progress,
    required bool isUnlocked,
  }) {
    DateTime? unlockedAt;
    if (isUnlocked) {
      unlockedAt = _unlockLog[id];
      if (unlockedAt == null) {
        // First time this id has ever been seen unlocked — record it once,
        // now, and never again (recordAchievementUnlock no-ops if a date
        // already exists). Fire-and-forget: compute() stays synchronous,
        // and a write that loses a race with a fast double-call just costs
        // a few minutes of accuracy on a single achievement, not a crash.
        unlockedAt = DateTime.now();
        _bella.recordAchievementUnlock(id, unlockedAt);
      }
    }
    return Achievement(
      id: id,
      title: title,
      description: description,
      icon: icon,
      color: color,
      progress: progress.clamp(0, 100),
      isUnlocked: isUnlocked,
      unlockedAt: unlockedAt,
    );
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  int _distinctDayCount(List<WellnessSession> sessions) =>
      sessions.map((s) => _dateKey(s.date)).toSet().length;

  int _currentStreak(List<WellnessSession> sessions) {
    final days = sessions.map((s) => _dateKey(s.date)).toSet();
    int streak = 0;
    var cursor = DateTime.now();
    for (int i = 0; i < 365; i++) {
      if (days.contains(_dateKey(cursor))) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  int _longestStreak(List<WellnessSession> sessions) {
    if (sessions.isEmpty) return 0;
    final sorted = sessions
        .map((s) => DateTime(s.date.year, s.date.month, s.date.day))
        .toSet()
        .toList()
      ..sort();
    int longest = 1, current = 1;
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i].difference(sorted[i - 1]).inDays == 1) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 1;
      }
    }
    return longest;
  }
}