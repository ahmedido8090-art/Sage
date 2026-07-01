// screens/insights_screen.dart
//
// Insights & Achievements screen.
//
// ── Data source discipline (read this before touching this file) ──────────
// BellaService is the ONLY source for everything below. Every activity
// screen (meditation, walking, breathwork, sleep sounds) calls
// `BellaService().logSession(type, minutes)` on completion — it is the one
// write path that is guaranteed to be populated. DataStorageService (a
// separate SharedPreferences store) is NOT used for sessions here anymore:
// breathwork_screen.dart never wrote to it, and sleep_sounds_player_service
// explicitly stopped writing to it, so any screen built on top of it was
// structurally blind to half the app's activity types. The previous
// version of this screen had exactly that bug, which is why it "couldn't
// read any data."
//
// DataStorageService is still used for ONE thing: live band heart-rate
// history (written directly by BluetoothService whenever a band is
// connected) — that pipeline is independent and was never broken.
//
// Sections, all backed by real Bella data:
//   • Wellness score hero (sleep/nutrition/check-in/activity/chronic blend)
//   • 14-day activity trend
//   • Activity-type breakdown (donut)
//   • Week-over-week comparison
//   • Totals & vitals grid (minutes per type, streaks, avg HR, BMI)
//   • Sleep trend (last 7 nights)
//   • Mood & check-in trend (last 7 days)
//   • Nutrition & hydration
//   • Chronic condition readings (only shown if conditions are set)
//   • Day-of-week pattern
//   • Recommendations
//   • Achievements tab

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/data_storage_service.dart';
import '../services/user_service.dart';
import '../services/bella_service.dart';
import '../services/achievements_service.dart';
import '../services/wellness_score_service.dart';
import '../models/bella_data.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/animated_number.dart';
import '../widgets/shimmer_loader.dart';
import '../widgets/reveal.dart';
import '../widgets/pressable.dart';
import '../widgets/stagger.dart';

class InsightsScreen extends StatefulWidget {
  /// Increment to trigger a data reload without rebuilding the widget tree.
  final ValueNotifier<int>? reloadSignal;

  const InsightsScreen({super.key, this.reloadSignal});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  final BellaService _bella = BellaService();
  final DataStorageService _dataStorage = DataStorageService();

  late final TabController _tabs;
  final ScrollController _scrollController = ScrollController();

  // ── Source data ───────────────────────────────────────────────────────────
  List<WellnessSession> _allSessions = [];
  List<CheckinEntry> _checkins = [];
  List<SleepEntry> _sleepEntries = [];
  List<FoodEntry> _foodEntries = [];
  List<Map<String, dynamic>> _bandData = [];

  // ── Computed state ───────────────────────────────────────────────────────
  List<Achievement> _achievements = [];
  WellnessScoreResult? _scoreResult;
  WellnessScoreResult? _yesterdayScoreResult;
  bool _isLoading = true;
  _TotalsPeriod _totalsPeriod = _TotalsPeriod.last14;
  int _trendDays = 14;

