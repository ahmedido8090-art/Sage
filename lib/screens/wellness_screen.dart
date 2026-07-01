// screens/wellness_screen.dart
//
// Every animated element on this screen (StaggerColumn entrance,
// _ProgressMiniCard, _PracticeCard, streak chips, the score ring, the
// progress arcs) is built on the shared motion system in widgets/reveal.dart,
// widgets/pressable.dart, widgets/stagger.dart, and theme/motion.dart —
// the same primitives every other screen uses. There is no screen-local
// animation code left here apart from the two CustomPainter-driven rings
// (_AnimatedArc, _AnimatedScoreRing), which animate a numeric fill rather
// than an entrance and so don't fit the Reveal/Pressable/Stagger model.

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/bella_data.dart';
import '../services/bluetooth_service.dart';
import '../services/user_service.dart';
import '../services/wellness_quote_service.dart';
import '../services/bella_service.dart';
import '../services/wellness_score_service.dart';
import '../models/health_data.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/quote_section.dart';
import '../widgets/animated_pillar_row.dart';
import '../widgets/reveal.dart';
import '../widgets/pressable.dart';
import '../widgets/stagger.dart';
import '../utils/page_transitions.dart';
import 'breathwork_screen.dart';
import 'meditation_screen.dart';
import 'walking_screen.dart';
import 'sleep_sounds_screen.dart';

class WellnessScreen extends StatefulWidget {
  final ValueNotifier<int> reloadSignal;
  const WellnessScreen({super.key, required this.reloadSignal});

  @override
  State<WellnessScreen> createState() => _WellnessScreenState();
}

/// App-wide RouteObserver so WellnessScreen can detect when a pushed route
/// pops back to it and refresh its Bella data immediately.
final RouteObserver<ModalRoute<void>> wellnessRouteObserver =
    RouteObserver<ModalRoute<void>>();

class _WellnessScreenState extends State<WellnessScreen> with RouteAware {
  final BluetoothService _bt = BluetoothService.instance;
  final BellaService _bella = BellaService();
  int _heartRate = 72;
  int _steps = 0;
  double _bmi = 22.5;
  late Quote _currentQuote;

  // ── Bella data ────────────────────────────────────────────────────────────
  CheckinEntry? _lastCheckin;
  double? _avgSleepQuality;
  int _todayCalories = 0;
  int _todayFoodCount = 0;
  int _todayWaterMl = 0;
  bool _hasChronicConditions = false;
  bool _chronicReadingsInRange = true;
  List<String> _flaggedConditions = [];

  // ── Activity progress (today) ─────────────────────────────────────────────
  int _meditationMinutesToday = 0;
  int _meditationTarget = 10;
  int _breathworkSessionsToday = 0;
  int _breathworkTarget = 1;
  int _walkingMinutesToday = 0;
  int _walkingTarget = 30;
  int _sleepSoundsMinutesToday = 0;

  // ── Streaks (consecutive days with ≥1 session) ────────────────────────────
  int _meditationStreak = 0;
  int _breathworkStreak = 0;
  int _walkingStreak = 0;
  // Combined streak: days where ≥2 of the 3 activity types had a session.
  int _multiActivityStreak = 0;

  // ── Holistic score pillars (0–100 each) ───────────────────────────────────
  int _sleepScore = 0;
  int _nutritionScore = 0;
  int _checkinScore = 0;
  int _activityScore = 0;
  int _chronicScore = 0;
  int _overallScore = 0;

  int get _totalActivityMinutesToday =>
      _meditationMinutesToday + _walkingMinutesToday +
      _breathworkSessionsToday * 5 + // approx 5 min per breathwork session
      _sleepSoundsMinutesToday;

