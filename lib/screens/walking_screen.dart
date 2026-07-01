// screens/walking_screen.dart
//
// Redesigned Walking screen.
//
// What's new vs the original:
//   • Idle state shows a weekly activity bar chart (7-day step bar mini-graph)
//     pulled from BellaService sessions, giving a streak-at-a-glance view.
//   • Active session flips to an ambient hero panel (SageColors.moss background)
//     with the big step counter, live timer, and activity chip — visually
//     distinct from the idle state so you know at a glance you're tracking.
//   • Milestone progress track: a permanent 4-node strip (25% → 50% → 75% → goal)
//     that fills as steps accumulate, replacing the ephemeral banner-only approach.
//     Banners still fire at each milestone for immediate feedback.
//   • 3-stat pill row (HR · kcal · km) replaces the 2×2 grid during active
//     mode — more glanceable while walking.
//   • Post-session summary uses showModalBottomSheet (matching zzzify pattern)
//     instead of AlertDialog — feels more native and shows a weekly session count.
//   • All existing logic preserved: pace coach, activity detection, BMI-based
//     goal, low-energy/poor-sleep context banners, BT data, DataStorage logging.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/data_storage_service.dart';
import '../services/user_service.dart';
import '../services/bella_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/reveal.dart';
import 'daily_checkin_screen.dart';

class WalkingScreen extends StatefulWidget {
  final int initialHeartRate;
  final int initialSteps;
  final bool isConnected;

  const WalkingScreen({
    super.key,
    required this.initialHeartRate,
    required this.initialSteps,
    this.isConnected = false,
  });

  @override
  State<WalkingScreen> createState() => _WalkingScreenState();
}