  // ── BMI ──────────────────────────────────────────────────────────────────
  double _bmi = 22.5;
  String _bmiCategory = 'Normal';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    widget.reloadSignal?.addListener(_onReloadSignal);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scrollController.dispose();
    widget.reloadSignal?.removeListener(_onReloadSignal);
    super.dispose();
  }

  String _formatFullDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '${months[d.month - 1]} ${d.day}, ${d.year} · $hour12:$minute $ampm';
  }

  void _onReloadSignal() => _loadAll();

  /// Builds a plain-text summary of everything this screen shows — score
  /// + pillars, activity totals (today/yesterday/14d), streaks, sleep,
  /// mood, nutrition/hydration, chronic readings, and achievement
  /// progress — and copies it to the clipboard. No share_plus or similar
  /// package required: Clipboard is part of the Flutter SDK, so this
  /// works today without touching pubspec.yaml. From the clipboard the
  /// user can paste it into an email, a notes app, or to a doctor.
  Future<void> _exportReport() async {
    final buf = StringBuffer();
    final now = DateTime.now();
    final user = UserService().currentUserObject;
    final result = _scoreResult;

    buf.writeln('SAGE HEALTH — WELLNESS REPORT');
    buf.writeln(_formatFullDate(now));
    if (user != null) buf.writeln('User: ${user.username}');
    buf.writeln();

    if (result != null) {
      buf.writeln('— WELLNESS SCORE —');
      buf.writeln('Overall: ${result.overallScore}/100 ($_scoreLabel)');
      if (_yesterdayScoreResult != null) {
        final diff = result.overallScore - _yesterdayScoreResult!.overallScore;
        buf.writeln('Yesterday: ${_yesterdayScoreResult!.overallScore}/100 '
            '(${diff >= 0 ? '+' : ''}$diff today)');
      }
      buf.writeln('  Sleep: ${result.sleepScore}/100 (30% weight)');
      buf.writeln('  Nutrition: ${result.nutritionScore}/100 (20% weight)');
      buf.writeln('  Check-in: ${result.checkinScore}/100 (20% weight)');
      buf.writeln('  Activity: ${result.activityScore}/100 (20% weight)');
      buf.writeln('  Chronic care: ${result.chronicScore}/100 (10% weight)');
      buf.writeln();
    }

    buf.writeln('— ACTIVITY TOTALS (all-time) —');
    for (final type in ['meditation', 'walking', 'breathwork', 'sleep_sounds']) {
      final sessions = _byType(type);
      if (sessions.isEmpty) continue;
      buf.writeln('  ${type == 'sleep_sounds' ? 'Sleep sounds' : type[0].toUpperCase() + type.substring(1)}: '
          '${sessions.length} sessions, ${_minutesOf(sessions)} minutes');
    }
    // Steps: parsed from walking session detail field
    final totalStepsReport = _byType('walking').fold<int>(
        0, (s, e) => s + (int.tryParse(e.detail ?? '') ?? 0));
    if (totalStepsReport > 0) {
      buf.writeln('  Total steps logged: $totalStepsReport');
    }
    buf.writeln('  Current streak: $_currentStreak days');
    buf.writeln('  Longest streak: $_longestStreak days');
    buf.writeln();

    final avgSleep = _bella.averageSleepQuality();
    final avgWellbeing = _bella.averageWellbeing();
    buf.writeln('— VITALS —');
    buf.writeln('  Avg sleep quality (7d): ${avgSleep?.toStringAsFixed(1) ?? '—'}/5');
    buf.writeln('  Avg wellbeing (7d): ${avgWellbeing?.toStringAsFixed(1) ?? '—'}/10');
    final avgHr = _avgHeartRate;
    buf.writeln('  Avg heart rate (14d): ${avgHr != null ? '$avgHr bpm' : '—'}');
    buf.writeln('  BMI: ${_bmi.toStringAsFixed(1)} ($_bmiCategory)');
    buf.writeln();

    if (user != null && user.chronicDiseases.isNotEmpty) {
      buf.writeln('— CHRONIC CARE READINGS —');
      for (final cond in user.chronicDiseases) {
        final readings = _bella.getReadings(condition: cond);
        if (readings.isEmpty) {
          buf.writeln('  $cond: no readings logged');
          continue;
        }
        final latest = readings.first;
        final flagged = _isReadingFlagged(cond, latest);
        buf.write('  $cond: ${latest.type} ${latest.value.toStringAsFixed(0)}'
            '${latest.secondaryValue != null ? '/${latest.secondaryValue!.toStringAsFixed(0)}' : ''} '
            '${latest.unit} (${_relativeTime(latest.time)})'
            '${flagged ? ' — OUTSIDE TYPICAL RANGE' : ''}');
        // Trend direction: compare latest vs the reading before it (same type).
        final trend = _bella.readingTrend(cond, latest.type, n: 14);
        if (trend.length >= 2) {
          final first = trend.first.value;
          final last = trend.last.value;
          final change = last - first;
          final higherIsBetter = cond == 'Asthma';
          final improved = higherIsBetter ? change > 0 : change < 0;
          final flat = (first != 0 ? (change / first * 100).abs() : 0) < 3;
          if (!flat) {
            final arrow = improved ? '↑ improving' : '↓ worsening';
            buf.write(' · $arrow over last ${trend.length} readings '
                '(${first.toStringAsFixed(0)} → ${last.toStringAsFixed(0)})');
          } else {
            buf.write(' · steady over last ${trend.length} readings');
          }
        }
        buf.writeln();
      }
      buf.writeln();
    }

    final unlocked = _achievements.where((a) => a.isUnlocked).length;
    buf.writeln('— ACHIEVEMENTS —');
    buf.writeln('  $unlocked / ${_achievements.length} unlocked');
    buf.writeln();
    buf.writeln('Generated by Sage Health.');

    final reportText = buf.toString();
    await Clipboard.setData(ClipboardData(text: reportText));
    if (mounted) {
      // Show a bottom sheet so the user can read, select, and share the
      // report directly — more useful than a silent clipboard copy,
      // especially on iOS where clipboard confirmation is invisible.
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: SageColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: SageColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Wellness Report',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: reportText));
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Report copied to clipboard'),
                              backgroundColor: SageColors.moss,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: Icon(Icons.copy_outlined,
                          size: 16, color: SageColors.moss),
                      label: Text('Copy',
                          style: TextStyle(
                              fontSize: 13, color: SageColors.moss)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    reportText,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.55,
                      color: SageColors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ── Data loading ─────────────────────────────────────────────────────────
  //
  // Everything except band HR comes straight from BellaService and is
  // synchronous (Hive box is already open). Band data is the one async
  // read, kept separate so a slow/empty band history never blocks the
  // rest of the screen.

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final band = await _dataStorage.getBandData(daysBack: 14);

      final sessions = _bella.getSessions()
        ..sort((a, b) => a.date.compareTo(b.date));
      final checkins = _bella.getCheckins();
      final sleep = _bella.getSleepEntries();
      final food = _bella.getFoodEntries();

      final achievements = AchievementsService.instance.compute(sessions);
      final user = UserService().currentUserObject;
      final scoreResult = WellnessScoreService.compute(
        bella: _bella,
        chronicConditions: user?.chronicDiseases ?? const [],
      );
      final yesterdayScoreResult = WellnessScoreService.compute(
        bella: _bella,
        chronicConditions: user?.chronicDiseases ?? const [],
        asOf: DateTime.now().subtract(const Duration(days: 1)),
      );

      _calculateBmi();

      if (mounted) {
        setState(() {
          _allSessions = sessions;
          _checkins = checkins;
          _sleepEntries = sleep;
          _foodEntries = food;
          _bandData = band;
          _achievements = achievements;
          _scoreResult = scoreResult;
          _yesterdayScoreResult = yesterdayScoreResult;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('InsightsScreen._loadAll error: $e');
    }
  }

  void _calculateBmi() {
    final user = UserService().currentUserObject;
    if (user != null && user.height > 0 && user.weight > 0) {
      final h = user.height / 100;
      _bmi = user.weight / (h * h);
      if (_bmi < 18.5) {
        _bmiCategory = 'Underweight';
      } else if (_bmi < 25) {
        _bmiCategory = 'Normal';
      } else if (_bmi < 30) {
        _bmiCategory = 'Overweight';
      } else {
        _bmiCategory = 'Obese';
      }
    }
  }

  // ── Per-type session helpers ────────────────────────────────────────────

  List<WellnessSession> _byType(String type) =>
      _allSessions.where((s) => s.type == type).toList();

  int _minutesOf(List<WellnessSession> s) =>
      s.fold(0, (sum, e) => sum + e.durationMinutes);

  // ── Computed getters ──────────────────────────────────────────────────────

  /// Wellness score — computed once per load via WellnessScoreService, the
  /// single formula shared with WellnessScreen. This used to be a second,
  /// independently-drifting copy of the formula (different chronic-care
  /// baseline, different flag thresholds, different label breakpoints),
  /// which is exactly why the two screens could show 43-"Needs Care" and
  /// 44-"Take it easy" for the same data. Now there is only one number.
  int get _wellnessScore => _scoreResult?.overallScore ?? 0;

  bool _isReadingFlagged(String condition, ReadingEntry r) =>
      WellnessScoreService.isReadingFlagged(condition, r);

  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  int get _currentStreak {
    if (_allSessions.isEmpty) return 0;
    final days = _allSessions.map((s) => _dateKey(s.date)).toSet();
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

  int get _longestStreak {
    if (_allSessions.isEmpty) return 0;
    final sorted = _allSessions
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

  int get _thisWeekSessions {
    final now = DateTime.now();
    return _allSessions.where((s) => now.difference(s.date).inDays < 7).length;
  }

  int get _lastWeekSessions {
    final now = DateTime.now();
    return _allSessions.where((s) {
      final d = now.difference(s.date).inDays;
      return d >= 7 && d < 14;
    }).length;
  }

  /// Null when the band has never reported — more honest than a fake
  /// resting-HR default.
  int? get _avgHeartRate {
    final hrs = _bandData
        .where((d) => d['hr'] != null && (d['hr'] as int) > 0)
        .map((d) => d['hr'] as int)
        .toList();
    if (hrs.isEmpty) return null;
    return (hrs.reduce((a, b) => a + b) / hrs.length).round();
  }

  // ── Cross-metric helpers (used by Correlations card + Recommendations) ───

  double? _avgSleepInWindow({required int daysAgoStart, required int daysAgoEnd}) {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: daysAgoStart));
    final end = now.subtract(Duration(days: daysAgoEnd));
    final entries = _sleepEntries
        .where((e) => !e.isNap && e.date.isAfter(end) && e.date.isBefore(start.add(const Duration(days: 1))))
        .toList();
    if (entries.isEmpty) return null;
    return entries.map((e) => e.quality).reduce((a, b) => a + b) / entries.length;
  }

  double? _avgWellbeingInWindow({required int daysAgoStart, required int daysAgoEnd}) {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: daysAgoStart));
    final end = now.subtract(Duration(days: daysAgoEnd));
    final entries = _checkins
        .where((c) => c.time.isAfter(end) && c.time.isBefore(start.add(const Duration(days: 1))))
        .toList();
    if (entries.isEmpty) return null;
    return entries.map((c) => c.wellbeingScore).reduce((a, b) => a + b) / entries.length;
  }

  /// Does a good night's sleep actually predict whether the user shows up
  /// for an activity the next day? Walks every sleep entry that has a
  /// "next calendar day" in the data window and checks whether any session
  /// was logged that next day. Needs at least one night on each side to
  /// say anything at all — this is meant to surface as soon as there's
  /// real signal, not sit gated behind an arbitrary sample size.
  _SleepActivityLink? get _sleepActivityLink {
    final nonNap = _sleepEntries.where((e) => !e.isNap).toList();
    if (nonNap.isEmpty) return null;

    final sessionDays = _allSessions.map((s) => _dateKey(s.date)).toSet();

    int goodNights = 0, goodNightsFollowedByActivity = 0;
    int poorNights = 0, poorNightsFollowedByActivity = 0;
    int okNights = 0, okNightsFollowedByActivity = 0;

    for (final e in nonNap) {
      final nextDay = e.date.add(const Duration(days: 1));
      // Skip if "next day" is still in the future relative to today.
      if (nextDay.isAfter(DateTime.now())) continue;
      final activeNextDay = sessionDays.contains(_dateKey(nextDay));
      if (e.quality >= 4) {
        goodNights++;
        if (activeNextDay) goodNightsFollowedByActivity++;
      } else if (e.quality <= 2) {
        poorNights++;
        if (activeNextDay) poorNightsFollowedByActivity++;
      } else {
        okNights++;
        if (activeNextDay) okNightsFollowedByActivity++;
      }
    }

    if (goodNights == 0 && poorNights == 0) return null;

    return _SleepActivityLink(
      goodNightActivityPct:
          goodNights > 0 ? goodNightsFollowedByActivity / goodNights : null,
      poorNightActivityPct:
          poorNights > 0 ? poorNightsFollowedByActivity / poorNights : null,
      okNightActivityPct:
          okNights > 0 ? okNightsFollowedByActivity / okNights : null,
      goodNights: goodNights,
      poorNights: poorNights,
      okNights: okNights,
    );
  }

  Color get _scoreColor => WellnessScoreService.color(_wellnessScore);

  String get _scoreLabel => WellnessScoreService.label(_wellnessScore);

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SageColors.linen,
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 12),
                    const ShimmerHeroCard(),
                    const SizedBox(height: 16),
                    Row(
                      children: const [
                        Expanded(child: ShimmerMetricTile()),
                        SizedBox(width: 10),
                        Expanded(child: ShimmerMetricTile()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: const [
                        Expanded(child: ShimmerMetricTile()),
                        SizedBox(width: 10),
                        Expanded(child: ShimmerMetricTile()),
                      ],
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadAll,
                color: SageColors.moss,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      _buildTabBar(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: _tabs.index == 0
                            ? _buildOverviewTab()
                            : _buildAchievementsTab(),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Insights', style: SageText.headline()),
                const SizedBox(height: 2),
                Text(
                  'Your wellness at a glance',
                  style: TextStyle(fontSize: 13, color: SageColors.inkSoft),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.ios_share_rounded,
                color: SageColors.inkSoft, size: 20),
            onPressed: _exportReport,
            tooltip: 'Copy full report',
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: SageColors.inkSoft, size: 20),
            onPressed: _loadAll,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: SageColors.card,
          border: Border.all(color: SageColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TabBar(
          controller: _tabs,
          onTap: (i) {
            setState(() {});
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            }
          },
          labelColor: SageColors.linen,
          unselectedLabelColor: SageColors.inkSoft,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          indicator: BoxDecoration(
            color: SageColors.moss,
            borderRadius: BorderRadius.circular(8),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Achievements'),
          ],
        ),
      ),
    );
  }

  // ── OVERVIEW TAB ──────────────────────────────────────────────────────────

  Widget _buildOverviewTab() {
    final hasConditions =
        (UserService().currentUserObject?.chronicDiseases ?? []).isNotEmpty;
    return StaggerColumn(
      size: RevealSize.large,
      children: [
        _buildScoreHero(),
        const SizedBox(height: 16),
        _buildTrendStrip(),
        const SizedBox(height: 16),
        _buildActivityRing(),
        const SizedBox(height: 16),
        _buildWeekCompare(),
        const SizedBox(height: 16),
        _buildTotalsGrid(),
        const SizedBox(height: 16),
        _buildSleepTrend(),
        const SizedBox(height: 16),
        _buildMoodTrend(),
        const SizedBox(height: 16),
        _buildNutritionHydration(),
        const SizedBox(height: 16),
        _buildCorrelationsCard(),
        if (hasConditions) ...[
          const SizedBox(height: 16),
          _buildChronicReadings(),
        ],
        const SizedBox(height: 16),
        _buildPatterns(),
        const SizedBox(height: 16),
        _buildRecommendations(),
      ],
    );
  }

  Widget _buildScoreHero() {
    final score = _wellnessScore;
    final result = _scoreResult;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: SageColors.heroBg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Today's Wellness Score",
            style: TextStyle(fontSize: 12, color: SageColors.heroLabelMuted),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AnimatedNumber(
                value: score,
                duration: SageMotion.numberCountUp,
                style: SageText.mono(
                  size: 52,
                  weight: FontWeight.w500,
                  color: SageColors.heroNumber,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 6),
              Text('/ 100',
                  style: TextStyle(
                      fontSize: 15, color: SageColors.heroLabelMuted)),
              if (_yesterdayScoreResult != null) ...[
                const SizedBox(width: 8),
                _scoreDeltaChip(score, _yesterdayScoreResult!.overallScore),
              ],
              const Spacer(),
              // Flexible + FittedBox: at large accessibility text scales or
              // on narrow phones, "Needs Care" next to a 52pt number was
              // exactly the kind of fixed-width Row that throws a
              // RenderFlex overflow — this lets the badge shrink instead.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _scoreLabel,
                      style: TextStyle(
                          fontSize: 12,
                          color: SageColors.heroLabel,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor:
                  AlwaysStoppedAnimation<Color>(SageColors.heroAccentOk),
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 14),
            // The "how is it calculating this" answer, right under the bar:
            // the five weighted pillars that produce the number above, so
            // the score is never a black box.
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _pillarChip('Sleep', result.sleepScore, 30),
                _pillarChip('Nutrition', result.nutritionScore, 20),
                _pillarChip('Check-in', result.checkinScore, 20),
                _pillarChip('Activity', result.activityScore, 20),
                _pillarChip('Chronic', result.chronicScore, 10),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              _heroStat('Streak',
                  '$_currentStreak day${_currentStreak == 1 ? '' : 's'}'),
              _heroDivider(),
              _heroStat('Best', '$_longestStreak days'),
              _heroDivider(),
              _heroStat('This week', '$_thisWeekSessions sessions'),
            ],
          ),
        ],
      ),
    );
  }

  /// "+6 vs yesterday" / "-3 vs yesterday" / "Same as yesterday" — both
  /// scores come from the exact same WellnessScoreService formula, just
  /// evaluated for two different days, so this is a real comparison, not
  /// an approximation.
  Widget _scoreDeltaChip(int today, int yesterday) {
    final diff = today - yesterday;
    final Color c;
    final IconData icon;
    final String text;
    if (diff > 0) {
      c = SageColors.heroAccentOk;
      icon = Icons.arrow_upward_rounded;
      text = '+$diff';
    } else if (diff < 0) {
      c = SageColors.heroAccentWarn;
      icon = Icons.arrow_downward_rounded;
      text = '$diff';
    } else {
      c = SageColors.heroLabelMuted;
      icon = Icons.remove_rounded;
      text = '0';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 2),
          Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _pillarChip(String label, int score, int weightPct) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $score · ${weightPct}%',
        style: TextStyle(fontSize: 10, color: SageColors.heroLabelMuted),
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: SageText.mono(
                  size: 16,
                  weight: FontWeight.w600,
                  color: SageColors.heroNumber),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(fontSize: 11, color: SageColors.heroLabelMuted)),
        ],
      ),
    );
  }

  Widget _heroDivider() => Container(
        width: 1,
        height: 28,
        color: Colors.white.withValues(alpha: 0.18),
      );

  /// 14-day activity trend — a real, boring-on-purpose detail strip showing
  /// session count per day, oldest to newest, scrollable if it overflows.
  Widget _buildTrendStrip() {
    final now = DateTime.now();
    final windowDays = _trendDays;
    final days =
        List.generate(windowDays, (i) => now.subtract(Duration(days: windowDays - 1 - i)));
    final counts = days.map((d) {
      final key = _dateKey(d);
      return _allSessions.where((s) => _dateKey(s.date) == key).length;
    }).toList();
    final maxCount = counts.isEmpty ? 1 : max(1, counts.reduce(max));
    final totalThisWindow = counts.fold(0, (a, b) => a + b);
    // 30 narrow bars can't each carry a count label and a day-of-month
    // label without overlapping — show labels every few bars instead of
    // every single one once the window gets wide.
    final labelStride = windowDays <= 14 ? 1 : (windowDays / 8).ceil();

    return _card(
      accent: SageColors.moss,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _sectionTitle('$windowDays-day activity',
                    Icons.show_chart_rounded, SageColors.moss),
              ),
              _trendWindowToggle(),
            ],
          ),
          const SizedBox(height: 4),
          Text('$totalThisWindow sessions in this window',
              style: TextStyle(fontSize: 11, color: SageColors.inkSoft)),
          const SizedBox(height: 16),
          if (totalThisWindow == 0)
            _emptyState(
              icon: Icons.show_chart_rounded,
              title: 'No activity in the last $windowDays days',
              subtitle: 'Complete any wellness activity to start your trend.',
            )
          else
            SizedBox(
              height: 88,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(windowDays, (i) {
                  final c = counts[i];
                  final isToday = i == windowDays - 1;
                  final showLabel = i % labelStride == 0 || isToday;
                  final h = max(4.0, 40.0 * (c / maxCount));
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            height: 13,
                            child: (c > 0 && windowDays <= 14)
                                ? Text('$c',
                                    style: TextStyle(
                                        fontSize: 8.5,
                                        color: SageColors.inkSoft))
                                : null,
                          ),
                          const SizedBox(height: 2),
                          AnimatedContainer(
                            duration: SageMotion.numberCountUp,
                            height: h,
                            decoration: BoxDecoration(
                              color: c > 0
                                  ? (isToday ? SageColors.amber : SageColors.moss)
                                  : SageColors.line,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 11,
                            child: showLabel
                                ? Text(
                                    '${days[i].day}',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      color: isToday
                                          ? SageColors.amber
                                          : SageColors.inkSoft,
                                      fontWeight: isToday
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trendWindowToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [14, 30].map((d) {
        final selected = d == _trendDays;
        return Pressable(
          onTap: () => setState(() => _trendDays = d),
          child: Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? SageColors.moss : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected ? SageColors.moss : SageColors.line),
            ),
            child: Text(
              '${d}d',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? SageColors.linen : SageColors.inkSoft,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActivityRing() {
    final medSessions = _byType('meditation');
    final walkSessions = _byType('walking');
    final breathSessions = _byType('breathwork');
    final ssSessions = _byType('sleep_sounds');
    final med = medSessions.length;
    final walk = walkSessions.length;
    final breath = breathSessions.length;
    final ss = ssSessions.length;
    final total = med + walk + breath + ss;

    if (total == 0) {
      return _card(
        child: _emptyState(
          icon: Icons.bar_chart_rounded,
          title: 'No sessions yet',
          subtitle: 'Complete a wellness activity to see your breakdown here.',
        ),
      );
    }

    return _card(
      accent: SageColors.clay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
              'Activity breakdown', Icons.donut_small_rounded, SageColors.clay),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: _DonutChart(
                  segments: [
                    _DonutSegment(med.toDouble(), SageColors.moss),
                    _DonutSegment(walk.toDouble(), SageColors.clay),
                    _DonutSegment(breath.toDouble(), SageColors.amber),
                    _DonutSegment(ss.toDouble(), const Color(0xFF5D6D7E)),
                  ],
                  center: '$total',
                  centerLabel: 'total',
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    _legendRow('Meditation', med, total, SageColors.moss),
                    const SizedBox(height: 8),
                    _legendRow('Walking', walk, total, SageColors.clay),
                    const SizedBox(height: 8),
                    _legendRow('Breathwork', breath, total, SageColors.amber),
                    const SizedBox(height: 8),
                    _legendRow(
                        'Sleep sounds', ss, total, const Color(0xFF5D6D7E)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._activityComments(
            medMinutes: _minutesOf(medSessions),
            walkMinutes: _minutesOf(walkSessions),
            breathMinutes: _minutesOf(breathSessions),
            ssMinutes: _minutesOf(ssSessions),
            meditationPoses: medSessions
                .map((s) => s.detail)
                .whereType<String>()
                .where((t) => t.isNotEmpty)
                .toSet(),
            breathTechniques: breathSessions
                .map((s) => s.detail)
                .whereType<String>()
                .where((t) => t.isNotEmpty)
                .toSet(),
          ),
        ],
      ),
    );
  }

  /// Turns the raw all-time minutes per activity into plain-English read-out
  /// lines instead of leaving the donut/legend to speak for itself. This is
  /// the "comment on it" treatment applied to the activity breakdown.
  List<Widget> _activityComments({
    required int medMinutes,
    required int walkMinutes,
    required int breathMinutes,
    required int ssMinutes,
    Set<String> meditationPoses = const {},
    Set<String> breathTechniques = const {},
  }) {
    const benefits = {
      'meditation': 'linked to lower stress reactivity and steadier focus',
      'walking': 'supports cardiovascular health and mood',
      'breathwork': 'can measurably lower resting heart rate in the short term',
      'sleep_sounds': 'helps with easier wind-down and sleep onset',
    };
    final entries = <MapEntry<String, int>>[
      MapEntry('meditation', medMinutes),
      MapEntry('walking', walkMinutes),
      MapEntry('breathwork', breathMinutes),
      MapEntry('sleep_sounds', ssMinutes),
    ].where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) return const [];

    final lines = <Widget>[];
    for (final e in entries) {
      final label = e.key == 'sleep_sounds' ? 'sleep sounds' : e.key;
      final qualifier = e.value < 10
          ? "That's a light dose so far — "
          : e.value < 60
              ? "A solid running total — "
              : "A real, sustained habit — ";
      String diversityClause = '';
      if (e.key == 'meditation' && meditationPoses.isNotEmpty) {
        diversityClause = meditationPoses.length == 1
            ? ' Always the same pose so far (${meditationPoses.first}) — '
                'trying another could keep it from going stale.'
            : ' Spread across ${meditationPoses.length} different poses '
                '(${meditationPoses.join(', ')}).';
      } else if (e.key == 'breathwork' && breathTechniques.isNotEmpty) {
        diversityClause = breathTechniques.length == 1
            ? ' Always the same technique so far (${breathTechniques.first}) — '
                'different techniques suit different moments (e.g. Box '
                'Breathing for calm, 4-7-8 for sleep).'
            : ' Spread across ${breathTechniques.length} different '
                'techniques (${breathTechniques.join(', ')}).';
      }
      lines.add(_insightRow(
        icon: e.key == 'meditation'
            ? Icons.self_improvement
            : e.key == 'walking'
                ? Icons.directions_walk
                : e.key == 'breathwork'
                    ? Icons.air
                    : Icons.nightlight_round,
        color: e.key == 'meditation'
            ? const Color(0xFF9B59B6)
            : e.key == 'walking'
                ? SageColors.clay
                : e.key == 'breathwork'
                    ? SageColors.amber
                    : const Color(0xFF5D6D7E),
        text: '${e.value} total minutes of $label. $qualifier'
            '${benefits[e.key]}, though the effect scales with consistency, '
            'not any single session.$diversityClause',
      ));
      lines.add(const SizedBox(height: 8));
    }
    if (lines.isNotEmpty) lines.removeLast();
    return lines;
  }

  Widget _legendRow(String label, int count, int total, Color color) {
    final pct = total > 0 ? count / total : 0.0;
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 12, color: SageColors.ink))),
        Text('$count', style: SageText.mono(size: 12, color: SageColors.inkSoft)),
        const SizedBox(width: 6),
        SizedBox(
          width: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: SageColors.line,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekCompare() {
    final thisWeek = _thisWeekSessions;
    final lastWeek = _lastWeekSessions;
    final diff = thisWeek - lastWeek;
    final pct = lastWeek > 0
        ? (diff / lastWeek * 100).round().abs()
        : thisWeek > 0
            ? 100
            : 0;

    final String trend;
    final Color trendColor;
    final IconData trendIcon;
    if (diff > 0) {
      trend = '+$pct% vs last week';
      trendColor = SageColors.moss;
      trendIcon = Icons.trending_up_rounded;
    } else if (diff < 0) {
      trend = '$pct% fewer sessions';
      trendColor = SageColors.clay;
      trendIcon = Icons.trending_down_rounded;
    } else {
      trend = 'Same as last week';
      trendColor = SageColors.inkSoft;
      trendIcon = Icons.trending_flat_rounded;
    }

    return _card(
      accent: SageColors.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
              'Week-over-week', Icons.compare_arrows_rounded, SageColors.amber),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  label: 'This week',
                  value: '$thisWeek',
                  unit: 'sessions',
                  color: SageColors.moss,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statTile(
                  label: 'Last week',
                  value: '$lastWeek',
                  unit: 'sessions',
                  color: SageColors.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: trendColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(trendIcon, size: 16, color: trendColor),
                const SizedBox(width: 6),
                Text(trend,
                    style: TextStyle(
                        fontSize: 13,
                        color: trendColor,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Detailed all-time totals & vitals — the "boring detail" dashboard:
  /// minutes per activity, streaks, avg HR, BMI, all in one scan.
  /// Sessions restricted to a specific period — backs the Today / Yesterday
  /// / Last 14 Days selector on the totals card. This is the direct fix for
  /// "it said 13 minutes but I only did 7" — that 13 was an unlabeled
  /// all-time total quietly including earlier test sessions. Splitting it
  /// out by period makes the number's scope explicit instead of implicit.
  List<WellnessSession> _sessionsForPeriod(_TotalsPeriod p) {
    final now = DateTime.now();
    switch (p) {
      case _TotalsPeriod.today:
        return _allSessions.where((s) => _dateKey(s.date) == _dateKey(now)).toList();
      case _TotalsPeriod.yesterday:
        final y = now.subtract(const Duration(days: 1));
        return _allSessions.where((s) => _dateKey(s.date) == _dateKey(y)).toList();
      case _TotalsPeriod.last14:
        return _allSessions.where((s) => now.difference(s.date).inDays < 14).toList();
    }
  }

  String _periodLabel(_TotalsPeriod p) {
    switch (p) {
      case _TotalsPeriod.today:
        return 'Today';
      case _TotalsPeriod.yesterday:
        return 'Yesterday';
      case _TotalsPeriod.last14:
        return 'Last 14 days';
    }
  }

  Widget _buildTotalsGrid() {
    final periodSessions = _sessionsForPeriod(_totalsPeriod);
    final medMin = _minutesOf(periodSessions.where((s) => s.type == 'meditation').toList());
    final walkMin = _minutesOf(periodSessions.where((s) => s.type == 'walking').toList());
    final breathMin = _minutesOf(periodSessions.where((s) => s.type == 'breathwork').toList());
    final ssMin = _minutesOf(periodSessions.where((s) => s.type == 'sleep_sounds').toList());
    final avgHr = _avgHeartRate;
    final avgSleep = _bella.averageSleepQuality();
    final avgWellbeing = _bella.averageWellbeing();
    // Only sessions logged after step-tracking was added carry this — older
    // sessions just contribute 0, they don't crash or get excluded.
    final totalSteps = _byType('walking')
        .fold<int>(0, (s, e) => s + (int.tryParse(e.detail ?? '') ?? 0));

    // Personal best: the single walk with the highest step count.
    final walkStepCounts = _byType('walking')
        .map((s) => int.tryParse(s.detail ?? '') ?? 0)
        .where((n) => n > 0)
        .toList();
    final bestSteps = walkStepCounts.isEmpty
        ? 0
        : walkStepCounts.reduce((a, b) => a > b ? a : b);
    // Find the date of that best walk so we can name it.
    WellnessSession? bestWalk;
    if (bestSteps > 0) {
      bestWalk = _byType('walking').firstWhere(
        (s) => (int.tryParse(s.detail ?? '') ?? 0) == bestSteps,
        orElse: () => _byType('walking').first,
      );
    }

    return _card(
      accent: SageColors.moss,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
              'Activity totals', Icons.analytics_rounded, SageColors.moss),
          const SizedBox(height: 14),
          // Today / Yesterday / Last 14 Days — explicit period selector so
          // every number on this card states its own scope.
          Row(
            children: _TotalsPeriod.values.map((p) {
              final selected = p == _totalsPeriod;
              return Expanded(
                child: Pressable(
                  onTap: () => setState(() => _totalsPeriod = p),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? SageColors.moss : SageColors.linen,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: selected ? SageColors.moss : SageColors.line),
                    ),
                    child: Text(
                      _periodLabel(p),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? SageColors.linen : SageColors.inkSoft,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          if (periodSessions.isEmpty)
            _emptyState(
              icon: Icons.event_busy_rounded,
              title: 'Nothing logged ${_periodLabel(_totalsPeriod).toLowerCase()}',
              subtitle: _totalsPeriod == _TotalsPeriod.today
                  ? 'Complete any activity today and it\'ll show up here immediately.'
                  : 'No sessions fall in this window yet.',
            )
          else ...[
            _statsGrid([
              _StatItem('Meditation', '$medMin min', const Color(0xFF9B59B6)),
              _StatItem('Walking', '$walkMin min', SageColors.clay),
              _StatItem('Breathwork', '$breathMin min', SageColors.amber),
              _StatItem('Sleep sounds', '$ssMin min', const Color(0xFF5D6D7E)),
            ]),
            const SizedBox(height: 10),
            _insightRow(
              icon: Icons.info_outline,
              color: SageColors.moss,
              text: '${_periodLabel(_totalsPeriod)}: ${periodSessions.length} '
                  'session${periodSessions.length == 1 ? '' : 's'} totaling '
                  '${medMin + walkMin + breathMin + ssMin} minutes across all '
                  'activity types.',
            ),
          ],
          const SizedBox(height: 18),
          Container(height: 1, color: SageColors.line),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.all_inclusive_rounded, size: 14, color: SageColors.inkSoft),
              const SizedBox(width: 6),
              Text('ALL-TIME VITALS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: SageColors.inkSoft)),
            ],
          ),
          const SizedBox(height: 10),
          _statsGrid([
            _StatItem('All-time sessions', '${_allSessions.length}',
                SageColors.moss),
            _StatItem('Longest streak', '$_longestStreak days',
                SageColors.clay),
            _StatItem('Avg heart rate', avgHr != null ? '$avgHr bpm' : '—',
                SageColors.moss),
            _StatItem(
                'Avg sleep quality',
                avgSleep != null ? '${avgSleep.toStringAsFixed(1)}/5' : '—',
                const Color(0xFF5D6D7E)),
            _StatItem(
                'Avg wellbeing',
                avgWellbeing != null
                    ? '${avgWellbeing.toStringAsFixed(1)}/10'
                    : '—',
                SageColors.amber),
            _StatItem(
                'BMI', '${_bmi.toStringAsFixed(1)} · $_bmiCategory',
                SageColors.ink),
            _StatItem(
                'Total steps',
                totalSteps > 0 ? '$totalSteps' : '—',
                const Color(0xFF229954)),
            _StatItem(
                'Personal best walk',
                bestSteps > 0 ? '$bestSteps steps' : '—',
                const Color(0xFF1A7A44)),
          ]),
          if (bestSteps > 0 && bestWalk != null) ...[
            const SizedBox(height: 10),
            _insightRow(
              icon: Icons.emoji_events_outlined,
              color: const Color(0xFF1A7A44),
              text: 'Personal best: $bestSteps steps on '
                  '${_shortDate(bestWalk.date)}. '
                  '${bestSteps >= 10000 ? 'That\'s a 10,000-step day — great work.' : bestSteps >= 7500 ? 'That\'s a strong walk.' : 'Every walk builds the habit.'}',
            ),
          ],
        ],
      ),
    );
  }

  /// Last 7 nights of sleep quality, day by day.
  Widget _buildSleepTrend() {
    final now = DateTime.now();
    final days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));

    final entries = days.map((d) {
      final forDay = _sleepEntries
          .where((e) =>
              e.date.year == d.year &&
              e.date.month == d.month &&
              e.date.day == d.day)
          .toList();
      if (forDay.isEmpty) return null;
      final nonNap = forDay.where((e) => !e.isNap).toList();
      return nonNap.isNotEmpty ? nonNap.first : forDay.first;
    }).toList();

    final loggedCount = entries.where((e) => e != null).length;

    return _card(
      accent: const Color(0xFF5D6D7E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Sleep — last 7 nights', Icons.nightlight_round,
              const Color(0xFF5D6D7E)),
          const SizedBox(height: 16),
          if (loggedCount == 0)
            _emptyState(
              icon: Icons.nightlight_round,
              title: 'No sleep logged this week',
              subtitle: 'Log a night in ZZZify to see your quality trend.',
            )
          else
            SizedBox(
              height: 78,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (i) {
                  final e = entries[i];
                  final d = days[i];
                  final label =
                      ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1];
                  final quality = e?.quality ?? 0;
                  final color = quality == 0
                      ? SageColors.line
                      : quality >= 4
                          ? SageColors.moss
                          : quality == 3
                              ? SageColors.amber
                              : SageColors.clay;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(quality > 0 ? '$quality' : '–',
                              style: TextStyle(
                                  fontSize: 10, color: SageColors.inkSoft)),
                          const SizedBox(height: 3),
                          Container(
                            height: max(4.0, 36.0 * (quality / 5)),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(label,
                              style: TextStyle(
                                  fontSize: 10.5, color: SageColors.inkSoft)),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          if (loggedCount > 0) ...[
            const SizedBox(height: 12),
            ..._sleepTrendComments(entries, days),
          ],
        ],
      ),
    );
  }

  /// Plain-English read-out of the 7-night sleep chart: best/worst night,
  /// how many nights are missing, and whether it's trending up or down.
  List<Widget> _sleepTrendComments(
      List<SleepEntry?> entries, List<DateTime> days) {
    final logged = <MapEntry<SleepEntry, DateTime>>[];
    for (int i = 0; i < entries.length; i++) {
      if (entries[i] != null) logged.add(MapEntry(entries[i]!, days[i]));
    }
    if (logged.isEmpty) return const [];

    final avg = logged.map((e) => e.key.quality).reduce((a, b) => a + b) /
        logged.length;
    final best = logged.reduce(
        (a, b) => a.key.quality >= b.key.quality ? a : b);
    final worst = logged.reduce(
        (a, b) => a.key.quality <= b.key.quality ? a : b);
    final missing = 7 - logged.length;
    final napCount = logged.where((e) => e.key.isNap).length;
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final parts = <String>[];
    parts.add('This week averaged ${avg.toStringAsFixed(1)}/5 across '
        '${logged.length} logged night${logged.length == 1 ? '' : 's'}'
        '${missing > 0 ? ' ($missing night${missing == 1 ? '' : 's'} not logged)' : ''}.');
    if (best.key.quality != worst.key.quality) {
      parts.add('Best: ${dayNames[best.value.weekday - 1]} '
          '(${best.key.quality}/5). Worst: '
          '${dayNames[worst.value.weekday - 1]} (${worst.key.quality}/5).');
    }
    if (napCount > 0) {
      parts.add('$napCount of those were logged as naps, not full nights.');
    }
    if (avg >= 4) {
      parts.add('That\'s a strong week for sleep — keep whatever you\'re doing.');
    } else if (avg < 2.5) {
      parts.add('That\'s a tough stretch — consider sleep sounds or an '
          'earlier wind-down a few nights this week.');
    }

    return [
      _insightRow(
        icon: Icons.nightlight_round,
        color: const Color(0xFF5D6D7E),
        text: parts.join(' '),
      ),
    ];
  }

  /// Last 7 days of check-in wellbeing (mood/energy/stress blended).
  Widget _buildMoodTrend() {
    final now = DateTime.now();
    final days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));

    final entries = days.map((d) {
      final forDay = _checkins
          .where((c) =>
              c.time.year == d.year &&
              c.time.month == d.month &&
              c.time.day == d.day)
          .toList();
      return forDay.isEmpty ? null : forDay.first;
    }).toList();

    final loggedCount = entries.where((e) => e != null).length;

    return _card(
      accent: SageColors.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Mood & check-ins — last 7 days', Icons.mood,
              SageColors.amber),
          const SizedBox(height: 16),
          if (loggedCount == 0)
            _emptyState(
              icon: Icons.mood,
              title: 'No check-ins this week',
              subtitle:
                  'A daily check-in helps Sage understand how you\'re doing.',
            )
          else
            SizedBox(
              height: 78,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (i) {
                  final c = entries[i];
                  final d = days[i];
                  final label =
                      ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1];
                  final score = c?.wellbeingScore ?? 0;
                  final color = c == null
                      ? SageColors.line
                      : score >= 7
                          ? SageColors.moss
                          : score >= 4.5
                              ? SageColors.amber
                              : SageColors.clay;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(c != null ? score.toStringAsFixed(0) : '–',
                              style: TextStyle(
                                  fontSize: 10, color: SageColors.inkSoft)),
                          const SizedBox(height: 3),
                          Container(
                            height: max(4.0, 36.0 * (score / 10)),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(label,
                              style: TextStyle(
                                  fontSize: 10.5, color: SageColors.inkSoft)),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          if (loggedCount > 0) ...[
            const SizedBox(height: 12),
            ..._moodTrendComments(entries, days),
          ],
        ],
      ),
    );
  }

  /// Plain-English read-out of the 7-day check-in chart, including the
  /// individual mood/stress/energy components (not just the blended score)
  /// so a low day can actually be diagnosed, not just flagged.
  List<Widget> _moodTrendComments(
      List<CheckinEntry?> entries, List<DateTime> days) {
    final logged = entries.whereType<CheckinEntry>().toList();
    if (logged.isEmpty) return const [];

    final avgScore =
        logged.map((c) => c.wellbeingScore).reduce((a, b) => a + b) /
            logged.length;
    final avgStress =
        logged.map((c) => c.stress).reduce((a, b) => a + b) / logged.length;
    final avgEnergy =
        logged.map((c) => c.energy).reduce((a, b) => a + b) / logged.length;
    final missing = 7 - logged.length;

    final parts = <String>[];
    parts.add('This week averaged ${avgScore.toStringAsFixed(1)}/10 '
        'wellbeing across ${logged.length} check-in${logged.length == 1 ? '' : 's'}'
        '${missing > 0 ? ' ($missing day${missing == 1 ? '' : 's'} not logged)' : ''}.');
    parts.add('Average stress ${avgStress.toStringAsFixed(1)}/5, '
        'average energy ${avgEnergy.toStringAsFixed(1)}/5.');
    if (avgStress >= 3.5 && avgEnergy <= 2.5) {
      parts.add('That\'s a stress-heavy, low-energy week — calming activities '
          '(breathwork, meditation) are likely to move the needle more than '
          'high-output ones right now.');
    } else if (avgScore >= 7) {
      parts.add('A genuinely good week — worth noting what was different.');
    }

    return [
      _insightRow(
        icon: Icons.mood,
        color: SageColors.amber,
        text: parts.join(' '),
      ),
    ];
  }

  /// Nutrition logging + hydration vs target, last 7 days.
  Widget _buildNutritionHydration() {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final weekFood = _foodEntries.where((f) => f.time.isAfter(weekAgo)).toList();
    final daysWithFood = weekFood.map((f) => _dateKey(f.time)).toSet().length;
    final loggedCalDays =
        weekFood.where((f) => f.calories != null).toList();
    final avgCalories = loggedCalDays.isNotEmpty
        ? (loggedCalDays.fold<int>(0, (s, f) => s + (f.calories ?? 0)) /
                daysWithFood.clamp(1, 7))
            .round()
        : null;

    final todayWater = _bella.todayWaterMl();
    final waterTarget = _bella.getTarget<int>('waterMl') ?? 2000;
    final waterPct = (todayWater / waterTarget).clamp(0.0, 1.0);

    return _card(
      accent: SageColors.clay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Nutrition & hydration', Icons.water_drop_outlined,
              SageColors.clay),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  label: "Today's water",
                  value: '$todayWater',
                  unit: 'of $waterTarget ml',
                  color: SageColors.clay,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statTile(
                  label: 'Meals logged (7d)',
                  value: '${weekFood.length}',
                  unit: 'across $daysWithFood day${daysWithFood == 1 ? '' : 's'}',
                  color: SageColors.moss,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: waterPct,
              minHeight: 8,
              backgroundColor: SageColors.line,
              valueColor: AlwaysStoppedAnimation<Color>(SageColors.clay),
            ),
          ),
          const SizedBox(height: 12),
          ..._nutritionComments(
            todayWater: todayWater,
            waterTarget: waterTarget,
            waterPct: waterPct,
            weekFood: weekFood,
            daysWithFood: daysWithFood,
            avgCalories: avgCalories,
          ),
        ],
      ),
    );
  }

  List<Widget> _nutritionComments({
    required int todayWater,
    required int waterTarget,
    required double waterPct,
    required List<FoodEntry> weekFood,
    required int daysWithFood,
    required int? avgCalories,
  }) {
    final parts = <String>[];

    if (todayWater == 0) {
      parts.add('No water logged yet today.');
    } else if (waterPct >= 1) {
      parts.add('Today\'s water target is met.');
    } else {
      parts.add('Today you\'re at ${(waterPct * 100).round()}% of your '
          '${waterTarget}ml water target.');
    }

    if (weekFood.isEmpty) {
      parts.add('No meals logged this week — nutrition scoring will stay '
          'low until something is logged.');
    } else {
      parts.add('You logged food on $daysWithFood of the last 7 days.');
      if (avgCalories != null) {
        parts.add('Averaging ~$avgCalories kcal on the days you tracked.');
        if (avgCalories < 1200) {
          parts.add('That\'s on the low side — worth checking it\'s not '
              'under-logging rather than under-eating.');
        } else if (avgCalories > 3000) {
          parts.add('That\'s on the high side for most adults — context '
              '(activity level, goals) matters here.');
        }
      }
      final highSodium =
          weekFood.where((f) => f.tag == 'high-sodium').length;
      final highCarb = weekFood.where((f) => f.tag == 'high-carb').length;
      if (highSodium > 0) {
        parts.add('$highSodium item${highSodium == 1 ? '' : 's'} tagged '
            'high-sodium this week.');
      }
      if (highCarb > 0) {
        parts.add('$highCarb item${highCarb == 1 ? '' : 's'} tagged '
            'high-carb this week.');
      }
      // Late-night eating pattern
      final lateEntries = weekFood.where((f) {
        final h = f.time.hour;
        return h >= 21 || h < 2;
      }).length;
      if (lateEntries >= 3) {
        parts.add('$lateEntries late-night meals logged this week '
            '(after 9 PM) — that can affect sleep quality.');
      } else if (lateEntries > 0 && lateEntries < 3) {
        parts.add('$lateEntries late-night meal${lateEntries == 1 ? '' : 's'} '
            'this week — keep an eye on timing if sleep has been off.');
      }
    }

    return [
      _insightRow(
        icon: Icons.restaurant_outlined,
        color: SageColors.clay,
        text: parts.join(' '),
      ),
    ];
  }

  /// Latest reading + flag status for each chronic condition the user has
  /// set in their profile. Only rendered when conditions exist.
  Widget _buildChronicReadings() {
    final user = UserService().currentUserObject;
    final conditions = user?.chronicDiseases ?? [];

    return _card(
      accent: SageColors.clay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Chronic care readings', Icons.monitor_heart_outlined,
              SageColors.clay),
          const SizedBox(height: 16),
          ...conditions.map((cond) {
            final readings = _bella.getReadings(condition: cond);
            final latest = readings.isNotEmpty ? readings.first : null;
            final flagged =
                latest != null && _isReadingFlagged(cond, latest);
            // Trend: same condition + same reading type, oldest-to-newest,
            // so blood pressure and blood glucose (say) don't get mixed
            // into one meaningless line if a condition has more than one
            // type of reading logged against it.
            final trend = latest != null
                ? _bella.readingTrend(cond, latest.type, n: 14)
                : <ReadingEntry>[];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (flagged ? SageColors.clay : SageColors.moss)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          flagged
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          size: 18,
                          color: flagged ? SageColors.clay : SageColors.moss,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cond,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                latest == null
                                    ? 'No readings logged yet'
                                    : '${latest.type}: ${latest.value.toStringAsFixed(0)}'
                                        '${latest.secondaryValue != null ? '/${latest.secondaryValue!.toStringAsFixed(0)}' : ''}'
                                        ' ${latest.unit} · '
                                        '${_relativeTime(latest.time)}',
                                style: TextStyle(
                                    fontSize: 11.5, color: SageColors.inkSoft),
                              ),
                            ],
                          ),
                        ),
                        if (trend.length >= 2)
                          SizedBox(
                            width: 64,
                            height: 28,
                            child: _Sparkline(
                              values: trend.map((r) => r.value).toList(),
                              color: flagged ? SageColors.clay : SageColors.moss,
                            ),
                          ),
                      ],
                    ),
                    if (trend.length >= 2) ...[
                      const SizedBox(height: 8),
                      Text(
                        _readingTrendComment(cond, trend),
                        style: TextStyle(
                            fontSize: 11, color: SageColors.inkSoft, height: 1.3),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Plain-English read on a reading trend: is it improving, worsening, or
  /// holding steady, and by roughly how much — instead of just "here's a
  /// little squiggle, good luck." Direction of "better" depends on the
  /// condition (lower is better for glucose/BP; higher is better for peak
  /// flow), so this isn't just "number went up = bad."
  String _readingTrendComment(String condition, List<ReadingEntry> trend) {
    final first = trend.first.value;
    final last = trend.last.value;
    final change = last - first;
    final pctChange = first != 0 ? (change / first * 100) : 0;
    final type = trend.last.type;

    // Asthma (peak flow): higher is better. Everything else here: lower
    // is generally the safer direction.
    final higherIsBetter = condition == 'Asthma';
    final improved = higherIsBetter ? change > 0 : change < 0;
    final flat = pctChange.abs() < 3;

    final span = '${trend.length} readings';
    if (flat) {
      return '$type has been steady over your last $span '
          '(${first.toStringAsFixed(0)} → ${last.toStringAsFixed(0)} ${trend.last.unit}).';
    }
    return '$type has ${improved ? 'improved' : 'moved the wrong way'} over '
        'your last $span: ${first.toStringAsFixed(0)} → '
        '${last.toStringAsFixed(0)} ${trend.last.unit} '
        '(${change > 0 ? '+' : ''}${change.toStringAsFixed(0)}). '
        '${improved ? 'Keep doing whatever you\'re doing.' : 'Worth a mention at your next checkup if this continues.'}';
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Connects the dots between data sources instead of showing them in
  /// isolation: does good sleep actually predict showing up the next day,
  /// and how is sleep/mood trending week over week (not just session count).
  Widget _buildCorrelationsCard() {
    final link = _sleepActivityLink;

    final sleepThis = _avgSleepInWindow(daysAgoStart: 6, daysAgoEnd: 0);
    final sleepLast = _avgSleepInWindow(daysAgoStart: 13, daysAgoEnd: 7);
    final moodThis = _avgWellbeingInWindow(daysAgoStart: 6, daysAgoEnd: 0);
    final moodLast = _avgWellbeingInWindow(daysAgoStart: 13, daysAgoEnd: 7);

    final rows = <Widget>[];

    // ── Layer 1: read EVERYTHING logged today, with a comment on each.
    // This layer never needs multiple days of history, so it's the part
    // that should always have something to say the moment any data exists
    // — multi-day correlations below this are a bonus once there's enough
    // history, not a gate on the whole card.
    rows.addAll(_todaysFullReadout());

    // ── Layer 2: multi-day correlations — only meaningful once there's
    // more than a single day of history, so these stay conditional.
    if (link != null) {
      final goodPct = link.goodNightActivityPct != null
          ? (link.goodNightActivityPct! * 100).round()
          : null;
      final poorPct = link.poorNightActivityPct != null
          ? (link.poorNightActivityPct! * 100).round()
          : null;
      if (goodPct != null && poorPct != null) {
        final pp = goodPct - poorPct;
        rows.add(_insightRow(
          icon: Icons.bedtime_outlined,
          color: const Color(0xFF5D6D7E),
          text: pp.abs() > 5
              ? 'After a good night\'s sleep (4–5/5), you\'re active $goodPct% of '
                  'the next day — vs $poorPct% after a poor night (1–2/5), across '
                  '${link.goodNights + link.poorNights} tracked nights.'
              : 'Across ${link.goodNights + link.poorNights} tracked nights, sleep '
                  'quality hasn\'t shown a strong link to next-day activity yet — '
                  'keep logging both to sharpen this.',
        ));
      } else if (link.goodNights + link.poorNights + link.okNights > 0) {
        rows.add(_insightRow(
          icon: Icons.bedtime_outlined,
          color: const Color(0xFF5D6D7E),
          text: 'You have ${link.goodNights + link.poorNights + link.okNights} '
              'night${(link.goodNights + link.poorNights + link.okNights) == 1 ? '' : 's'} '
              'of sleep logged with a "next day" to compare against, but not yet '
              'both a good night and a poor night — once you do, Sage will '
              'compare next-day activity between them here.',
        ));
      }
    }

    if (sleepThis != null && sleepLast != null) {
      final delta = sleepThis - sleepLast;
      if (delta.abs() >= 0.3) {
        rows.add(_insightRow(
          icon: delta > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          color: delta > 0 ? SageColors.moss : SageColors.clay,
          text: 'Sleep quality is averaging ${sleepThis.toStringAsFixed(1)}/5 this '
              'week vs ${sleepLast.toStringAsFixed(1)}/5 last week '
              '(${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}).',
        ));
      }
    }

    if (moodThis != null && moodLast != null) {
      final delta = moodThis - moodLast;
      if (delta.abs() >= 0.6) {
        rows.add(_insightRow(
          icon: delta > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          color: delta > 0 ? SageColors.moss : SageColors.clay,
          text: 'Check-in wellbeing is averaging ${moodThis.toStringAsFixed(1)}/10 '
              'this week vs ${moodLast.toStringAsFixed(1)}/10 last week '
              '(${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}).',
        ));
      }
    }

    return _card(
      accent: const Color(0xFF2E9E6B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Connections', Icons.hub_outlined, const Color(0xFF2E9E6B)),
          const SizedBox(height: 4),
          Text(
            'Everything Sage has on file, read together instead of in isolation.',
            style: TextStyle(fontSize: 11.5, color: SageColors.inkSoft),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            _emptyState(
              icon: Icons.hub_outlined,
              title: 'Nothing logged anywhere yet',
              subtitle:
                  'Log a sleep entry, a check-in, or any activity and Sage will '
                  'start reading it back to you here — no waiting period needed.',
            )
          else
            Column(
              children: [
                for (int i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i != rows.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }

  /// Reads back literally everything on file for "today" (and, where
  /// nothing exists today, the most recent entry of each kind instead of
  /// going silent) — sleep, check-in, food, water, sessions, chronic
  /// readings — each with a short comment. This is the layer that makes
  /// "I did everything in the app" actually show up immediately, rather
  /// than waiting on a multi-day correlation to become statistically
  /// meaningful.
  List<Widget> _todaysFullReadout() {
    final rows = <Widget>[];
    final now = DateTime.now();

    // Sleep — last night specifically, falling back to most recent entry.
    final lastSleep = _sleepEntries.isNotEmpty ? _sleepEntries.first : null;
    if (lastSleep != null) {
      final isLastNight = _dateKey(lastSleep.date) ==
          _dateKey(now.subtract(const Duration(days: 1)));
      final whenLabel = isLastNight
          ? 'Last night'
          : _relativeTime(lastSleep.date);
      final durationText = lastSleep.duration != null
          ? ', ${lastSleep.duration!.inHours}h ${lastSleep.duration!.inMinutes % 60}m'
          : '';
      rows.add(_insightRow(
        icon: Icons.nightlight_round,
        color: const Color(0xFF5D6D7E),
        text: '$whenLabel you logged ${lastSleep.quality}/5 sleep quality'
            '$durationText${lastSleep.isNap ? ' (marked as a nap)' : ''}. '
            '${lastSleep.quality >= 4 ? 'That\'s a genuinely good night — it tends to show up in next-day energy.' : lastSleep.quality <= 2 ? 'That\'s rough — go easy on yourself today and consider an earlier wind-down tonight.' : 'A middling night — not bad, but there\'s room to improve the wind-down routine.'}',
      ));
    }

    // Check-in — most recent.
    final lastCheckin = _bella.lastCheckin;
    if (lastCheckin != null) {
      final fresh = now.difference(lastCheckin.time).inHours <= 24;
      rows.add(_insightRow(
        icon: Icons.mood,
        color: SageColors.amber,
        text: '${fresh ? 'Today' : _relativeTime(lastCheckin.time)} you '
            'checked in: mood ${lastCheckin.mood}/5, energy ${lastCheckin.energy}/5, '
            'stress ${lastCheckin.stress}/5'
            '${lastCheckin.note != null && lastCheckin.note!.trim().isNotEmpty ? ' — you noted "${lastCheckin.note}"' : ''}. '
            '${lastCheckin.isLow ? 'That blends to a low wellbeing score — worth being gentle with yourself.' : 'That blends to a wellbeing score of ${lastCheckin.wellbeingScore.toStringAsFixed(1)}/10.'}',
      ));
    }

    // Food — today's entries.
    final foodToday = _foodEntries
        .where((f) => _dateKey(f.time) == _dateKey(now))
        .toList();
    if (foodToday.isNotEmpty) {
      final withCal = foodToday.where((f) => f.calories != null).toList();
      final calTotal = withCal.fold<int>(0, (s, f) => s + (f.calories ?? 0));
      final tags = foodToday.map((f) => f.tag).whereType<String>().toSet();
      rows.add(_insightRow(
        icon: Icons.restaurant_outlined,
        color: SageColors.clay,
        text: 'Today you logged ${foodToday.length} food entr${foodToday.length == 1 ? 'y' : 'ies'}'
            '${withCal.isNotEmpty ? ' totaling ~$calTotal kcal' : ''}'
            '${tags.contains('high-sodium') ? ' — including something tagged high-sodium' : ''}'
            '${tags.contains('high-carb') ? ' — including something tagged high-carb' : ''}.',
      ));
    }

    // Water — today vs target.
    final waterTarget = _bella.getTarget<int>('waterMl') ?? 2000;
    final todayWater = _bella.todayWaterMl();
    if (todayWater > 0) {
      final pct = (todayWater / waterTarget * 100).round();
      rows.add(_insightRow(
        icon: Icons.water_drop_outlined,
        color: const Color(0xFF2E86C1),
        text: 'Today you\'ve had ${todayWater}ml of water — $pct% of your '
            '${waterTarget}ml target. '
            '${pct >= 100 ? 'Target met.' : pct >= 60 ? 'On pace, but not there yet.' : 'Well behind — worth catching up.'}',
      ));
    }

    // Sessions — today's, each one named.
    final sessionsToday =
        _allSessions.where((s) => _dateKey(s.date) == _dateKey(now)).toList();
    if (sessionsToday.isNotEmpty) {
      final byType = <String, int>{};
      for (final s in sessionsToday) {
        byType[s.type] = (byType[s.type] ?? 0) + s.durationMinutes;
      }
      final parts = byType.entries
          .map((e) => '${e.value} min ${e.key == 'sleep_sounds' ? 'sleep sounds' : e.key}')
          .join(', ');
      rows.add(_insightRow(
        icon: Icons.bolt_rounded,
        color: SageColors.moss,
        text: 'Today\'s activity: $parts '
            '(${sessionsToday.length} session${sessionsToday.length == 1 ? '' : 's'} total). '
            'That\'s logged and counted toward your streak and achievements.',
      ));
    }

    // Chronic readings — anything logged today, for any tracked condition.
    final user = UserService().currentUserObject;
    if (user != null && user.chronicDiseases.isNotEmpty) {
      for (final cond in user.chronicDiseases) {
        final readings = _bella.getReadings(condition: cond);
        if (readings.isEmpty) continue;
        final latest = readings.first;
        final isToday = _dateKey(latest.time) == _dateKey(now);
        if (!isToday) continue;
        final flagged = _isReadingFlagged(cond, latest);
        rows.add(_insightRow(
          icon: flagged ? Icons.warning_amber_rounded : Icons.check_circle_outline,
          color: flagged ? SageColors.clay : SageColors.moss,
          text: 'Today you logged a $cond reading: ${latest.type} '
              '${latest.value.toStringAsFixed(0)}'
              '${latest.secondaryValue != null ? '/${latest.secondaryValue!.toStringAsFixed(0)}' : ''} '
              '${latest.unit}. '
              '${flagged ? 'That\'s outside the typical range for this condition.' : 'That\'s within the typical range.'}',
        ));
      }
    }

    return rows;
  }

  Widget _insightRow({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5, color: SageColors.ink, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildPatterns() {
    if (_allSessions.isEmpty) return const SizedBox.shrink();

    final dayCount = <String, int>{};
    for (final s in _allSessions) {
      final day =
          ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][s.date.weekday - 1];
      dayCount[day] = (dayCount[day] ?? 0) + 1;
    }

    final maxCount = dayCount.values.isEmpty ? 1 : dayCount.values.reduce(max);

    return _card(
      accent: SageColors.moss,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
              'Day-of-week pattern', Icons.bar_chart_rounded, SageColors.moss),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children:
                ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((day) {
              final count = dayCount[day] ?? 0;
              final heightFactor = maxCount > 0 ? count / maxCount : 0.0;
              return Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: SageMotion.numberCountUp,
                        curve: Curves.easeOut,
                        width: 22,
                        height: max(4, 56 * heightFactor),
                        decoration: BoxDecoration(
                          color: count > 0 ? SageColors.moss : SageColors.line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(day,
                      style: TextStyle(fontSize: 10, color: SageColors.inkSoft)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Recommendations built directly from how the user says they're feeling
  /// right now — today's check-in (mood/stress/energy/note) and last
  /// night's sleep — rather than generic "you haven't meditated enough"
  /// thresholds. Returns specific, numbers-cited advice, or an empty list
  /// if there's genuinely no recent check-in/sleep to read.
  List<_Rec> _stateBasedRecs() {
    final out = <_Rec>[];
    final checkin = _bella.lastCheckin;
    final checkinFresh =
        checkin != null && DateTime.now().difference(checkin.time).inHours <= 24;
    final sleep = _bella.lastNightSleep;
    final sleepFresh = sleep != null &&
        DateTime.now().difference(sleep.date).inDays <= 1;

    if (checkinFresh) {
      final c = checkin!;
      if (c.stress >= 4 && c.energy <= 2) {
        out.add(_Rec(
          icon: Icons.air,
          title: 'High stress, low energy — that combo first',
          body: 'You logged stress ${c.stress}/5 and energy ${c.energy}/5 '
              'today. That pairing usually responds better to a calming '
              'breathwork session than to pushing through with more activity '
              '— try Box Breathing for 5 minutes before anything else.',
          color: SageColors.clay,
        ));
      } else if (c.stress >= 4) {
        out.add(_Rec(
          icon: Icons.air,
          title: 'Stress is running high today',
          body: 'Stress ${c.stress}/5 in today\'s check-in. A short breathwork '
              'or meditation session right now is more likely to help than '
              'waiting for it to pass on its own.',
          color: SageColors.amber,
        ));
      } else if (c.energy <= 2 && c.mood <= 2) {
        out.add(_Rec(
          icon: Icons.battery_alert_outlined,
          title: 'Low energy and low mood today',
          body: 'You logged mood ${c.mood}/5 and energy ${c.energy}/5. Worth '
              'checking the basics first — water, food, and sleep — before '
              'anything more involved. Be gentle with yourself today.',
          color: SageColors.clay,
        ));
      } else if (c.mood >= 4 && c.energy >= 4 && c.stress <= 2) {
        out.add(_Rec(
          icon: Icons.wb_sunny_outlined,
          title: 'You\'re in a good place today',
          body: 'Mood ${c.mood}/5, energy ${c.energy}/5, stress ${c.stress}/5 — '
              'this is a good day to take on something slightly harder than '
              'usual, like a longer walk or a new technique.',
          color: SageColors.moss,
        ));
      }

      if (c.note != null && c.note!.trim().isNotEmpty) {
        out.add(_Rec(
          icon: Icons.edit_note_rounded,
          title: 'From your check-in note',
          body: 'You wrote: "${c.note!.trim()}". Keep that in mind as context '
              'for the rest of today\'s suggestions.',
          color: SageColors.amber,
        ));
      }
    } else {
      out.add(_Rec(
        icon: Icons.mood,
        title: "Haven't checked in today",
        body: 'Without today\'s check-in, recommendations below fall back to '
            'your longer-term averages instead of how you actually feel '
            'right now. A 30-second check-in fixes that.',
        color: SageColors.amber,
      ));
    }

    if (sleepFresh && sleep!.quality <= 2) {
      out.add(_Rec(
        icon: Icons.nightlight_round,
        title: 'Running on a bad night\'s sleep',
        body: 'You logged ${sleep.quality}/5 quality last night. Expect lower '
            'capacity today — this is a reasonable day to scale back '
            'intensity rather than push for a personal best.',
        color: const Color(0xFF5D6D7E),
      ));
    }

    return out;
  }

  Widget _buildRecommendations() {
    final recs = <_Rec>[];
    final medMin = _minutesOf(_byType('meditation'));
    final medSessions = _byType('meditation');
    final breathSessions = _byType('breathwork');
    final walkSessions = _byType('walking');
    final avgHr = _avgHeartRate;
    final user = UserService().currentUserObject;

    // ── Layer 0: built directly from how you say you're feeling right now
    // (today's check-in + last night's sleep), not generic thresholds.
    // These always go first, since "how am I doing today" should outrank
    // "here's a tip about your 14-day average".
    final stateRecs = _stateBasedRecs();
    recs.addAll(stateRecs);

    // ── Single-metric basics ────────────────────────────────────────────
    if (_bmiCategory == 'Overweight' || _bmiCategory == 'Obese') {
      recs.add(_Rec(
        icon: Icons.directions_walk,
        title: 'Daily walk',
        body: 'Even a 20-minute walk builds a sustainable momentum.',
        color: SageColors.clay,
      ));
    }

    if (medMin < 30) {
      recs.add(_Rec(
        icon: Icons.self_improvement,
        title: 'Start meditating',
        body: 'Try a 5-minute session — consistency beats duration at first.',
        color: const Color(0xFF9B59B6),
      ));
    } else if (medSessions.length >= 5 && medMin / medSessions.length < 10) {
      recs.add(_Rec(
        icon: Icons.self_improvement,
        title: 'Go a bit longer',
        body: 'Your average session is under 10 min — try extending to 15.',
        color: const Color(0xFF9B59B6),
      ));
    }

    if (breathSessions.isEmpty) {
      recs.add(_Rec(
        icon: Icons.air,
        title: 'Try Box Breathing',
        body: 'Even one 5-minute breathwork session can lower resting HR.',
        color: SageColors.amber,
      ));
    }

    if (!_bella.hasCheckedInToday()) {
      recs.add(_Rec(
        icon: Icons.mood,
        title: "Haven't checked in today",
        body: 'A 30-second daily check-in keeps your wellness score accurate.',
        color: SageColors.amber,
      ));
    }

    // ── Cross-metric: HR elevated + low calming activity ────────────────
    if (avgHr != null &&
        avgHr > 85 &&
        medSessions.length + breathSessions.length < 3) {
      recs.add(_Rec(
        icon: Icons.monitor_heart_outlined,
        title: 'Your HR is elevated',
        body: 'Avg $avgHr bpm over the last 14 days. A short breathwork '
            'session may help — it\'s the activity most directly linked to '
            'lowering resting HR.',
        color: SageColors.clay,
      ));
    }

    // ── Cross-metric: sleep trend, severity-aware ───────────────────────
    final avgSleep = _bella.averageSleepQuality();
    final sleepThis = _avgSleepInWindow(daysAgoStart: 6, daysAgoEnd: 0);
    final sleepLast = _avgSleepInWindow(daysAgoStart: 13, daysAgoEnd: 7);
    if (avgSleep != null && avgSleep < 3) {
      recs.add(_Rec(
        icon: Icons.nightlight_round,
        title: 'Poor sleep trend',
        body: 'Try sleep sounds or the 4-7-8 breathing technique before bed.',
        color: const Color(0xFF5D6D7E),
      ));
    } else if (sleepThis != null &&
        sleepLast != null &&
        sleepThis < sleepLast - 0.5) {
      recs.add(_Rec(
        icon: Icons.trending_down_rounded,
        title: 'Sleep is slipping',
        body: 'Down from ${sleepLast.toStringAsFixed(1)} to '
            '${sleepThis.toStringAsFixed(1)}/5 this week — worth an earlier '
            'wind-down tonight.',
        color: const Color(0xFF5D6D7E),
      ));
    }

    // ── Cross-metric: the sleep→activity link, made actionable ──────────
    final link = _sleepActivityLink;
    if (link != null &&
        link.goodNightActivityPct != null &&
        link.poorNightActivityPct != null &&
        (link.goodNightActivityPct! - link.poorNightActivityPct!) > 0.25) {
      recs.add(_Rec(
        icon: Icons.bedtime_outlined,
        title: 'Sleep is your unlock',
        body: 'You\'re consistently more active the day after good sleep. '
            'Protecting tonight\'s sleep may matter more than tomorrow\'s '
            'willpower.',
        color: const Color(0xFF5D6D7E),
      ));
    }

    // ── Cross-metric: hydration + logged low energy ─────────────────────
    final waterTarget = _bella.getTarget<int>('waterMl') ?? 2000;
    final lastCheckin = _bella.lastCheckin;
    final checkinFresh = lastCheckin != null &&
        DateTime.now().difference(lastCheckin.time).inHours <= 18;
    if (checkinFresh &&
        lastCheckin!.energy <= 2 &&
        _bella.todayWaterMl() < waterTarget * 0.6) {
      recs.add(_Rec(
        icon: Icons.water_drop_outlined,
        title: 'Low energy + under-hydrated',
        body: 'You logged low energy and you\'re well under today\'s water '
            'target — dehydration is a common, easy-to-fix energy drain.',
        color: SageColors.clay,
      ));
    }

    // ── Chronic condition + inactivity combo ─────────────────────────────
    if (user != null && user.chronicDiseases.isNotEmpty) {
      for (final cond in user.chronicDiseases) {
        final readings = _bella.getReadings(condition: cond);
        if (readings.isEmpty) continue;
        final flagged = _isReadingFlagged(cond, readings.first);
        final lowActivity = walkSessions.length + breathSessions.length < 2;
        if (flagged && lowActivity) {
          recs.add(_Rec(
            icon: Icons.warning_amber_rounded,
            title: '$cond reading was out of range',
            body: 'Your latest $cond reading was flagged and activity has '
                'been light this week — check the Chronic Care symptom '
                'guide, and mention the trend at your next visit if it continues.',
            color: SageColors.clay,
          ));
          break; // one is enough — avoid piling on
        }
      }
    }

    // ── Streak encouragement ─────────────────────────────────────────────
    if (_currentStreak >= 3) {
      recs.add(_Rec(
        icon: Icons.local_fire_department,
        title: '$_currentStreak-day streak!',
        body: 'Keep it going — one more day and you\'re halfway to a week.',
        color: SageColors.clay,
      ));
    } else if (_currentStreak == 0 && _longestStreak >= 3) {
      recs.add(_Rec(
        icon: Icons.refresh_rounded,
        title: 'Restart your streak',
        body: 'You\'ve hit $_longestStreak days before — one session today '
            'gets a new streak going.',
        color: SageColors.moss,
      ));
    }

    if (recs.isEmpty) {
      recs.add(_Rec(
        icon: Icons.check_circle_outline,
        title: "You're on track",
        body: 'Keep doing what you\'re doing — your routine looks solid.',
        color: SageColors.moss,
      ));
    }

    // Cross-metric recs carry the most signal — surface those first.
    return _card(
      accent: SageColors.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
              'Recommendations', Icons.lightbulb_outline, SageColors.amber),
          const SizedBox(height: 12),
          ...recs.take(8).map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: r.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(r.icon, size: 16, color: r.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(r.body,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: SageColors.inkSoft,
                                  height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── ACHIEVEMENTS TAB ──────────────────────────────────────────────────────

  Widget _buildAchievementsTab() {
    final unlocked = _achievements.where((a) => a.isUnlocked).toList();
    final locked = _achievements.where((a) => !a.isUnlocked).toList();

    return Reveal(
      size: RevealSize.large,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SageColors.card,
            border: Border.all(color: SageColors.line),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: SageColors.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.emoji_events,
                    color: SageColors.amber, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${unlocked.length} / ${_achievements.length} unlocked',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: SageColors.ink),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _achievements.isEmpty
                            ? 0
                            : unlocked.length / _achievements.length,
                        minHeight: 6,
                        backgroundColor: SageColors.line,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(SageColors.amber),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_achievements.isEmpty ? 0 : (unlocked.length / _achievements.length * 100).round()}% complete',
                      style:
                          TextStyle(fontSize: 11, color: SageColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (unlocked.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('UNLOCKED',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: SageColors.inkSoft)),
          const SizedBox(height: 12),
          _achievementsGrid(unlocked, dimmed: false),
        ],
        if (locked.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('IN PROGRESS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: SageColors.inkSoft)),
          const SizedBox(height: 12),
          _achievementsGrid(locked, dimmed: true),
        ],
      ],
      ), // Column
    ); // Reveal
  }

  Widget _achievementsGrid(List<Achievement> list, {required bool dimmed}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.05,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => StaggerItem(
        index: i,
        child: _achievementTile(list[i], dimmed: dimmed),
      ),
    );
  }

  /// Phrases how long ago an achievement unlocked, in the same voice as
  /// the rest of the screen. Distinct from `_relativeTime` because "just
  /// now" / "today" reads better here than "0h ago" for a fresh unlock.
  String _unlockedRelativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 2) return 'just now';
    if (diff.inHours < 24) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 14) return '${diff.inDays}d ago';
    if (diff.inDays < 60) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  Widget _achievementTile(Achievement a, {required bool dimmed}) {
    final opacity = dimmed ? 0.55 : 1.0;
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SageColors.card,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(
            color: a.isUnlocked
                ? a.color.withValues(alpha: 0.35)
                : SageColors.line,
            width: a.isUnlocked ? 1.5 : 1,
          ),
          boxShadow: a.isUnlocked
              ? [
                  BoxShadow(
                    color: a.color.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: a.color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(a.icon, size: 16, color: a.color),
                ),
                const Spacer(),
                if (a.isUnlocked)
                  Icon(Icons.check_circle_rounded, size: 16, color: a.color),
              ],
            ),
            const Spacer(),
            Text(
              a.title,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: SageColors.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              a.description,
              style: TextStyle(
                  fontSize: 10.5, color: SageColors.inkSoft, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: a.progress / 100,
                minHeight: 4,
                backgroundColor: SageColors.line,
                valueColor: AlwaysStoppedAnimation<Color>(a.color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              a.isUnlocked && a.unlockedAt != null
                  ? 'Unlocked ${_unlockedRelativeTime(a.unlockedAt!)}'
                  : '${a.progress.round()}%',
              style: TextStyle(
                  fontSize: 10,
                  color: a.isUnlocked ? a.color : SageColors.inkSoft,
                  fontWeight: a.isUnlocked ? FontWeight.w600 : FontWeight.w400),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────
  //
  // `_card` uses the same asymmetric sharp-top-left-corner language as
  // WellnessGridCard/MetricTile elsewhere in the app (with an optional
  // colored top accent border), so Insights now visually matches the rest
  // of Sage instead of using a one-off plain rounded-rectangle style.

  Widget _card({required Widget child, Color? accent}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SageColors.card,
        border: Border.all(color: SageColors.line),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: accent == null
          ? child
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -16,
                  left: -16,
                  child: Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
                child,
              ],
            ),
    );
  }

  Widget _sectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SageColors.ink)),
        ),
      ],
    );
  }

  Widget _emptyState(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return Column(
      children: [
        Icon(icon, size: 32, color: SageColors.line),
        const SizedBox(height: 8),
        Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: SageColors.inkSoft)),
        const SizedBox(height: 4),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: SageColors.inkSoft)),
      ],
    );
  }

  Widget _statTile(
      {required String label,
      required String value,
      required String unit,
      required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SageColors.linen,
        border: Border.all(color: SageColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: SageColors.inkSoft)),
          const SizedBox(height: 4),
          Text(value,
              style: SageText.mono(
                  size: 20, weight: FontWeight.w600, color: color)),
          Text(unit,
              style: TextStyle(fontSize: 11, color: SageColors.inkSoft),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _statsGrid(List<_StatItem> items) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: items
          .map((item) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: SageColors.linen,
                  border: Border.all(color: SageColors.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(item.label,
                        style:
                            TextStyle(fontSize: 10, color: SageColors.inkSoft)),
                    const SizedBox(height: 2),
                    Text(item.value,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: item.color),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

// ── Supporting types ──────────────────────────────────────────────────────────

enum _TotalsPeriod { today, yesterday, last14 }

class _SleepActivityLink {
  final double? goodNightActivityPct;
  final double? poorNightActivityPct;
  final double? okNightActivityPct;
  final int goodNights;
  final int poorNights;
  final int okNights;
  const _SleepActivityLink({
    required this.goodNightActivityPct,
    required this.poorNightActivityPct,
    required this.okNightActivityPct,
    required this.goodNights,
    required this.poorNights,
    required this.okNights,
  });
}

class _StatItem {
  final String label;
  final String value;
  final Color color;
  const _StatItem(this.label, this.value, this.color);
}

class _Rec {
  final IconData icon;
  final String title;
  final String body;
  final Color color;
  const _Rec(
      {required this.icon,
      required this.title,
      required this.body,
      required this.color});
}

// ── Donut chart ───────────────────────────────────────────────────────────────

class _DonutSegment {
  final double value;
  final Color color;
  const _DonutSegment(this.value, this.color);
}

class _DonutChart extends StatelessWidget {
  final List<_DonutSegment> segments;
  final String center;
  final String centerLabel;

  const _DonutChart({
    required this.segments,
    required this.center,
    required this.centerLabel,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DonutPainter(segments),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: SageColors.ink)),
            Text(centerLabel,
                style: TextStyle(fontSize: 10, color: SageColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  _DonutPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (s, e) => s + e.value);

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    const strokeWidth = 10.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (total == 0) {
      paint.color = const Color(0xFFE9E6DA);
      canvas.drawArc(rect.deflate(strokeWidth / 2), 0, 2 * pi, false, paint);
      return;
    }

    double startAngle = -pi / 2;
    for (final seg in segments) {
      if (seg.value == 0) continue;
      final sweep = (seg.value / total) * 2 * pi;
      paint.color = seg.color;
      canvas.drawArc(
        rect.deflate(strokeWidth / 2),
        startAngle,
        sweep - 0.06,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.segments != segments;
}

// ── Sparkline ──────────────────────────────────────────────────────────────────

/// Minimal trend line for a chronic-condition reading history — just
/// enough to show direction and volatility at a glance, no axes or labels
/// (the accompanying text comment carries the actual numbers).
class _Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;

  const _Sparkline({required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SparklinePainter(values, color));
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(min);
    final maxV = values.reduce(max);
    final range = (maxV - minV).abs() < 0.0001 ? 1.0 : (maxV - minV);

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = size.width * (i / (values.length - 1));
      final norm = (values[i] - minV) / range;
      // Invert: higher value draws higher on the sparkline (lower y).
      final y = size.height - (norm * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // Dot on the most recent point so "where it ended up" is unambiguous.
    final lastX = size.width;
    final lastNorm = (values.last - minV) / range;
    final lastY = size.height - (lastNorm * size.height);
    canvas.drawCircle(Offset(lastX, lastY), 2.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
}