  @override
  void initState() {
    super.initState();
    // Quote is initially random; _loadBellaData() will refine it once
    // Bella data is available.
    _currentQuote = WellnessQuoteService.getQuoteForState(
      lastCheckin: _bella.lastCheckin,
      lastSleep: _bella.lastNightSleep,
      avgSleepQuality: _bella.averageSleepQuality(),
      totalActivityMinutesToday: _bella.sessionMinutesToday('meditation') +
          _bella.sessionMinutesToday('walking') +
          _bella.sessionsToday('breathwork') * 5 +
          _bella.sessionMinutesToday('sleep_sounds'),
    );

    _bt.dataStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _heartRate = data.heartRate;
        _steps = data.steps;
      });
    });

    _calculateBMI();
    _loadBellaData();

    // Reload whenever DashboardScreen signals a tab-switch back to Wellness.
    // RouteAware's didPopNext only fires for pushed routes; it misses bottom-nav
    // tab switches because WellnessScreen is never actually popped — it stays
    // in the widget tree. This notifier bridges that gap.
    widget.reloadSignal.addListener(_onReloadSignal);
  }

  void _onReloadSignal() {
    if (!mounted) return;
    setState(() {
      _loadBellaData();
      _currentQuote = WellnessQuoteService.getQuoteForState(
        lastCheckin: _bella.lastCheckin,
        lastSleep: _bella.lastNightSleep,
        avgSleepQuality: _bella.averageSleepQuality(),
        totalActivityMinutesToday: _totalActivityMinutesToday,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe once the route is available in context
    final route = ModalRoute.of(context);
    if (route != null) {
      wellnessRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    wellnessRouteObserver.unsubscribe(this);
    widget.reloadSignal.removeListener(_onReloadSignal);
    super.dispose();
  }

  /// Called when a pushed route (ChronicCare, PurePlate, etc.) pops
  /// back to this screen — reload Bella data so scores are fresh.
  @override
  void didPopNext() {
    if (!mounted) return;
    setState(() {
      _loadBellaData();
      _currentQuote = WellnessQuoteService.getQuoteForState(
        lastCheckin: _bella.lastCheckin,
        lastSleep: _bella.lastNightSleep,
        avgSleepQuality: _bella.averageSleepQuality(),
        totalActivityMinutesToday: _totalActivityMinutesToday,
      );
    });
  }

  void _loadBellaData() {
    _lastCheckin = _bella.lastCheckin;
    _avgSleepQuality = _bella.averageSleepQuality();

    final foodToday = _bella.getFoodEntries(onDate: DateTime.now());
    _todayFoodCount = foodToday.length;
    _todayCalories = foodToday.fold(0, (s, f) => s + (f.calories ?? 0));
    _todayWaterMl = _bella.todayWaterMl();

    final user = UserService().currentUserObject;
    _hasChronicConditions = user != null && user.chronicDiseases.isNotEmpty;
    // _chronicReadingsInRange / _flaggedConditions are set by _computeScores()
    // below, via WellnessScoreService — the single source of truth shared
    // with InsightsScreen. Don't recompute it separately here.

    // Activity progress
    _meditationMinutesToday = _bella.sessionMinutesToday('meditation');
    _meditationTarget = _bella.getTarget<int>('meditationMinutes') ?? 10;
    _breathworkSessionsToday = _bella.sessionsToday('breathwork');
    _breathworkTarget = _bella.getTarget<int>('breathworkSessions') ?? 1;
    _walkingMinutesToday = _bella.sessionMinutesToday('walking');
    _walkingTarget = _bella.getTarget<int>('walkMinutes') ?? 30;
    _sleepSoundsMinutesToday = _bella.sessionMinutesToday('sleep_sounds');

    // Streaks
    _meditationStreak = _calculateStreak('meditation');
    _breathworkStreak = _calculateStreak('breathwork');
    _walkingStreak = _calculateStreak('walking');
    _multiActivityStreak = _calculateMultiActivityStreak();

    _computeScores();
  }

  /// Consecutive days where at least 2 of the 4 activity types
  /// (meditation, breathwork, walking, sleep_sounds) had at least one session.
  /// This is the most motivating streak because it shows a holistic practice.
  int _calculateMultiActivityStreak() {
    final medDates = _bella
        .getSessions(type: 'meditation')
        .map((s) => _dateKey(s.date))
        .toSet();
    final bwDates = _bella
        .getSessions(type: 'breathwork')
        .map((s) => _dateKey(s.date))
        .toSet();
    final walkDates = _bella
        .getSessions(type: 'walking')
        .map((s) => _dateKey(s.date))
        .toSet();
    final relaxDates = _bella
        .getSessions(type: 'sleep_sounds')
        .map((s) => _dateKey(s.date))
        .toSet();

    int streak = 0;
    DateTime cursor = DateTime.now();
    for (int i = 0; i < 365; i++) {
      final key = _dateKey(cursor);
      final count = (medDates.contains(key) ? 1 : 0) +
          (bwDates.contains(key) ? 1 : 0) +
          (walkDates.contains(key) ? 1 : 0) +
          (relaxDates.contains(key) ? 1 : 0);
      if (count >= 2) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  // ── Streak helper ────────────────────────────────────────────────────────
  int _calculateStreak(String type) {
    final dates =
        _bella.getSessions(type: type).map((s) => _dateKey(s.date)).toSet();
    if (dates.isEmpty) return 0;
    int streak = 0;
    DateTime cursor = DateTime.now();
    for (int i = 0; i < 365; i++) {
      if (dates.contains(_dateKey(cursor))) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Last session label ────────────────────────────────────────────────────
  String _lastSessionLabel(String type) {
    final sessions = _bella.getSessions(type: type);
    if (sessions.isEmpty) return 'Not started yet';
    final last = sessions.first;
    final diff = DateTime.now().difference(last.date);
    if (diff.inMinutes < 60) return 'Last: ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last: ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Last: yesterday';
    return 'Last: ${diff.inDays}d ago';
  }

  bool _completedTodayFor(String type) {
    switch (type) {
      case 'meditation':
        return _meditationMinutesToday >= _meditationTarget;
      case 'breathwork':
        return _breathworkSessionsToday >= _breathworkTarget;
      case 'walking':
        return _walkingMinutesToday >= _walkingTarget;
      case 'sleep_sounds':
        return _sleepSoundsMinutesToday > 0;
      default:
        return false;
    }
  }

  // ── Score computation ────────────────────────────────────────────────────
  //
  // Delegates to WellnessScoreService — the single formula shared with
  // InsightsScreen — so the two screens can never show two different
  // numbers/labels for the same underlying data again.
  void _computeScores() {
    final user = UserService().currentUserObject;
    final result = WellnessScoreService.compute(
      bella: _bella,
      chronicConditions: user?.chronicDiseases ?? const [],
    );
    _sleepScore = result.sleepScore;
    _nutritionScore = result.nutritionScore;
    _checkinScore = result.checkinScore;
    _activityScore = result.activityScore;
    _chronicScore = result.chronicScore;
    _overallScore = result.overallScore;
    _flaggedConditions = result.flaggedConditions;
    _chronicReadingsInRange = result.flaggedConditions.isEmpty;
  }

  void _calculateBMI() {
    final user = UserService().currentUserObject;
    if (user != null && user.height > 0 && user.weight > 0) {
      final h = user.height / 100;
      setState(() => _bmi = user.weight / (h * h));
    }
  }

  String _getBMICategory() {
    if (_bmi < 18.5) return 'Underweight';
    if (_bmi < 25) return 'Normal';
    if (_bmi < 30) return 'Overweight';
    return 'Obese';
  }

  String _scoreLabel() => WellnessScoreService.label(_overallScore);

  Color _scoreColor() => WellnessScoreService.color(_overallScore);

  bool get _hasAnyData =>
      _lastCheckin != null || _avgSleepQuality != null || _todayFoodCount > 0;

  String _getHealthAdvice() {
    if (_hasChronicConditions && !_chronicReadingsInRange) {
      final label = _flaggedConditions.length == 1
          ? _flaggedConditions.first
          : _flaggedConditions.length == 2
              ? '${_flaggedConditions[0]} & ${_flaggedConditions[1]}'
              : '${_flaggedConditions.sublist(0, _flaggedConditions.length - 1).join(', ')} & ${_flaggedConditions.last}';
      return 'Your $label reading needs attention today — check in with Chronic Care.';
    }
    if (_checkinScore < 40 && _lastCheckin != null) {
      return _lastCheckin!.stress >= 4
          ? 'Stress is high — a short breathwork session can help reset your nervous system.'
          : 'Mood and energy have been low. A 10-min meditation or gentle walk can help.';
    }
    if (_activityScore < 40) {
      return 'No activity logged today. Even a short session counts — try breathwork or a walk.';
    }
    if (_sleepScore < 40) {
      return 'Sleep quality has been below average. Try sleep sounds to wind down tonight.';
    }
    if (_nutritionScore < 40) {
      // Check if it's specifically a hydration gap vs food logging gap.
      final hour = DateTime.now().hour;
      final underHydrated = (hour >= 10 && _todayWaterMl < 500) ||
          (hour >= 14 && _todayWaterMl < 1000) ||
          (hour >= 18 && _todayWaterMl < 1500);
      if (underHydrated && _todayFoodCount > 0) {
        final logged = _todayWaterMl > 0
            ? '${(_todayWaterMl / 1000).toStringAsFixed(1)}L logged'
            : 'none logged';
        return 'You\'re behind on water today ($logged). That\'s your easiest win right now.';
      }
      return 'No meals logged today. Tracking nutrition helps Sage give you better insights.';
    }
    if (_overallScore >= 80)
      return 'You\'re thriving — keep up the healthy habits!';
    if (_overallScore >= 60)
      return 'Good momentum. Focus on your lowest pillar to level up.';
    return 'Start by completing a check-in or a short session — small steps build the picture.';
  }

  // ── Navigation helpers ────────────────────────────────────────────────────
  /// One context-aware line for the wellness hub header.
  /// Reflects the current score state so the header isn't always generic.
  String _wellnessHubSubtitle() {
    if (_hasChronicConditions && !_chronicReadingsInRange) {
      final label = _flaggedConditions.length == 1
          ? _flaggedConditions.first
          : 'A reading';
      return '$label needs attention today.';
    }
    if (_lastCheckin != null && _lastCheckin!.stress >= 4) {
      return 'High stress detected — breathwork is ready for you.';
    }
    if (_avgSleepQuality != null && _avgSleepQuality! < 2.5) {
      return 'Sleep has been rough this week. Rest is the priority.';
    }
    if (_lastCheckin != null && _lastCheckin!.energy <= 2) {
      return 'Low energy today — gentle movement can shift this.';
    }
    // Celebrate a multi-activity streak prominently.
    if (_multiActivityStreak >= 3) {
      return '$_multiActivityStreak days of mixed practice in a row — that\'s real momentum.';
    }
    if (_multiActivityStreak >= 2) {
      return '$_multiActivityStreak days combining practices — keep the streak alive.';
    }
    if (_overallScore >= 80) return 'You\'re thriving. Keep the momentum.';
    if (_overallScore >= 60)
      return 'Good progress. Focus on your lowest pillar.';
    if (_overallScore > 0)
      return 'Start anywhere. Small steps build the picture.';
    return 'Breathe, move, and rest well.';
  }

  void _go(Widget screen) {
    Navigator.push(context, slideUpRoute(screen))
        .then((_) {
      if (!mounted) return;
      setState(() {
        _loadBellaData();
        _currentQuote = WellnessQuoteService.getQuoteForState(
          lastCheckin: _bella.lastCheckin,
          lastSleep: _bella.lastNightSleep,
          avgSleepQuality: _bella.averageSleepQuality(),
          totalActivityMinutesToday: _totalActivityMinutesToday,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SageColors.linen,
      body: SafeArea(
        child: RefreshIndicator(
          color: SageColors.moss,
          onRefresh: () async => setState(_loadBellaData),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            // StaggerColumn fades + rises each top-level section in with
            // a small delay between them — same primitive every other
            // screen's entrance is built on, using shared SageMotion
            // tokens for delay/duration instead of a local number.
            child: StaggerColumn(
              size: RevealSize.large,
              children: [
                // ── Header ──────────────────────────────────────────────
                _buildHeader(),
                const SizedBox(height: 20),

                // ── Chronic alert (only when out-of-range) ───────────────
                if (_hasChronicConditions && !_chronicReadingsInRange)
                  _buildAlert(
                    icon: Icons.monitor_heart_outlined,
                    message: _flaggedConditions.length == 1
                        ? 'Your ${_flaggedConditions.first} reading needs attention today — check in with Chronic Care.'
                        : _flaggedConditions.isEmpty
                            ? 'One or more chronic readings is outside the healthy range.'
                            : 'Your ${_flaggedConditions.join(' & ')} readings need attention today — check in with Chronic Care.',
                    color: SageColors.clay,
                  ),

                // ── Poor-sleep nudge ─────────────────────────────────────
                if (_avgSleepQuality != null &&
                    _avgSleepQuality! < 3.0 &&
                    !(_hasChronicConditions && !_chronicReadingsInRange))
                  _buildAlert(
                    icon: Icons.bedtime_outlined,
                    message: 'Sleep quality has been below average this week.',
                    color: SageColors.moss,
                    actionLabel: 'Sleep Sounds',
                    onAction: () => _go(const SleepSoundsScreen()),
                  ),

                // ── Health score card ─────────────────────────────────────
                _HealthStatusCard(
                  overallScore: _overallScore,
                  scoreLabel: _scoreLabel(),
                  scoreColor: _scoreColor(),
                  sleepScore: _sleepScore,
                  nutritionScore: _nutritionScore,
                  checkinScore: _checkinScore,
                  activityScore: _activityScore,
                  chronicScore: _chronicScore,
                  hasChronicConditions: _hasChronicConditions,
                  advice: _getHealthAdvice(),
                  hasData: _hasAnyData,
                ),

                const SizedBox(height: 24),

                // ── Today's progress row ──────────────────────────────────
                _buildSectionLabel('TODAY\'S PROGRESS'),
                const SizedBox(height: 12),
                _buildProgressRow(),

                const SizedBox(height: 24),

                // ── Streaks ────────────────────────────────────────────────
                if (_meditationStreak > 1 ||
                    _breathworkStreak > 1 ||
                    _walkingStreak > 1 ||
                    _multiActivityStreak > 1) ...[
                  _buildSectionLabel('STREAKS'),
                  const SizedBox(height: 10),
                  _buildStreakRow(),
                  const SizedBox(height: 24),
                ],

                // ── Practice cards ─────────────────────────────────────────
                _buildSectionLabel('PRACTICES'),
                const SizedBox(height: 12),
                _buildPracticeGrid(),

                const SizedBox(height: 28),

                // ── Quote ──────────────────────────────────────────────────
                QuoteSection(
                  text: _currentQuote.text,
                  author: _currentQuote.author,
                  onRefresh: () => setState(() =>
                      _currentQuote = WellnessQuoteService.getQuoteForState(
                        lastCheckin: _bella.lastCheckin,
                        lastSleep: _bella.lastNightSleep,
                        avgSleepQuality: _bella.averageSleepQuality(),
                        totalActivityMinutesToday: _totalActivityMinutesToday,
                      )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WELLNESS HUB',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: SageColors.inkSoft,
                ),
              ),
              const SizedBox(height: 4),
              Text('$greeting.', style: SageText.headline()),
              const SizedBox(height: 3),
              Text(
                _wellnessHubSubtitle(),
                style: TextStyle(color: SageColors.inkSoft, fontSize: 13.5),
              ),
            ],
          ),
        ),
        // Heart rate chip — cross-fades the bpm value when it changes so a
        // live reading doesn't just snap, matching SageHeroCard's chip.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: SageColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: SageColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite, color: SageColors.clay, size: 13),
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: SageMotion.valueChange,
                child: Text(
                  '$_heartRate',
                  key: ValueKey(_heartRate),
                  style: SageText.mono(
                      size: 13,
                      weight: FontWeight.w700,
                      color: SageColors.ink),
                ),
              ),
              Text(
                ' bpm',
                style: TextStyle(fontSize: 11, color: SageColors.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: SageColors.inkSoft,
      ),
    );
  }

  // ── Alert banner ─────────────────────────────────────────────────────────
  Widget _buildAlert({
    required IconData icon,
    required String message,
    required Color color,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: TextStyle(fontSize: 13, color: color, height: 1.4)),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: Text(actionLabel,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  // ── Today's progress row ──────────────────────────────────────────────────
  Widget _buildProgressRow() {
    return Row(
      children: [
        Expanded(
          child: _ProgressMiniCard(
            index: 0,
            icon: Icons.self_improvement,
            label: 'Meditate',
            value: _meditationMinutesToday,
            target: _meditationTarget,
            unit: 'min',
            color: SageColors.sage,
            done: _completedTodayFor('meditation'),
            onTap: () => _go(MeditationScreen(
              initialHeartRate: _heartRate,
              bmi: _bmi,
              bmiCategory: _getBMICategory(),
            )),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ProgressMiniCard(
            index: 1,
            icon: Icons.air,
            label: 'Breathwork',
            value: _breathworkSessionsToday,
            target: _breathworkTarget,
            unit: 'sessions',
            color: SageColors.clay,
            done: _completedTodayFor('breathwork'),
            onTap: () => _go(BreathworkScreen(initialHeartRate: _heartRate)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ProgressMiniCard(
            index: 2,
            icon: Icons.directions_walk,
            label: 'Walk',
            value: _walkingMinutesToday,
            target: _walkingTarget,
            unit: 'min',
            color: SageColors.amber,
            done: _completedTodayFor('walking'),
            onTap: () => _go(WalkingScreen(
              initialHeartRate: _heartRate,
              initialSteps: _steps,
            )),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ProgressMiniCard(
            index: 3,
            icon: Icons.nights_stay,
            label: 'Relax',
            value: _sleepSoundsMinutesToday,
            target: 10,
            unit: 'min',
            color: SageColors.moss,
            done: _completedTodayFor('sleep_sounds'),
            onTap: () => _go(const SleepSoundsScreen()),
          ),
        ),
      ],
    );
  }

  // ── Streaks row ────────────────────────────────────────────────────────────
  Widget _buildStreakRow() {
    final streaks = <Map<String, dynamic>>[];

    // Multi-activity streak goes first — it's the most meaningful signal.
    if (_multiActivityStreak > 1) {
      streaks.add({
        'label': 'Mixed Practice',
        'days': _multiActivityStreak,
        'color': SageColors.moss,
        'icon': Icons.star_outline_rounded,
        'emoji': '⭐',
      });
    }
    if (_meditationStreak > 1) {
      streaks.add({
        'label': 'Meditation',
        'days': _meditationStreak,
        'color': SageColors.sage,
        'icon': Icons.self_improvement,
        'emoji': '🔥',
      });
    }
    if (_breathworkStreak > 1) {
      streaks.add({
        'label': 'Breathwork',
        'days': _breathworkStreak,
        'color': SageColors.clay,
        'icon': Icons.air,
        'emoji': '🔥',
      });
    }
    if (_walkingStreak > 1) {
      streaks.add({
        'label': 'Walking',
        'days': _walkingStreak,
        'color': SageColors.amber,
        'icon': Icons.directions_walk,
        'emoji': '🔥',
      });
    }

    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: streaks.length,
        itemBuilder: (context, i) {
          final s = streaks[i];
          final color = s['color'] as Color;
          final days = s['days'] as int;
          // Each chip fades + slides in from the right with a tiny
          // per-item stagger — uses the shared StaggerItem primitive
          // with the small-size token, same as every other tile.
          return StaggerItem(
            index: i,
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s['emoji'] as String,
                      style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$days-day streak',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: color),
                      ),
                      Text(
                        s['label'] as String,
                        style:
                            TextStyle(fontSize: 11, color: SageColors.inkSoft),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Practice grid ──────────────────────────────────────────────────────────
  Widget _buildPracticeGrid() {
    // Context-aware subtitles derived from the most recent check-in.
    final c = _lastCheckin;
    final checkinFresh =
        c != null && DateTime.now().difference(c.time).inHours <= 24;
    final highStress = checkinFresh && c!.stress >= 4;
    final lowEnergy = checkinFresh && c!.energy <= 2;
    final lowMood = checkinFresh && c!.mood <= 2;
    final highSleep = _avgSleepQuality != null && _avgSleepQuality! < 2.5;

    String breathSubtitle = 'Guided breathing';
    if (highStress) breathSubtitle = 'Stress is high \u2014 start here';
    else if (lowEnergy) breathSubtitle = 'Low energy \u2014 reset with breath';

    String medSubtitle = 'Guided sessions';
    if (lowMood) medSubtitle = 'Mood is low \u2014 a session can help';
    else if (highStress) medSubtitle = 'Calm your mind';

    String walkSubtitle = 'Track your activity';
    if (lowEnergy && !highStress) walkSubtitle = 'Gentle movement boosts energy';
    else if (lowMood) walkSubtitle = 'Movement lifts mood';

    String relaxSubtitle = 'Relax and rest';
    if (highSleep) relaxSubtitle = 'Sleep has been rough \u2014 wind down';
    else if (highStress) relaxSubtitle = 'Decompress before bed';

    final cards = [
      _PracticeCardData(
        icon: Icons.air,
        title: 'Breathwork',
        subtitle: breathSubtitle,
        accent: SageColors.clay,
        lastSession: _lastSessionLabel('breathwork'),
        done: _completedTodayFor('breathwork'),
        onTap: () => _go(BreathworkScreen(initialHeartRate: _heartRate)),
      ),
      _PracticeCardData(
        icon: Icons.self_improvement,
        title: 'Meditation',
        subtitle: medSubtitle,
        accent: SageColors.sage,
        lastSession: _lastSessionLabel('meditation'),
        done: _completedTodayFor('meditation'),
        onTap: () => _go(MeditationScreen(
          initialHeartRate: _heartRate,
          bmi: _bmi,
          bmiCategory: _getBMICategory(),
        )),
      ),
      _PracticeCardData(
        icon: Icons.directions_walk,
        title: 'Walking',
        subtitle: walkSubtitle,
        accent: SageColors.amber,
        lastSession: _lastSessionLabel('walking'),
        done: _completedTodayFor('walking'),
        onTap: () => _go(WalkingScreen(
          initialHeartRate: _heartRate,
          initialSteps: _steps,
        )),
      ),
      _PracticeCardData(
        icon: Icons.nights_stay,
        title: 'Relaxation',
        subtitle: relaxSubtitle,
        accent: SageColors.moss,
        lastSession: _lastSessionLabel('sleep_sounds'),
        done: _completedTodayFor('sleep_sounds'),
        onTap: () => _go(const SleepSoundsScreen()),
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: [
        for (int i = 0; i < cards.length; i++)
          _PracticeCard(data: cards[i], index: i),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Today's Progress Mini Card
// ────────────────────────────────────────────────────────────────────────────
//
// Built on the shared StaggerItem (entrance) + Pressable (tap feedback)
// primitives instead of hand-rolled AnimationControllers — same motion
// vocabulary as every other tile in the app now.
class _ProgressMiniCard extends StatelessWidget {
  const _ProgressMiniCard({
    required this.index,
    required this.icon,
    required this.label,
    required this.value,
    required this.target,
    required this.unit,
    required this.color,
    required this.done,
    required this.onTap,
  });

  final int index;
  final IconData icon;
  final String label;
  final int value;
  final int target;
  final String unit;
  final Color color;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = (value / target).clamp(0.0, 1.0);

    return StaggerItem(
      index: index,
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: done ? color.withValues(alpha: 0.10) : SageColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: done ? color.withValues(alpha: 0.40) : SageColors.line,
              width: done ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated arc progress — fills from 0 to pct instead of
              // snapping straight to its final value.
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _AnimatedArc(
                      progress: pct,
                      color: color,
                      trackColor: SageColors.line,
                    ),
                    done
                        ? Icon(Icons.check, color: color, size: 15)
                        : Icon(icon, color: color, size: 15),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: done ? color : SageColors.ink,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value == 0 ? '0/$target' : '$value/$target',
                style: SageText.mono(
                  size: 10,
                  weight: FontWeight.w500,
                  color: SageColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Practice Card
// ────────────────────────────────────────────────────────────────────────────

class _PracticeCardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String lastSession;
  final bool done;
  final VoidCallback onTap;

  _PracticeCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.lastSession,
    required this.done,
    required this.onTap,
  });
}

// Built on StaggerItem (entrance) + Pressable (tap feedback) instead of
// a hand-rolled AnimationController — matches WellnessGridCard's feel
// because both are now literally built from the same two primitives.
class _PracticeCard extends StatelessWidget {
  const _PracticeCard({required this.data, required this.index});
  final _PracticeCardData data;
  final int index;

  @override
  Widget build(BuildContext context) {
    return StaggerItem(
      index: index,
      child: Pressable(
        onTap: data.onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SageColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: data.done
                  ? data.accent.withValues(alpha: 0.40)
                  : SageColors.line,
              width: data.done ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: data.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(data.icon, color: data.accent, size: 20),
                  ),
                  const Spacer(),
                  // AnimatedSwitcher so the "Done" badge fades in instead
                  // of popping into existence the instant a target is hit.
                  AnimatedSwitcher(
                    duration: SageMotion.valueChange,
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: data.done
                        ? Container(
                            key: const ValueKey('done'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: data.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check,
                                    color: data.accent, size: 10),
                                const SizedBox(width: 3),
                                Text(
                                  'Done',
                                  style: TextStyle(
                                    color: data.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('not-done')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                data.title,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                data.subtitle,
                style: TextStyle(fontSize: 11.5, color: SageColors.inkSoft),
              ),
              const Spacer(),
              Text(
                data.lastSession,
                style: TextStyle(
                  fontSize: 11,
                  color: data.done ? data.accent : SageColors.inkSoft,
                  fontWeight: data.done ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Health Status Card
// ────────────────────────────────────────────────────────────────────────────

class _HealthStatusCard extends StatelessWidget {
  const _HealthStatusCard({
    required this.overallScore,
    required this.scoreLabel,
    required this.scoreColor,
    required this.sleepScore,
    required this.nutritionScore,
    required this.checkinScore,
    required this.activityScore,
    required this.chronicScore,
    required this.hasChronicConditions,
    required this.advice,
    required this.hasData,
  });

  final int overallScore;
  final String scoreLabel;
  final Color scoreColor;
  final int sleepScore;
  final int nutritionScore;
  final int checkinScore;
  final int activityScore;
  final int chronicScore;
  final bool hasChronicConditions;
  final String advice;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SageColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SageColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text(
                'Health status',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              // Label badge cross-fades when the score label changes
              // (e.g. "Needs Care" → "On Track") instead of snapping.
              AnimatedSwitcher(
                duration: SageMotion.valueChange,
                child: Container(
                  key: ValueKey(scoreLabel),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    scoreLabel,
                    style: TextStyle(
                      color: scoreColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Score ring + pillars
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Animated ring — fills from 0 to overallScore on
                    // first paint and tweens smoothly whenever the score
                    // changes, instead of snapping straight to value.
                    _AnimatedScoreRing(
                      score: overallScore,
                      color: scoreColor,
                      trackColor: SageColors.line,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Cross-fades the number so a score change reads
                        // as a deliberate update, not a flicker.
                        AnimatedSwitcher(
                          duration: SageMotion.valueChange,
                          child: Text(
                            hasData ? '$overallScore' : '--',
                            key: ValueKey('$hasData-$overallScore'),
                            style: SageText.mono(
                              size: 20,
                              weight: FontWeight.w700,
                              color: scoreColor,
                            ),
                          ),
                        ),
                        Text(
                          'score',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: SageColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    AnimatedPillarRow(
                        label: 'Sleep',
                        score: sleepScore,
                        hasData: hasData,
                        icon: Icons.bedtime_outlined,
                        color: SageColors.moss),
                    const SizedBox(height: 7),
                    AnimatedPillarRow(
                        label: 'Nutrition',
                        score: nutritionScore,
                        hasData: hasData,
                        icon: Icons.restaurant_outlined,
                        color: SageColors.amber),
                    const SizedBox(height: 7),
                    AnimatedPillarRow(
                        label: 'Check-in',
                        score: checkinScore,
                        hasData: hasData,
                        icon: Icons.sentiment_satisfied_outlined,
                        color: SageColors.clay),
                    const SizedBox(height: 7),
                    AnimatedPillarRow(
                        label: 'Activity',
                        score: activityScore,
                        hasData: hasData,
                        icon: Icons.local_fire_department_outlined,
                        color: SageColors.sage),
                    if (hasChronicConditions) ...[
                      const SizedBox(height: 7),
                      AnimatedPillarRow(
                        label: 'Chronic',
                        score: chronicScore,
                        hasData: hasData,
                        icon: Icons.monitor_heart_outlined,
                        color: chronicScore >= 80
                            ? SageColors.sage
                            : SageColors.clay,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Advice tip — cross-fades its text so changing advice (e.g.
          // after a refresh pulls in new data) doesn't snap mid-sentence.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SageColors.sage.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.lightbulb_outline,
                      color: SageColors.moss, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: SageMotion.valueChange,
                    child: Text(
                      hasData
                          ? advice
                          : 'Log a meal, complete a check-in, or record sleep to see your health score.',
                      key: ValueKey(hasData ? advice : 'no-data'),
                      style: TextStyle(
                          color: SageColors.moss, fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// _PillarRow removed — replaced by AnimatedPillarRow (widgets/animated_pillar_row.dart)

// ────────────────────────────────────────────────────────────────────────────
// Animated arc — drop-in replacement for the static _ArcPainter usage in
// _ProgressMiniCard. Tweens its own progress value from 0 (or the previous
// value) to the target whenever [progress] changes, so the ring visibly
// fills rather than snapping.
// ────────────────────────────────────────────────────────────────────────────

class _AnimatedArc extends StatefulWidget {
  final double progress;
  final Color color;
  final Color trackColor;

  const _AnimatedArc({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  State<_AnimatedArc> createState() => _AnimatedArcState();
}

class _AnimatedArcState extends State<_AnimatedArc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: SageMotion.numberCountUp,
    );
    // Fills from 0 on first paint — a nice "loading in" feel for the
    // first frame, consistent with AnimatedPillarRow's bars.
    _anim = Tween<double>(begin: 0, end: widget.progress)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedArc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _anim = Tween<double>(begin: _anim.value, end: widget.progress).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        size: const Size(44, 44),
        painter: _ArcPainter(
          progress: _anim.value,
          color: widget.color,
          trackColor: widget.trackColor,
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const sw = 4.5;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - sw) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;

    // Track
    canvas.drawCircle(center, radius, paint..color = trackColor);

    // Arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.color != color;
}

// ────────────────────────────────────────────────────────────────────────────
// Animated score ring — same pattern as _AnimatedArc, for the larger
// 80x80 health-status ring. Tweens the integer score (rounded for paint)
// from its previous value to the new one instead of snapping.
// ────────────────────────────────────────────────────────────────────────────

class _AnimatedScoreRing extends StatefulWidget {
  final int score;
  final Color color;
  final Color trackColor;

  const _AnimatedScoreRing({
    required this.score,
    required this.color,
    required this.trackColor,
  });

  @override
  State<_AnimatedScoreRing> createState() => _AnimatedScoreRingState();
}

class _AnimatedScoreRingState extends State<_AnimatedScoreRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: SageMotion.revealLarge,
    );
    _anim = Tween<double>(begin: 0, end: widget.score.toDouble())
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedScoreRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
      _anim = Tween<double>(begin: _anim.value, end: widget.score.toDouble())
          .animate(
              CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        size: const Size(80, 80),
        painter: _ScoreRingPainter(
          score: _anim.value.round(),
          color: widget.color,
          trackColor: widget.trackColor,
        ),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  const _ScoreRingPainter({
    required this.score,
    required this.color,
    required this.trackColor,
  });

  final int score;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const sw = 7.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - sw) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, paint..color = trackColor);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * (score / 100.0),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) =>
      old.score != score || old.color != color;
}