class _WalkingScreenState extends State<WalkingScreen>
    with TickerProviderStateMixin {
  // ── Services ───────────────────────────────────────────────────────────────
  final BluetoothService _bt = BluetoothService.instance;
  final DataStorageService _dataStorage = DataStorageService();
  final UserService _userService = UserService();
  final BellaService _bella = BellaService();

  // ── Session state ──────────────────────────────────────────────────────────
  Timer? _timer;
  int _seconds = 0;
  int _heartRate = 0;
  int _steps = 0;
  int _initialSteps = 0;
  bool _isActive = false;
  String _activityType = 'Walking';
  double _calories = 0;
  double _distance = 0;
  double _bmi = 22.5;
  int _targetSteps = 10000;
  String _bmiCategory = 'Normal';
  int? _fitlyStepsTarget;

  // ── Context flags ──────────────────────────────────────────────────────────
  List<String> _conditions = [];
  bool _lowEnergyDay = false;
  bool _poorSleepToday = false;
  bool _recentHeavyMeal = false; // high-cal meal within 90 min of now
  bool _lowWaterToday = false; // under-hydrated relative to time of day

  // Chronic reading context — null means no relevant reading / no condition.
  // Set to a non-null string to show a banner on the idle screen.
  String? _chronicReadingBanner;

  // ── Milestone banner ───────────────────────────────────────────────────────
  String? _milestoneBanner;
  Timer? _bannerTimer;
  final Set<int> _shownMilestones = {};

  // ── Last session ───────────────────────────────────────────────────────────
  String? _lastSessionSummary;

  // ── Weekly bar chart data ──────────────────────────────────────────────────
  // List of 7 entries [oldest … today], each = total minutes walked that day.
  List<int> _weekMinutes = List.filled(7, 0);

  // ── Activity detection ─────────────────────────────────────────────────────
  int _lastSteps = 0;
  DateTime? _lastUpdate;
  final List<int> _recentHeartRates = [];

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _ringController;
  late Animation<double> _ringProgress;

  // Drives the hero panel background colour-shift when session starts/stops.
  late AnimationController _ambientController;
  late Animation<double> _ambientFade;

  @override
  void initState() {
    super.initState();
    _heartRate = widget.initialHeartRate;
    _initialSteps = widget.initialSteps;
    _steps = 0;
    _conditions = UserService().currentUserObject?.chronicDiseases ?? [];

    _calculateBMIAndSetTarget();

    final fitlyTarget = _bella.getTarget<int>('steps');
    if (fitlyTarget != null) {
      _fitlyStepsTarget = fitlyTarget;
      _targetSteps = fitlyTarget;
    }

    final lastCheckin = _bella.lastCheckin;
    if (lastCheckin != null &&
        lastCheckin.energy <= 2 &&
        _fitlyStepsTarget == null) {
      _targetSteps = (_targetSteps * 0.6).round();
      _lowEnergyDay = true;
    }

    final lastSleep = _bella.lastNightSleep;
    if (lastSleep != null && lastSleep.quality <= 2) {
      _poorSleepToday = true;
    }

    // Food timing — warn if a heavy meal was logged within the last 90 min.
    final now = DateTime.now();
    final recentFood = _bella.getFoodEntries(onDate: now).where((f) {
      final age = now.difference(f.time).inMinutes;
      return age <= 90 && (f.calories ?? 0) >= 500;
    }).toList();
    if (recentFood.isNotEmpty) _recentHeavyMeal = true;

    // Hydration — flag under-hydration relative to time of day.
    final waterMl = _bella.todayWaterMl();
    final hour = now.hour;
    if ((hour >= 10 && waterMl < 500) || (hour >= 14 && waterMl < 1000)) {
      _lowWaterToday = true;
    }

    // Chronic reading context — show a walking-specific insight when a
    // recent reading is flagged. For Diabetes a high reading makes walking
    // genuinely therapeutic right now. For Hypertension a high reading
    // means a gentle pace is important. We check the most recent reading
    // only — we don't want to nag about readings from days ago.
    for (final cond in _conditions) {
      final readings = _bella.getReadings(condition: cond);
      if (readings.isEmpty) continue;
      final r = readings.first;
      // Only surface if the reading is recent (within 12 hours).
      if (now.difference(r.time).inHours > 12) continue;

      if (cond == 'Diabetes') {
        if (r.value > 180) {
          _chronicReadingBanner =
              'Your glucose is elevated (${r.value.toStringAsFixed(0)} ${r.unit}) — '
              'walking is one of the fastest ways to bring it down naturally.';
          break;
        } else if (r.value < 70) {
          _chronicReadingBanner =
              'Your glucose is low (${r.value.toStringAsFixed(0)} ${r.unit}) — '
              'have a fast-acting carb before starting and keep this walk gentle.';
          break;
        }
      } else if (cond == 'Hypertension' || cond == 'Heart Disease') {
        if (r.value >= 140 || (r.secondaryValue ?? 0) >= 90) {
          _chronicReadingBanner =
              'Blood pressure is elevated — keep your pace comfortable and '
              'stop if you feel chest tightness or dizziness.';
          break;
        }
      }
    }

    _loadLastSession();
    _loadWeekData();

    // Ring animation
    _ringController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _ringProgress = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );

    // Ambient fade animation (idle ↔ active hero panel)
    _ambientController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _ambientFade =
        CurvedAnimation(parent: _ambientController, curve: Curves.easeInOut);

    _bt.dataStream.listen((data) {
      if (!mounted) return;
      final newSteps = data.steps - _initialSteps;
      setState(() {
        _heartRate = data.heartRate;
        _steps = newSteps > 0 ? newSteps : 0;
        _recentHeartRates.add(data.heartRate);
        if (_recentHeartRates.length > 10) _recentHeartRates.removeAt(0);
        _detectActivityType();
        _calculateMetrics();
      });
      _animateRing();
      if (_isActive) _checkMilestone();
    });
  }

  void _loadLastSession() {
    final sessions = _bella.getSessions(type: 'walking');
    if (sessions.isEmpty) return;
    final last = sessions.first;
    final diff = DateTime.now().difference(last.date);
    String when;
    if (diff.inDays == 0) {
      when = 'today';
    } else if (diff.inDays == 1) {
      when = 'yesterday';
    } else {
      when = '${diff.inDays} days ago';
    }
    _lastSessionSummary = '${last.durationMinutes} min · $when';
  }

  void _loadWeekData() {
    final sessions = _bella.getSessions(type: 'walking');
    final now = DateTime.now();
    final mins = List<int>.filled(7, 0);
    // Index 0 = 6 days ago, index 6 = today
    for (final s in sessions) {
      final diff = now.difference(s.date).inDays;
      if (diff >= 0 && diff < 7) {
        mins[6 - diff] += s.durationMinutes;
      }
    }
    _weekMinutes = mins;
  }

  void _animateRing() {
    final target = (_steps / _targetSteps).clamp(0.0, 1.0);
    _ringProgress = Tween<double>(
      begin: _ringProgress.value,
      end: target,
    ).animate(CurvedAnimation(parent: _ringController, curve: Curves.easeOut));
    _ringController.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bannerTimer?.cancel();
    _ringController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  // ── Calculations ───────────────────────────────────────────────────────────

  void _calculateBMIAndSetTarget() {
    final user = _userService.currentUserObject;
    if (user != null && user.height > 0 && user.weight > 0) {
      final h = user.height / 100;
      _bmi = user.weight / (h * h);
      if (_bmi < 18.5) {
        _bmiCategory = 'Underweight';
        _targetSteps = 8000;
      } else if (_bmi <= 24.9) {
        _bmiCategory = 'Normal';
        _targetSteps = 10000;
      } else if (_bmi <= 29.9) {
        _bmiCategory = 'Overweight';
        _targetSteps = 7500;
      } else {
        _bmiCategory = 'Obese';
        _targetSteps = 5000;
      }
    } else {
      _bmiCategory = 'Normal';
      _targetSteps = 10000;
    }
  }

  void _detectActivityType() {
    if (_recentHeartRates.length < 5) return;
    final avg =
        _recentHeartRates.reduce((a, b) => a + b) / _recentHeartRates.length;
    if (avg > 120) {
      _activityType = 'Running';
    } else if (avg > 100) {
      _activityType = 'Brisk Walking';
    } else if (avg > 80) {
      _activityType = 'Walking';
    } else {
      _activityType = 'Slow Walking';
    }

    if (_lastUpdate != null && _steps > _lastSteps) {
      final diff = DateTime.now().difference(_lastUpdate!).inSeconds;
      if (diff > 0) {
        final sps = (_steps - _lastSteps) / diff;
        if (sps > 2.5) {
          _activityType = 'Running';
        } else if (sps > 1.8) {
          _activityType = 'Brisk Walking';
        }
      }
    }
    _lastSteps = _steps;
    _lastUpdate = DateTime.now();
  }

  void _calculateMetrics() {
    final user = _userService.currentUserObject;
    if (user == null) return;
    _distance = (_steps * 0.762) / 1000;
    double met = 2.5;
    if (_activityType == 'Running') met = 8.0;
    if (_activityType == 'Brisk Walking') met = 4.0;
    double weight = user.weight;
    if (_bmi > 30) weight *= 1.2;
    if (_bmi < 18.5) weight *= 0.9;
    _calories = (met * weight * _seconds) / 3600;
  }

  // ── Milestones ─────────────────────────────────────────────────────────────

  void _checkMilestone() {
    if (_targetSteps == 0) return;
    final pct = (_steps / _targetSteps * 100).round();
    for (final m in [25, 50, 75, 100]) {
      if (pct >= m && !_shownMilestones.contains(m)) {
        _shownMilestones.add(m);
        _showMilestoneBanner(m);
        break;
      }
    }
  }

  void _showMilestoneBanner(int pct) {
    final half = (_targetSteps ~/ 2);
    final messages = {
      25: 'Great start — 25% there! 🌱',
      50: 'Halfway! $half steps down 💚',
      75: 'Almost there — final stretch 🌿',
      100: 'Goal reached! $_targetSteps steps ✨',
    };
    setState(() => _milestoneBanner = messages[pct]);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _milestoneBanner = null);
    });
  }

  // How many of the 4 milestone thresholds have been crossed?
  int get _milestonesReached {
    if (_targetSteps == 0) return 0;
    final pct = (_steps / _targetSteps * 100);
    if (pct >= 100) return 4;
    if (pct >= 75) return 3;
    if (pct >= 50) return 2;
    if (pct >= 25) return 1;
    return 0;
  }

  // ── Session control ────────────────────────────────────────────────────────

  void _startWalking() {
    if (_isActive) {
      _stopWalking();
      return;
    }
    setState(() {
      _isActive = true;
      _seconds = 0;
      _steps = 0;
      _initialSteps = widget.initialSteps;
      _calories = 0;
      _distance = 0;
      _shownMilestones.clear();
    });
    _ambientController.forward();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  void _stopWalking() {
    _timer?.cancel();
    setState(() => _isActive = false);
    _ambientController.reverse();

    _dataStorage.saveWalkingSession(
      steps: _steps,
      distanceKm: _distance,
      calories: _calories,
      durationSeconds: _seconds,
      activityType: _activityType,
      timestamp: DateTime.now(),
      averageHeartRate: _heartRate,
    );
    _dataStorage.updateDailyGoal(
        goalType: 'steps',
        progress: _steps.toDouble(),
        target: _targetSteps.toDouble(),
        date: DateTime.now());
    _dataStorage.updateDailyGoal(
        goalType: 'activity',
        progress: _seconds / 60.0,
        target: 30.0,
        date: DateTime.now());

    if (_seconds >= 60) {
      _bella.logSession('walking', _seconds ~/ 60, detail: '$_steps');
    }

    // Refresh week data so chart is up to date if user starts another session
    _loadWeekData();

    _showSessionSummary();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Color _getActivityColor() {
    switch (_activityType) {
      case 'Running':
        return SageColors.clay;
      case 'Brisk Walking':
        return SageColors.amber;
      case 'Walking':
        return SageColors.moss;
      default:
        return SageColors.sage;
    }
  }

  Color _getBMIColor() {
    if (_bmi < 18.5) return SageColors.sage;
    if (_bmi <= 24.9) return SageColors.moss;
    if (_bmi <= 29.9) return SageColors.amber;
    return SageColors.clay;
  }

  Color _getHealthTipColor() {
    if (_conditions.contains('Heart Disease') ||
        _conditions.contains('Hypertension')) {
      return SageColors.clay;
    }
    if (_conditions.contains('Arthritis')) return SageColors.sage;
    if (_conditions.contains('Asthma')) return SageColors.amber;
    if (_bmi > 30) return SageColors.clay;
    if (_bmi > 25) return SageColors.amber;
    return SageColors.moss;
  }

  String _getTimeFormatted() {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _getPaceCoach() {
    if (!_isActive || _heartRate == 0) return 'Tap start and begin walking.';

    final hasHeartIssue = _conditions.contains('Heart Disease') ||
        _conditions.contains('Hypertension');

    if (hasHeartIssue && _heartRate > 130) {
      return 'HR at $_heartRate — ease off and slow your pace.';
    }
    if (_heartRate > 150) return 'HR very high — consider slowing down.';

    switch (_activityType) {
      case 'Running':
        return _heartRate > 140
            ? 'Good run · $_heartRate BPM · strong effort'
            : 'Running · $_heartRate BPM · excellent pace';
      case 'Brisk Walking':
        return 'Brisk pace · $_heartRate BPM · keep it up';
      case 'Walking':
        return 'Good rhythm · $_heartRate BPM · steady';
      default:
        return 'Gentle pace · $_heartRate BPM · every step counts';
    }
  }

  Color _getPaceCoachColor() {
    if (!_isActive) return SageColors.inkSoft;
    final hasHeartIssue = _conditions.contains('Heart Disease') ||
        _conditions.contains('Hypertension');
    if ((hasHeartIssue && _heartRate > 130) || _heartRate > 150) {
      return SageColors.clay;
    }
    if (_activityType == 'Running' || _activityType == 'Brisk Walking') {
      return SageColors.moss;
    }
    return SageColors.inkSoft;
  }

  String _getHealthTip() {
    if (_conditions.contains('Heart Disease') ||
        _conditions.contains('Hypertension')) {
      return 'Keep your heart rate below 130 BPM. Slow down if it rises.';
    }
    if (_conditions.contains('Arthritis')) {
      return 'Low-impact pace recommended. Listen to your joints.';
    }
    if (_conditions.contains('Asthma')) {
      return 'Keep your inhaler nearby. Breathe deeply and slowly.';
    }
    if (_bmi > 30) {
      return 'Start with short walks. Each step improves your health!';
    }
    if (_bmi > 25) return 'Regular walking helps manage weight effectively.';
    if (_bmi < 18.5) {
      return 'Walking boosts appetite and maintains healthy metabolism.';
    }
    return 'Walking maintains cardiovascular health and ideal weight.';
  }

  String _getTargetExplanation() {
    if (_lowEnergyDay) {
      return 'Target reduced today based on your low energy check-in. A gentle walk still counts.';
    }
    if (_fitlyStepsTarget != null) {
      return 'Target set from your Fitly wellness plan.';
    }
    if (_bmi < 18.5) {
      return '8,000 steps — sustainable goal for building healthy habits.';
    }
    if (_bmi <= 24.9) {
      return '10,000 steps — optimal for maintaining cardiovascular health.';
    }
    if (_bmi <= 29.9) {
      return '7,500 steps — sustainable target for weight management.';
    }
    return '5,000 steps — an achievable starting point. Build from here.';
  }

  // ── Bottom-sheet session summary ───────────────────────────────────────────

  void _showSessionSummary() {
    final goalPct = (_steps / _targetSteps * 100).clamp(0, 100).round();
    final weekSessions = _bella
        .getSessions(type: 'walking')
        .where((s) => DateTime.now().difference(s.date).inDays < 7)
        .length;

    showModalBottomSheet(
      context: context,
      backgroundColor: SageColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + mq.viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: SageColors.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Trophy + title
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: SageColors.moss.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.directions_walk,
                      color: SageColors.moss, size: 28),
                ),
                const SizedBox(height: 10),
                Text(
                  'Session complete',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: SageColors.ink),
                ),
                if (weekSessions > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$weekSessions session${weekSessions == 1 ? '' : 's'} this week 🌿',
                    style: TextStyle(fontSize: 13, color: SageColors.moss),
                  ),
                ],
                const SizedBox(height: 20),

                // 4-stat row
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SageColors.linen,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(color: SageColors.line),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _summaryCol('$_steps', 'Steps', SageColors.moss),
                      _vDivider(),
                      _summaryCol(_calories.toStringAsFixed(0), 'kcal',
                          SageColors.amber),
                      _vDivider(),
                      _summaryCol('${_distance.toStringAsFixed(2)} km',
                          'Distance', SageColors.sage),
                      _vDivider(),
                      _summaryCol(
                          _getTimeFormatted(), 'Time', SageColors.inkSoft),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Goal progress bar
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SageColors.card,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(color: SageColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Daily goal',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: SageColors.ink)),
                          Text('$goalPct%',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _getBMIColor())),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: goalPct / 100,
                          minHeight: 8,
                          backgroundColor: SageColors.line,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(_getBMIColor()),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('$_steps / $_targetSteps steps',
                          style: TextStyle(
                              fontSize: 11.5, color: SageColors.inkSoft)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Action row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: SageColors.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(12),
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text('Done',
                            style: TextStyle(color: SageColors.inkSoft)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const DailyCheckinScreen()));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SageColors.moss,
                          foregroundColor: SageColors.linen,
                          elevation: 0,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(12),
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Log check-in',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summaryCol(String value, String label, Color color) => Column(
        children: [
          Text(value,
              style: SageText.mono(
                  size: 15, weight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: SageColors.inkSoft)),
        ],
      );

  Widget _vDivider() => Container(
        width: 1,
        height: 30,
        color: SageColors.line,
      );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hrWarning = (_conditions.contains('Heart Disease') ||
            _conditions.contains('Hypertension')) &&
        _heartRate > 130 &&
        _isActive;

    return Scaffold(
      backgroundColor: SageColors.linen,
      body: Column(
        children: [
          // ── Ambient hero header (idle ring → active step counter) ─────────
          AnimatedBuilder(
            animation: _ambientFade,
            builder: (context, _) {
              return _buildHeroPanel(fade: _ambientFade.value);
            },
          ),

          // ── HR ceiling warning ────────────────────────────────────────────
          AnimatedSwitcher(
            duration: SageMotion.valueChange,
            child: hrWarning
                ? Container(
                    key: const ValueKey('hrwarn'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    color: SageColors.clay.withValues(alpha: 0.10),
                    child: Row(children: [
                      Icon(Icons.warning_amber_rounded,
                          color: SageColors.clay, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'HR at $_heartRate BPM — ease off and slow your pace.',
                          style: TextStyle(
                              color: SageColors.clay,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  )
                : const SizedBox.shrink(key: ValueKey('nohrwarn')),
          ),

          // ── Milestone banner ──────────────────────────────────────────────
          AnimatedSwitcher(
            duration: SageMotion.valueChange,
            child: _milestoneBanner != null
                ? Container(
                    key: ValueKey(_milestoneBanner),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    color: SageColors.moss,
                    child: Text(_milestoneBanner!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: SageColors.linen,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                  )
                : const SizedBox.shrink(key: ValueKey('nomilestone')),
          ),

          // ── Scrollable content ────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Reveal(
                size: RevealSize.large,
                child: AnimatedSwitcher(
                  duration: SageMotion.revealSmall,
                  switchInCurve: SageMotion.revealCurve,
                  switchOutCurve: Curves.easeIn,
                  child: _isActive
                      ? KeyedSubtree(
                          key: const ValueKey('active'),
                          child: _buildActiveBody(),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('idle'),
                          child: _buildIdleBody(),
                        ),
                ),
              ),
            ),
          ),

          // ── Bottom button bar ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: SageColors.card,
              border: Border(top: BorderSide(color: SageColors.line)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _startWalking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isActive ? SageColors.clay : _getBMIColor(),
                  foregroundColor: SageColors.linen,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isActive
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded),
                    const SizedBox(width: 10),
                    Text(
                      _isActive ? 'STOP WALKING' : 'START WALKING',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero panel ─────────────────────────────────────────────────────────────
  //
  // Transitions smoothly between two visual states using [fade] (0 = idle,
  // 1 = active). The background colour interpolates from transparent/linen
  // to SageColors.moss so it feels like the screen "wakes up".

  Widget _buildHeroPanel({required double fade}) {
    // Interpolate background: linen at idle, moss at active
    final bg = Color.lerp(
      SageColors.linen,
      SageColors.moss,
      fade * 0.92,
    )!;
    // Text colours: ink at idle, linen at active
    final primaryTxt = Color.lerp(SageColors.ink, SageColors.linen, fade)!;
    final mutedTxt = Color.lerp(
        SageColors.inkSoft, SageColors.linen.withValues(alpha: 0.7), fade)!;
    final chipBg = Color.lerp(
      SageColors.card,
      SageColors.linen.withValues(alpha: 0.15),
      fade,
    )!;
    final chipBorder = Color.lerp(
      SageColors.line,
      SageColors.linen.withValues(alpha: 0.3),
      fade,
    )!;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      color: bg,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 12, 20, 20),
      child: Column(
        children: [
          // AppBar row
          Row(
            children: [
              // Back button colour adapts
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: primaryTxt, size: 20),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Text('Walking', style: SageText.headline(color: primaryTxt)),
              const Spacer(),
              // Activity chip (visible during active session)
              if (_isActive)
                AnimatedOpacity(
                  opacity: fade,
                  duration: SageMotion.valueChange,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: chipBorder),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      // Pulsing dot
                      _PulseDot(color: SageColors.linen),
                      const SizedBox(width: 5),
                      Icon(
                        _activityType == 'Running'
                            ? Icons.directions_run
                            : Icons.directions_walk,
                        size: 13,
                        color: SageColors.linen,
                      ),
                      const SizedBox(width: 4),
                      Text(_activityType,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Idle: step ring   /   Active: big step counter
          if (!_isActive)
            // --- IDLE RING ---
            SizedBox(
              width: 200,
              height: 200,
              child: AnimatedBuilder(
                animation: _ringController,
                builder: (context, _) => CustomPaint(
                  painter: _StepRingPainter(
                    progress: _ringProgress.value,
                    color: _getBMIColor(),
                    trackColor: SageColors.line,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_steps',
                          style: SageText.mono(
                              size: 42,
                              weight: FontWeight.w700,
                              color: SageColors.ink),
                        ),
                        Text('steps',
                            style: TextStyle(
                                fontSize: 13, color: SageColors.inkSoft)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: SageColors.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: SageColors.line),
                          ),
                          child: Text(
                            '$_targetSteps target',
                            style: TextStyle(
                                fontSize: 12,
                                color: SageColors.inkSoft,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            // --- ACTIVE BIG COUNTER ---
            Column(
              children: [
                Text(
                  '$_steps',
                  style: SageText.mono(
                      size: 56,
                      weight: FontWeight.w700,
                      color: SageColors.linen),
                ),
                Text(
                    'steps · ${(_steps / _targetSteps * 100).clamp(0, 100).toStringAsFixed(0)}% of goal',
                    style: TextStyle(fontSize: 13, color: mutedTxt)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: chipBorder),
                  ),
                  child: Text(
                    '⏱ ${_getTimeFormatted()}',
                    style: TextStyle(
                        fontSize: 13,
                        color: SageColors.linen,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Idle body ──────────────────────────────────────────────────────────────

  Widget _buildIdleBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Context banners — priority capped at 2 maximum.
        // Chronic reading is always shown first if present (most urgent,
        // most specific). Then the single most relevant supporting signal:
        // heavy meal > low water > low energy / poor sleep.
        ..._buildContextBanners(),

        // Last session chip
        if (_lastSessionSummary != null) ...[
          _sectionLabel('Last session'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _cardDecoration(),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: SageColors.moss.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.history, size: 18, color: SageColors.moss),
              ),
              const SizedBox(width: 12),
              Text(_lastSessionSummary!,
                  style: TextStyle(
                      fontSize: 13.5,
                      color: SageColors.ink,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 20),
        ],

        // Weekly bar chart
        _sectionLabel('This week'),
        _buildWeekChart(),
        const SizedBox(height: 20),

        // Goal explanation
        _sectionLabel('Daily goal'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    '$_targetSteps steps',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _getBMIColor(),
                        fontFamily: 'monospace'),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _getBMIColor().withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_bmiCategory,
                      style: TextStyle(
                          fontSize: 11,
                          color: _getBMIColor(),
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.info_outline, size: 14, color: SageColors.inkSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_getTargetExplanation(),
                      style: TextStyle(
                          fontSize: 12.5,
                          color: SageColors.inkSoft,
                          height: 1.4)),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Health tip
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _getHealthTipColor().withValues(alpha: 0.06),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            border:
                Border.all(color: _getHealthTipColor().withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Icon(Icons.health_and_safety,
                color: _getHealthTipColor(), size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(_getHealthTip(),
                  style: TextStyle(
                      color: _getHealthTipColor(), fontSize: 13, height: 1.4)),
            ),
          ]),
        ),
      ],
    );
  }

  // ── Active body ────────────────────────────────────────────────────────────

  Widget _buildActiveBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 3-stat pill row
        Row(children: [
          _statPill(
            label: 'Heart Rate',
            value: '$_heartRate',
            unit: 'BPM',
            icon: Icons.favorite,
            color: ((_conditions.contains('Heart Disease') ||
                        _conditions.contains('Hypertension')) &&
                    _heartRate > 130)
                ? SageColors.clay
                : SageColors.clay,
          ),
          const SizedBox(width: 10),
          _statPill(
            label: 'Calories',
            value: _calories.toStringAsFixed(0),
            unit: 'kcal',
            icon: Icons.local_fire_department,
            color: SageColors.amber,
          ),
          const SizedBox(width: 10),
          _statPill(
            label: 'Distance',
            value: _distance.toStringAsFixed(2),
            unit: 'km',
            icon: Icons.map_outlined,
            color: SageColors.sage,
          ),
        ]),
        const SizedBox(height: 16),

        // Pace coach
        AnimatedSwitcher(
          duration: SageMotion.valueChange,
          child: Container(
            key: ValueKey(_getPaceCoach()),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _getPaceCoachColor().withValues(alpha: 0.07),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(
                  color: _getPaceCoachColor().withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(
                _heartRate > 130
                    ? Icons.warning_amber_rounded
                    : _activityType == 'Running'
                        ? Icons.directions_run
                        : Icons.directions_walk,
                color: _getPaceCoachColor(),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _getPaceCoach(),
                  style: TextStyle(
                      fontSize: 13.5,
                      color: _getPaceCoachColor(),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),

        // Milestone progress track
        _sectionLabel('Milestones'),
        _buildMilestoneTrack(),
        const SizedBox(height: 20),

        // Daily goal progress bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Daily goal',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: SageColors.ink)),
                  Text(
                    '${(_steps / _targetSteps * 100).clamp(0, 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _getBMIColor()),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (_steps / _targetSteps).clamp(0.0, 1.0),
                  backgroundColor: SageColors.line,
                  valueColor: AlwaysStoppedAnimation<Color>(_getBMIColor()),
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$_steps / $_targetSteps steps',
                      style:
                          TextStyle(fontSize: 12, color: SageColors.inkSoft)),
                  Text(
                    '${(_targetSteps - _steps).clamp(0, _targetSteps)} to go',
                    style: TextStyle(fontSize: 12, color: SageColors.inkSoft),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Weekly bar chart ───────────────────────────────────────────────────────

  Widget _buildWeekChart() {
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    // Align to today: figure out which weekday index (0=Mon) today is
    final todayWeekday = DateTime.now().weekday; // 1=Mon … 7=Sun
    // Which index in our 7-slot array is "today"? Always index 6.

    final maxMin = _weekMinutes.reduce(math.max);
    final displayMax = maxMin < 20 ? 30 : maxMin; // minimum bar scale

    // Label indices: 6 = today, going backwards
    // dayLabel for slot i: today is slot 6, so slot i is
    // (todayWeekday - 1 - (6 - i)) mod 7
    List<String> slotLabels = List.generate(7, (i) {
      final offset = 6 - i; // how many days ago slot i is
      final wd = ((todayWeekday - 1 - offset) % 7 + 7) % 7;
      return dayLabels[wd];
    });

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final mins = _weekMinutes[i];
              final isToday = i == 6;
              final barH = displayMax > 0
                  ? (mins / displayMax * 56).clamp(4.0, 56.0)
                  : 4.0;
              final barColor = isToday
                  ? _getBMIColor()
                  : mins > 0
                      ? _getBMIColor().withValues(alpha: 0.45)
                      : SageColors.line;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // bar
                      AnimatedContainer(
                        duration: SageMotion.numberCountUp,
                        curve: Curves.easeOut,
                        height: barH,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        slotLabels[i],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isToday ? FontWeight.w700 : FontWeight.w500,
                          color: isToday ? _getBMIColor() : SageColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            '${_weekMinutes.where((m) => m > 0).length} active days · '
            '${_weekMinutes.fold(0, (a, b) => a + b)} min total',
            style: TextStyle(fontSize: 11.5, color: SageColors.inkSoft),
          ),
        ],
      ),
    );
  }

  // ── Milestone progress track ───────────────────────────────────────────────

  Widget _buildMilestoneTrack() {
    final reached = _milestonesReached;
    final labels = ['25%', '50%', '75%', '🏁'];
    final sublabels = ['great\nstart', 'halfway', 'stretch', 'goal'];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _cardDecoration(),
      child: Row(
        children: List.generate(7, (i) {
          if (i.isOdd) {
            // Connector line
            final lineIndex = i ~/ 2; // 0, 1, 2
            final filled = reached > lineIndex;
            return Expanded(
              child: Container(
                height: 2,
                color: filled ? _getBMIColor() : SageColors.line,
              ),
            );
          }
          // Node
          final nodeIndex = i ~/ 2; // 0, 1, 2, 3
          final done = reached > nodeIndex;
          final active = reached == nodeIndex;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: SageMotion.valueChange,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? _getBMIColor()
                      : active
                          ? _getBMIColor().withValues(alpha: 0.12)
                          : SageColors.card,
                  border: Border.all(
                    color: done || active ? _getBMIColor() : SageColors.line,
                    width: done ? 0 : 1.5,
                  ),
                ),
                child: Center(
                  child: done
                      ? Icon(Icons.check_rounded,
                          color: SageColors.linen, size: 16)
                      : Text(
                          labels[nodeIndex],
                          style: TextStyle(
                            fontSize: nodeIndex == 3 ? 13 : 9,
                            fontWeight: FontWeight.w700,
                            color: active ? _getBMIColor() : SageColors.inkSoft,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                sublabels[nodeIndex],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.3,
                  color: done ? _getBMIColor() : SageColors.inkSoft,
                  fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ── Small widgets ──────────────────────────────────────────────────────────

  /// Builds at most 2 context banners with strict priority ordering:
  /// 1. Chronic reading (always first — most urgent, most specific)
  /// 2. The single most relevant supporting signal:
  ///    heavy meal > low water > low energy > poor sleep
  List<Widget> _buildContextBanners() {
    final banners = <Widget>[];

    // Primary: chronic reading — always shown if present
    if (_chronicReadingBanner != null) {
      banners.add(_contextBanner(
        icon: Icons.monitor_heart_outlined,
        text: _chronicReadingBanner!,
        color: SageColors.clay,
      ));
    }

    // Secondary: one supporting signal, by priority
    if (banners.length < 2) {
      if (_recentHeavyMeal) {
        banners.add(_contextBanner(
          icon: Icons.restaurant_outlined,
          text: 'Heavy meal logged in the last 90 min — give it another '
              '30 min before walking hard. A gentle stroll is fine now.',
          color: SageColors.amber,
        ));
      } else if (_lowWaterToday) {
        banners.add(_contextBanner(
          icon: Icons.water_drop_outlined,
          text: 'You\'re under-hydrated for this time of day — drink a '
              'glass of water before you start.',
          color: SageColors.moss,
        ));
      } else if (_lowEnergyDay) {
        banners.add(_contextBanner(
          icon: Icons.battery_alert,
          text: 'Low energy today — target reduced to $_targetSteps steps. '
              'Listen to your body.',
          color: SageColors.amber,
        ));
      } else if (_poorSleepToday) {
        banners.add(_contextBanner(
          icon: Icons.bedtime_outlined,
          text: 'Rough night — walk at a comfortable pace and don\'t push it.',
          color: SageColors.inkSoft,
        ));
      }
    }

    return banners;
  }

  Widget _contextBanner(
      {required IconData icon, required String text, required Color color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _statPill({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value,
                    style: SageText.mono(
                        size: 18,
                        weight: FontWeight.w700,
                        color: SageColors.ink)),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(unit,
                        style:
                            TextStyle(fontSize: 10, color: SageColors.inkSoft)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 10.5, color: SageColors.inkSoft)),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: SageColors.inkSoft,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: SageColors.card,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(4),
        topRight: Radius.circular(20),
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(20),
      ),
      border: Border.all(color: SageColors.line),
    );
  }
}

// ── Pulsing live dot ──────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.25, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

// ── Step ring painter ─────────────────────────────────────────────────────────

class _StepRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  const _StepRingPainter(
      {required this.progress, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    const pi = math.pi;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_StepRingPainter old) =>
      old.progress != progress || old.color != color;
}