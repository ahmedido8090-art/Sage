// screens/daily_checkin_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/bella_service.dart';
import '../services/user_service.dart';
import '../services/bluetooth_service.dart';
import '../models/bella_data.dart';
import '../widgets/reveal.dart';
import 'breathwork_screen.dart';
import 'meditation_screen.dart';
import 'zzzify_screen.dart';
import 'pure_plate_screen.dart';
import 'walking_screen.dart';
import 'chronic_care_screen.dart';

/// Time period options for the analytics tab. Same scheme as ZZZify so the
/// two screens feel consistent.
enum _Period { day3, week, day14, month }

extension _PeriodExt on _Period {
  String get label {
    switch (this) {
      case _Period.day3:
        return '3 Days';
      case _Period.week:
        return '7 Days';
      case _Period.day14:
        return '14 Days';
      case _Period.month:
        return '30 Days';
    }
  }

  int get days {
    switch (this) {
      case _Period.day3:
        return 3;
      case _Period.week:
        return 7;
      case _Period.day14:
        return 14;
      case _Period.month:
        return 30;
    }
  }
}

/// Bella · Daily Check-in.
/// Log tab       : mood / stress / energy check-in, pre-checkin context,
///                 instant recommendations routed to the right screen.
/// Analytics tab : period-aware graph (hide/show today), averages,
///                 detailed report with narrative, cross-data insights,
///                 and full check-in history with delete.
class DailyCheckinScreen extends StatefulWidget {
  const DailyCheckinScreen({super.key});

  @override
  State<DailyCheckinScreen> createState() => _DailyCheckinScreenState();
}

class _DailyCheckinScreenState extends State<DailyCheckinScreen>
    with SingleTickerProviderStateMixin {
  final BellaService _bella = BellaService();
  final BluetoothService _bt = BluetoothService.instance;
  int _liveHeartRate = 72; // updated from band if connected

  // ── Log-tab state ──────────────────────────────────────────────────────
  int _mood = 3;
  int _stress = 3;
  int _energy = 3;
  String? _note;
  CheckinEntry? _justSaved;

  // ── Analytics-tab state ─────────────────────────────────────────────────
  _Period _period = _Period.week;
  bool _showToday = true;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Keep live HR in sync if band is connected
    _bt.dataStream.listen((data) {
      if (mounted && data.heartRate > 0) {
        setState(() => _liveHeartRate = data.heartRate);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  double get _bmi {
    final user = UserService().currentUserObject;
    if (user != null && user.height > 0 && user.weight > 0) {
      final h = user.height / 100;
      return user.weight / (h * h);
    }
    return 22.5;
  }

  String _bmiCategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    return 'Obese';
  }

  Future<void> _submit() async {
    final entry = CheckinEntry(
        time: DateTime.now(),
        mood: _mood,
        stress: _stress,
        energy: _energy,
        note: _note);
    await _bella.addCheckin(entry);
    setState(() => _justSaved = entry);
  }

  // ── Pre-checkin context banners ───────────────────────────────────────────

  List<_CheckinContext> _buildPreCheckinContext() {
    final ctx = <_CheckinContext>[];

    final lastSleep = _bella.lastNightSleep;
    if (lastSleep != null) {
      if (lastSleep.quality <= 2) {
        ctx.add(_CheckinContext(
          icon: Icons.nights_stay_outlined,
          color: SageColors.clay,
          text: 'Last night\'s sleep was rated ${lastSleep.quality}/5 — '
              'that may be pulling your energy and mood down today.',
        ));
      } else if (lastSleep.quality >= 4) {
        ctx.add(_CheckinContext(
          icon: Icons.nights_stay_outlined,
          color: SageColors.moss,
          text: 'You had a solid night\'s sleep (${lastSleep.quality}/5). '
              'That\'s a good start for today.',
        ));
      }
    }

    final foodToday = _bella.getFoodEntries(onDate: DateTime.now());
    final totalCal = foodToday.fold<int>(0, (s, f) => s + (f.calories ?? 0));
    if (totalCal == 0 && DateTime.now().hour >= 10) {
      ctx.add(_CheckinContext(
        icon: Icons.restaurant_outlined,
        color: SageColors.amber,
        text: 'You haven\'t logged any meals yet today. Food and hydration '
            'directly affect mood and energy.',
      ));
    }
    if (foodToday.any((f) => f.tag == 'high-sodium')) {
      ctx.add(_CheckinContext(
        icon: Icons.water_drop_outlined,
        color: SageColors.amber,
        text: 'High-sodium food today can cause bloating and sluggishness.',
      ));
    }

    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];
    for (final cond in conditions) {
      final readings = _bella.getReadings(condition: cond);
      if (readings.isEmpty) continue;
      final r = readings.first;
      final bool flagged;
      switch (cond) {
        case 'Diabetes':
          flagged = r.value < 70 || r.value > 180;
        case 'Hypertension':
        case 'Heart Disease':
        case 'Chronic Kidney Disease':
          flagged = r.value >= 140 || (r.secondaryValue ?? 0) >= 90;
        case 'Arthritis':
          flagged = r.value >= 6;
        case 'Asthma':
          flagged = r.value < 300;
        case 'High Cholesterol':
          flagged = r.value > 240;
        default:
          flagged = false;
      }
      if (flagged) {
        ctx.add(_CheckinContext(
          icon: Icons.monitor_heart_outlined,
          color: SageColors.clay,
          text: 'Your recent $cond reading was out of range. '
              'This can affect how you feel today.',
        ));
      }
    }

    // Activity sessions today — positively frame the check-in if something
    // was completed; absence of any activity by the afternoon is also useful.
    final walkingMin = _bella.sessionMinutesToday('walking');
    final meditationMin = _bella.sessionMinutesToday('meditation');
    final breathworkMin = _bella.sessionMinutesToday('breathwork');
    final sleepSoundsMin = _bella.sessionMinutesToday('sleep_sounds');
    final totalActivityMin =
        walkingMin + meditationMin + breathworkMin + sleepSoundsMin;
    final now = DateTime.now();

    if (totalActivityMin >= 20) {
      ctx.add(_CheckinContext(
        icon: Icons.directions_walk_outlined,
        color: SageColors.moss,
        text:
            'You\'ve already put in $totalActivityMin min of activity today — '
            'that tends to lift mood and energy. Factor that in.',
      ));
    } else if (now.hour >= 15 && totalActivityMin == 0) {
      ctx.add(_CheckinContext(
        icon: Icons.directions_walk_outlined,
        color: SageColors.inkSoft,
        text: 'No activity logged yet today. Even a short walk can shift '
            'energy and mood — worth noting if you\'re feeling flat.',
      ));
    }

    // Hydration — under-hydration is a common unrecognised cause of low energy.
    final waterMl = _bella.todayWaterMl();
    final hour = now.hour;
    if ((hour >= 10 && waterMl < 400) || (hour >= 14 && waterMl < 800)) {
      ctx.add(_CheckinContext(
        icon: Icons.water_drop_outlined,
        color: SageColors.moss,
        text: 'You\'re under-hydrated for this time of day '
            '(${waterMl}ml logged). Low water intake is a common '
            'cause of low energy and poor concentration.',
      ));
    }

    return ctx;
  }

  // ── Post-submission recommendations ──────────────────────────────────────
  //
  // This is the bit that routes a bad mood/stress/energy reading to a
  // concrete activity in Wellness (Breathwork / Meditation / Walking) or
  // to ZZZify / PurePlate. It's unchanged from before — it still runs every
  // time a check-in is submitted, in _buildResult below. If it ever looked
  // "missing" it's most likely because it only shows on the result panel
  // right after you submit, not in the Analytics tab or history list.

  List<_Recommendation> _buildRecommendations(CheckinEntry entry) {
    final recs = <_Recommendation>[];
    final bmi = _bmi;

    if (entry.stress >= 4) {
      recs.add(_Recommendation(
        icon: Icons.air,
        color: SageColors.clay,
        title: 'Breathwork',
        subtitle: 'Even 5 minutes reduces cortisol.',
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => BreathworkScreen(
                    initialHeartRate: _liveHeartRate, autoStart: true))),
      ));
    }

    if (entry.mood <= 2 || entry.energy <= 2) {
      recs.add(_Recommendation(
        icon: Icons.self_improvement,
        color: SageColors.sage,
        title: 'Meditation',
        subtitle: 'Grounds you when mood or energy dips.',
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => MeditationScreen(
                    initialHeartRate: _liveHeartRate,
                    bmi: bmi,
                    bmiCategory: _bmiCategory(bmi)))),
      ));
    }

    final lastSleep = _bella.lastNightSleep;
    final goodSleep = lastSleep != null && lastSleep.quality >= 3;
    if (entry.energy <= 2 && goodSleep) {
      final foodToday = _bella.getFoodEntries(onDate: DateTime.now());
      final totalCal = foodToday.fold<int>(0, (s, f) => s + (f.calories ?? 0));
      if (totalCal < 400 && DateTime.now().hour >= 11) {
        recs.add(_Recommendation(
          icon: Icons.restaurant_outlined,
          color: SageColors.amber,
          title: 'Check your nutrition',
          subtitle:
              'You\'ve slept well but energy is low — you may need more fuel.',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PurePlateScreen())),
        ));
      } else {
        recs.add(_Recommendation(
          icon: Icons.directions_walk,
          color: SageColors.amber,
          title: 'Light walk',
          subtitle: 'A 10-min walk can lift energy better than rest.',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => WalkingScreen(
                      initialHeartRate: _liveHeartRate, initialSteps: 0))),
        ));
      }
    }

    if (lastSleep != null && lastSleep.quality <= 2 && entry.isLow) {
      recs.add(_Recommendation(
        icon: Icons.bedtime_outlined,
        color: SageColors.moss,
        title: 'Prioritise sleep tonight',
        subtitle: 'Poor sleep is amplifying today\'s low score.',
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ZZZifyScreen())),
      ));
    }

    final foodToday = _bella.getFoodEntries(onDate: DateTime.now());
    if (entry.stress >= 4 && foodToday.any((f) => f.tag == 'high-sodium')) {
      recs.add(_Recommendation(
        icon: Icons.water_drop_outlined,
        color: SageColors.clay,
        title: 'Hydrate well today',
        subtitle:
            'High sodium + stress both raise blood pressure. Water helps.',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PurePlateScreen())),
      ));
    }

    if (recs.isEmpty && !entry.isLow) {
      recs.add(_Recommendation(
        icon: Icons.directions_walk,
        color: SageColors.moss,
        title: 'Keep it up with movement',
        subtitle: 'You\'re feeling good — channel that into a walk.',
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => WalkingScreen(
                    initialHeartRate: _liveHeartRate, initialSteps: 0))),
      ));
    }
    return recs.take(3).toList();
  }

  // ── Cross-data trend insights (shown in the Analytics report) ────────────

  List<_TrendInsight> _buildTrendInsights(List<CheckinEntry> period) {
    final insights = <_TrendInsight>[];
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];
    final cutoff = DateTime.now().subtract(Duration(days: _period.days));

    final sleepEntries = _bella.getSleepEntries();
    final recentSleepNights =
        sleepEntries.where((e) => e.date.isAfter(cutoff) && !e.isNap).toList();
    if (recentSleepNights.isNotEmpty) {
      final avgQuality = recentSleepNights
              .map((e) => e.quality)
              .fold<int>(0, (a, b) => a + b) /
          recentSleepNights.length;
      if (avgQuality < 2.5 && period.isNotEmpty) {
        final avgEnergy =
            period.map((e) => e.energy).fold<int>(0, (a, b) => a + b) /
                period.length;
        if (avgEnergy < 2.5) {
          insights.add(_TrendInsight(
            icon: Icons.nights_stay_outlined,
            color: SageColors.clay,
            text:
                'Your energy dip this period may be linked to poor sleep quality '
                '(avg ${avgQuality.toStringAsFixed(1)}/5). '
                'Improving sleep consistency should help restore energy.',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ZZZifyScreen())),
          ));
        }
      }
    }

    final foodInPeriod =
        _bella.getFoodEntries().where((f) => f.time.isAfter(cutoff)).toList();
    final highCarbDays = <String>{};
    for (final f in foodInPeriod) {
      if (f.tag == 'high-carb') {
        highCarbDays.add('${f.time.year}-${f.time.month}-${f.time.day}');
      }
    }
    if (highCarbDays.length >= 3 && period.isNotEmpty) {
      final avgMood = period.map((e) => e.mood).fold<int>(0, (a, b) => a + b) /
          period.length;
      if (avgMood < 3) {
        insights.add(_TrendInsight(
          icon: Icons.bakery_dining_outlined,
          color: SageColors.amber,
          text:
              'You\'ve had high-carb meals on ${highCarbDays.length} days this period. '
              'Carb-heavy diets can cause blood sugar spikes and crashes that '
              'affect mood and energy — try adding more protein and fibre.',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PurePlateScreen())),
        ));
      }
    }

    for (final cond in conditions) {
      final readings = _bella
          .getReadings(condition: cond)
          .where((r) => r.time.isAfter(cutoff))
          .toList();
      if (readings.isNotEmpty) {
        final anyElevated = readings.any((r) =>
            (cond == 'Diabetes' && (r.value < 70 || r.value > 180)) ||
            (cond == 'Hypertension' &&
                (r.value >= 140 || (r.secondaryValue ?? 0) >= 90)));
        final allNormal = readings.every((r) =>
            (cond == 'Diabetes' && r.value >= 70 && r.value <= 180) ||
            (cond == 'Hypertension' &&
                r.value < 140 &&
                (r.secondaryValue ?? 0) < 90));
        if (anyElevated) {
          insights.add(_TrendInsight(
            icon: Icons.monitor_heart_outlined,
            color: SageColors.clay,
            text: 'Your $cond readings have been elevated this period. '
                'Uncontrolled $cond can directly lower energy and mood — '
                'keep monitoring and review your diet plan.',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChronicCareScreen())),
          ));
        } else if (allNormal && readings.length >= 2) {
          insights.add(_TrendInsight(
            icon: Icons.monitor_heart_outlined,
            color: SageColors.moss,
            text: 'Your $cond readings are stable this period — keep up the '
                'consistent routine. Good readings support better energy and mood.',
          ));
        }
      }
    }

    if (period.length >= 4) {
      final scores = period.map((e) => e.wellbeingScore).toList();
      final firstHalf = scores.take(scores.length ~/ 2).toList();
      final secondHalf = scores.skip(scores.length ~/ 2).toList();
      final firstAvg = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
      final secondAvg = secondHalf.reduce((a, b) => a + b) / secondHalf.length;
      final delta = secondAvg - firstAvg;
      if (delta > 1.5) {
        insights.add(_TrendInsight(
          icon: Icons.trending_up,
          color: SageColors.moss,
          text: 'Great progress! Your wellbeing score has improved by '
              '${delta.toStringAsFixed(1)} points in the second half of this period. '
              'Keep going with your current habits.',
        ));
      } else if (delta < -1.5) {
        insights.add(_TrendInsight(
          icon: Icons.trending_down,
          color: SageColors.clay,
          text:
              'Your wellbeing score has dipped ${delta.abs().toStringAsFixed(1)} '
              'points this period. Consider reviewing your sleep routine, '
              'diet, and stress management.',
        ));
      }
    }

    return insights;
  }

  // ── Per-metric change commentary vs the period baseline ───────────────────

  List<_TrendInsight> _buildMetricDeltaInsights(
      CheckinEntry entry, List<CheckinEntry> period) {
    final insights = <_TrendInsight>[];
    final baseline = period
        .where((e) =>
            e.time.difference(entry.time).abs() > const Duration(minutes: 1))
        .toList();
    if (baseline.length < 2) return insights;

    double avgOf(List<int> vals) =>
        vals.fold<int>(0, (a, b) => a + b) / vals.length;

    final moodAvg = avgOf(baseline.map((e) => e.mood).toList());
    final stressAvg = avgOf(baseline.map((e) => e.stress).toList());
    final energyAvg = avgOf(baseline.map((e) => e.energy).toList());

    final moodDelta = entry.mood - moodAvg;
    final stressDelta = entry.stress - stressAvg;
    final energyDelta = entry.energy - energyAvg;

    const threshold = 0.8;

    if (moodDelta <= -threshold) {
      insights.add(_TrendInsight(
        icon: Icons.sentiment_dissatisfied_outlined,
        color: SageColors.clay,
        text: 'Mood is down ${moodDelta.abs().toStringAsFixed(1)} pts vs your '
            'recent average (${moodAvg.toStringAsFixed(1)}/5) — worth noting if '
            'this continues tomorrow.',
      ));
    } else if (moodDelta >= threshold) {
      insights.add(_TrendInsight(
        icon: Icons.sentiment_satisfied_alt_outlined,
        color: SageColors.moss,
        text: 'Mood is up ${moodDelta.toStringAsFixed(1)} pts vs your recent '
            'average (${moodAvg.toStringAsFixed(1)}/5) — whatever you did '
            'today, it\'s working.',
      ));
    }

    if (stressDelta >= threshold) {
      insights.add(_TrendInsight(
        icon: Icons.bolt,
        color: SageColors.clay,
        text: 'Stress is up ${stressDelta.toStringAsFixed(1)} pts vs your '
            'recent average (${stressAvg.toStringAsFixed(1)}/5). A short '
            'breathwork session can bring this back down quickly.',
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const BreathworkScreen(
                    initialHeartRate: 72, autoStart: true))),
      ));
    } else if (stressDelta <= -threshold) {
      insights.add(_TrendInsight(
        icon: Icons.spa_outlined,
        color: SageColors.moss,
        text: 'Stress is down ${stressDelta.abs().toStringAsFixed(1)} pts vs '
            'your recent average (${stressAvg.toStringAsFixed(1)}/5) — '
            'noticeably calmer than usual today.',
      ));
    }

    if (energyDelta <= -threshold) {
      insights.add(_TrendInsight(
        icon: Icons.battery_alert_outlined,
        color: SageColors.amber,
        text: 'Energy is down ${energyDelta.abs().toStringAsFixed(1)} pts vs '
            'your recent average (${energyAvg.toStringAsFixed(1)}/5). Check '
            'sleep and food logs from yesterday for likely causes.',
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ZZZifyScreen())),
      ));
    } else if (energyDelta >= threshold) {
      insights.add(_TrendInsight(
        icon: Icons.battery_charging_full_outlined,
        color: SageColors.moss,
        text: 'Energy is up ${energyDelta.toStringAsFixed(1)} pts vs your '
            'recent average (${energyAvg.toStringAsFixed(1)}/5) — a good day '
            'to tackle something demanding.',
      ));
    }

    return insights;
  }

  // ── Period report builder (averages + narrative) ─────────────────────────

  _CheckinReport _buildReport(List<CheckinEntry> entries) {
    if (entries.isEmpty) {
      return const _CheckinReport(
        count: 0,
        avgMood: null,
        avgStress: null,
        avgEnergy: null,
        avgWellbeing: null,
        lowDays: 0,
        goodDays: 0,
        narrative: 'No check-ins logged in this period yet.',
      );
    }

    double avgOf(List<int> vals) =>
        vals.fold<int>(0, (a, b) => a + b) / vals.length;
    final avgMood = avgOf(entries.map((e) => e.mood).toList());
    final avgStress = avgOf(entries.map((e) => e.stress).toList());
    final avgEnergy = avgOf(entries.map((e) => e.energy).toList());
    final avgWellbeing =
        entries.map((e) => e.wellbeingScore).reduce((a, b) => a + b) /
            entries.length;
    final lowDays = entries.where((e) => e.isLow).length;
    final goodDays = entries.where((e) => e.wellbeingScore >= 7).length;

    String narrative;
    if (avgWellbeing >= 7) {
      narrative = 'A strong period overall — average wellbeing is '
          '${avgWellbeing.toStringAsFixed(1)}/10 with $goodDays good day'
          '${goodDays == 1 ? '' : 's'} out of ${entries.length}. Keep your '
          'current routine going.';
    } else if (avgWellbeing >= 4.5) {
      narrative = 'A mixed period — average wellbeing sits at '
          '${avgWellbeing.toStringAsFixed(1)}/10. ${lowDays > 0 ? '$lowDays low day${lowDays == 1 ? '' : 's'} pulled the average down; ' : ''}'
          '${avgStress >= 3.5 ? 'stress has been the main driver this period — a daily breathwork or meditation habit could help. ' : ''}'
          '${avgEnergy <= 2.5 ? 'Energy has also been on the lower side — check your sleep and meals.' : ''}';
    } else {
      narrative = 'This has been a tough period — average wellbeing is '
          '${avgWellbeing.toStringAsFixed(1)}/10 with $lowDays low day'
          '${lowDays == 1 ? '' : 's'} out of ${entries.length}. '
          '${avgStress >= 3.5 ? 'Stress has been consistently high — breathwork or meditation, even briefly each day, tends to move this fastest. ' : ''}'
          '${avgEnergy <= 2.5 ? 'Energy has also stayed low — worth checking sleep quality and nutrition. ' : ''}'
          'Consider talking to someone you trust if this continues.';
    }

    return _CheckinReport(
      count: entries.length,
      avgMood: avgMood,
      avgStress: avgStress,
      avgEnergy: avgEnergy,
      avgWellbeing: avgWellbeing,
      lowDays: lowDays,
      goodDays: goodDays,
      narrative: narrative,
    );
  }

  List<CheckinEntry> get _weekCheckins {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _bella.getCheckins().where((c) => c.time.isAfter(cutoff)).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final week = _weekCheckins;

    // --- Analytics-tab data ---
    final today = DateTime.now();
    final cutoff = today.subtract(Duration(days: _period.days));
    final periodEntries = _bella
        .getCheckins()
        .where((c) =>
            c.time.isAfter(cutoff) ||
            (c.time.year == cutoff.year &&
                c.time.month == cutoff.month &&
                c.time.day == cutoff.day))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    final graphEntries = _showToday
        ? periodEntries
        : periodEntries
            .where((e) => !(e.time.year == today.year &&
                e.time.month == today.month &&
                e.time.day == today.day))
            .toList();

    final report = _buildReport(periodEntries);
    final trendInsights = _buildTrendInsights(periodEntries);

    return Scaffold(
      backgroundColor: SageColors.linen,
      appBar: AppBar(
        backgroundColor: SageColors.linen,
        title: Text('Daily Check-in',
            style: SageText.headline(color: SageColors.ink)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: SageColors.amber,
          labelColor: SageColors.amber,
          unselectedLabelColor: SageColors.inkSoft,
          tabs: const [
            Tab(text: 'Log'),
            Tab(text: 'Analytics'),
          ],
        ),
      ),
      body: Reveal(size: RevealSize.large,
        child: TabBarView(
          controller: _tabController,
          children: [
            // ════════════════════════════════════════════════════════════
            // TAB 1 — LOG
            // ════════════════════════════════════════════════════════════
            _buildLogTab(week),

            // ════════════════════════════════════════════════════════════
            // TAB 2 — ANALYTICS
            // ════════════════════════════════════════════════════════════
            _buildAnalyticsTab(
                periodEntries, graphEntries, report, trendInsights),
          ],
        ),
      ),
    );
  }

  // ══ Log tab ════════════════════════════════════════════════════════════════

  Widget _buildLogTab(List<CheckinEntry> week) {
    final alreadyDone = _bella.hasCheckedInToday();
    final preCtx = _buildPreCheckinContext();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_justSaved == null && preCtx.isNotEmpty) ...[
            ...preCtx.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _contextBanner(c),
                )),
            const SizedBox(height: 4),
          ],
          if (_justSaved == null) ...[
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How are you, really?',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: SageColors.ink)),
                  const SizedBox(height: 6),
                  Text(
                    alreadyDone
                        ? 'You already checked in today — this will update it.'
                        : 'Takes 30 seconds. Honest answers give better guidance.',
                    style: TextStyle(fontSize: 12, color: SageColors.inkSoft),
                  ),
                  const SizedBox(height: 18),
                  _slider('Mood', _mood, (v) => setState(() => _mood = v),
                      Icons.sentiment_satisfied_alt_outlined),
                  _moodLabel(_mood, false),
                  const SizedBox(height: 16),
                  _slider('Stress', _stress, (v) => setState(() => _stress = v),
                      Icons.bolt_outlined,
                      invert: true),
                  _moodLabel(_stress, true),
                  const SizedBox(height: 16),
                  _slider('Energy', _energy, (v) => setState(() => _energy = v),
                      Icons.battery_charging_full_outlined),
                  _moodLabel(_energy, false),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (v) => _note = v.isEmpty ? null : v,
                    decoration: InputDecoration(
                      hintText: 'Add a note (optional)',
                      filled: true,
                      fillColor: SageColors.linen,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _wellbeingPreview(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SageColors.amber,
                        foregroundColor: SageColors.ink,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Check in',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ] else
            _buildResult(_justSaved!),
        ],
      ),
    );
  }

  // ══ Analytics tab ═════════════════════════════════════════════════════════

  Widget _buildAnalyticsTab(
    List<CheckinEntry> periodEntries,
    List<CheckinEntry> graphEntries,
    _CheckinReport report,
    List<_TrendInsight> trendInsights,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodRow(),
          const SizedBox(height: 16),
          _buildAverageCard(report),
          const SizedBox(height: 16),
          _buildGraphCard(graphEntries),
          const SizedBox(height: 16),
          _buildDetailedReport(report),
          if (trendInsights.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSectionLabel('CROSS-DATA INSIGHTS'),
            const SizedBox(height: 10),
            ...trendInsights.map((ins) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _trendInsightBanner(ins),
                )),
          ],
          if (periodEntries.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSectionLabel('HISTORY'),
            const SizedBox(height: 10),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: periodEntries.reversed
                    .take(20)
                    .map((e) => _checkinHistoryRow(e))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodRow() {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _Period.values.map((p) {
                final sel = _period == p;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _period = p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? SageColors.amber : SageColors.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: sel ? SageColors.amber : SageColors.line),
                      ),
                      child: Text(p.label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  sel ? SageColors.ink : SageColors.inkSoft)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => _showToday = !_showToday),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _showToday
                  ? SageColors.moss.withValues(alpha: 0.12)
                  : SageColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _showToday ? SageColors.moss : SageColors.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  _showToday
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_outlined,
                  size: 13,
                  color: _showToday ? SageColors.moss : SageColors.inkSoft),
              const SizedBox(width: 5),
              Text('Today',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color:
                          _showToday ? SageColors.moss : SageColors.inkSoft)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildAverageCard(_CheckinReport report) {
    final score = report.avgWellbeing;
    final color = score == null
        ? SageColors.inkSoft
        : score >= 7
            ? SageColors.moss
            : score >= 4.5
                ? SageColors.amber
                : SageColors.clay;
    return _card(
      child: Row(children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
          ),
          child: Center(
            child: score == null
                ? Icon(Icons.mood_outlined, color: SageColors.inkSoft, size: 22)
                : Text(score.toStringAsFixed(1),
                    style: SageText.mono(
                        size: 18, weight: FontWeight.w700, color: color)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                score == null
                    ? 'No data for this period'
                    : 'Avg wellbeing  ·  ${_period.label}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: SageColors.ink),
              ),
              const SizedBox(height: 6),
              if (report.avgMood != null)
                Text(
                  'Mood ${report.avgMood!.toStringAsFixed(1)} · '
                  'Stress ${report.avgStress!.toStringAsFixed(1)} · '
                  'Energy ${report.avgEnergy!.toStringAsFixed(1)}  (avg over ${report.count})',
                  style: TextStyle(fontSize: 12, color: SageColors.inkSoft),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildGraphCard(List<CheckinEntry> entries) {
    if (entries.isEmpty) {
      return _card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text('No check-ins for this period',
                style: TextStyle(color: SageColors.inkSoft, fontSize: 13)),
          ),
        ),
      );
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wellbeing over time',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: SageColors.ink)),
          const SizedBox(height: 14),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: entries.map((e) {
                final score = e.wellbeingScore;
                final h = (score / 10) * 62 + 6;
                final col = score >= 7
                    ? SageColors.moss
                    : score >= 4.5
                        ? SageColors.amber
                        : SageColors.clay;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message:
                          '${score.toStringAsFixed(1)}/10\nMood ${e.mood} · Stress ${e.stress} · Energy ${e.energy}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: h,
                            decoration: BoxDecoration(
                              color: col.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (entries.length <= 14) ...[
            const SizedBox(height: 4),
            Row(
              children: entries.map((e) {
                return Expanded(
                  child: Text(
                    _dayLabel(e.time),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, color: SageColors.inkSoft),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailedReport(_CheckinReport report) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.assessment_outlined, color: SageColors.amber, size: 17),
            const SizedBox(width: 8),
            Text('${_period.label} Report',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: SageColors.ink)),
          ]),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _reportStat('${report.count}', 'Check-ins'),
              _reportStat(
                  report.avgWellbeing != null
                      ? '${report.avgWellbeing!.toStringAsFixed(1)}/10'
                      : '—',
                  'Avg wellbeing'),
              _reportStat('${report.goodDays}', 'Good days'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _reportStat(
                  report.avgMood != null
                      ? report.avgMood!.toStringAsFixed(1)
                      : '—',
                  'Avg mood'),
              _reportStat(
                  report.avgStress != null
                      ? report.avgStress!.toStringAsFixed(1)
                      : '—',
                  'Avg stress'),
              _reportStat('${report.lowDays}', 'Low days'),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.auto_awesome_outlined,
                size: 15, color: SageColors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                report.narrative,
                style: TextStyle(
                    fontSize: 12.5, color: SageColors.inkSoft, height: 1.5),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _reportStat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: SageText.mono(
                size: 17, weight: FontWeight.w600, color: SageColors.ink)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 10.5, color: SageColors.inkSoft),
            textAlign: TextAlign.center),
      ],
    );
  }

  // ── Result panel (Log tab, right after submit) ────────────────────────────

  Widget _buildResult(CheckinEntry entry) {
    final low = entry.isLow;
    final score = entry.wellbeingScore;
    final recs = _buildRecommendations(entry);
    final week = _weekCheckins;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _scoreRing(score),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          low
                              ? 'Sounds like a tough moment'
                              : score >= 7
                                  ? 'You\'re in a good place today'
                                  : 'Logged — thanks for checking in',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: SageColors.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${score.toStringAsFixed(1)} / 10  ·  '
                          'Mood ${entry.mood} · Stress ${entry.stress} · Energy ${entry.energy}',
                          style: TextStyle(
                              fontSize: 12, color: SageColors.inkSoft),
                        ),
                        if (entry.note != null) ...[
                          const SizedBox(height: 4),
                          Text('"${entry.note}"',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: SageColors.inkSoft,
                                  fontStyle: FontStyle.italic)),
                        ],
                      ]),
                ),
              ]),
              if (week.length >= 2) ...[
                const SizedBox(height: 12),
                _trendNote(week),
              ],
              if (_buildMetricDeltaInsights(entry, week).isNotEmpty) ...[
                const SizedBox(height: 12),
                ..._buildMetricDeltaInsights(entry, week).map((ins) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _trendInsightBanner(ins),
                    )),
              ],
              if (recs.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  low
                      ? 'Things that might help right now'
                      : 'Suggestions for today',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: SageColors.inkSoft),
                ),
                const SizedBox(height: 10),
                ...recs.map((r) => _recTile(r)),
              ],
              const SizedBox(height: 12),
              Row(children: [
                TextButton(
                  onPressed: () => setState(() => _justSaved = null),
                  child: Text('Edit check-in',
                      style:
                          TextStyle(color: SageColors.inkSoft, fontSize: 12.5)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _tabController.animateTo(1),
                  child: Text('View analytics →',
                      style: TextStyle(
                          color: SageColors.amber,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  // ── Helper widgets ────────────────────────────────────────────────────────

  Widget _scoreRing(double score) {
    final color = score >= 7
        ? SageColors.moss
        : score >= 4.5
            ? SageColors.amber
            : SageColors.clay;
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: score / 10,
          strokeWidth: 5,
          backgroundColor: SageColors.line,
          valueColor: AlwaysStoppedAnimation(color),
        ),
        Text(score.toStringAsFixed(1),
            style:
                SageText.mono(size: 13, weight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _recTile(_Recommendation r) {
    return GestureDetector(
      onTap: r.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: r.color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: r.color.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: r.color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(r.icon, size: 16, color: r.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SageColors.ink)),
              Text(r.subtitle,
                  style: TextStyle(fontSize: 12, color: SageColors.inkSoft)),
            ]),
          ),
          Icon(Icons.chevron_right, size: 18, color: r.color),
        ]),
      ),
    );
  }

  Widget _wellbeingPreview() {
    final score = CheckinEntry(
      time: DateTime.now(),
      mood: _mood,
      stress: _stress,
      energy: _energy,
    ).wellbeingScore;
    final color = score >= 7
        ? SageColors.moss
        : score >= 4.5
            ? SageColors.amber
            : SageColors.clay;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Text('Wellbeing score preview',
            style: TextStyle(fontSize: 12.5, color: SageColors.inkSoft)),
        const Spacer(),
        Text('${score.toStringAsFixed(1)} / 10',
            style:
                SageText.mono(size: 14, weight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _slider(
      String label, int value, ValueChanged<int> onChanged, IconData icon,
      {bool invert = false}) {
    final color = invert
        ? (value <= 2
            ? SageColors.moss
            : (value <= 3 ? SageColors.amber : SageColors.clay))
        : (value >= 4
            ? SageColors.moss
            : (value >= 3 ? SageColors.amber : SageColors.clay));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: SageColors.inkSoft),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, color: SageColors.inkSoft)),
        const Spacer(),
        Text('$value/5',
            style:
                SageText.mono(size: 13, weight: FontWeight.w600, color: color)),
      ]),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: color,
          thumbColor: color,
          inactiveTrackColor: SageColors.line,
          overlayColor: color.withValues(alpha: 0.12),
        ),
        child: Slider(
          value: value.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
    ]);
  }

  Widget _moodLabel(int val, bool invert) {
    final labels = invert
        ? ['', 'Very calm', 'Calm', 'Moderate', 'Stressed', 'Very stressed']
        : ['', 'Very low', 'Low', 'Okay', 'Good', 'Great'];
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(labels[val],
          style: TextStyle(fontSize: 11, color: SageColors.inkSoft)),
    );
  }

  Widget _trendNote(List<CheckinEntry> week) {
    final scores = week.map((e) => e.wellbeingScore).toList();
    final recent = scores.last;
    final earlier = scores.first;
    final delta = recent - earlier;
    final trend = delta > 1
        ? 'improving'
        : delta < -1
            ? 'declining'
            : 'stable';
    final color = trend == 'improving'
        ? SageColors.moss
        : trend == 'declining'
            ? SageColors.clay
            : SageColors.inkSoft;
    return Row(children: [
      Icon(
        trend == 'improving'
            ? Icons.trending_up
            : trend == 'declining'
                ? Icons.trending_down
                : Icons.trending_flat,
        size: 15,
        color: color,
      ),
      const SizedBox(width: 6),
      Text(
        'Wellbeing is $trend this week'
        '${trend != 'stable' ? ' (${delta.abs().toStringAsFixed(1)} pts)' : ''}.',
        style: TextStyle(fontSize: 12, color: color),
      ),
    ]);
  }

  Widget _checkinHistoryRow(CheckinEntry e) {
    final score = e.wellbeingScore;
    final color = score >= 7
        ? SageColors.moss
        : score >= 4.5
            ? SageColors.amber
            : SageColors.clay;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(_dayLabel(e.time),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: SageColors.ink)),
                const SizedBox(width: 6),
                Text('${e.time.day}/${e.time.month}',
                    style: TextStyle(fontSize: 11, color: SageColors.inkSoft)),
                const SizedBox(width: 8),
                Text('${score.toStringAsFixed(1)}/10',
                    style: SageText.mono(size: 11.5, color: color)),
              ]),
              const SizedBox(height: 2),
              Text('Mood ${e.mood} · Stress ${e.stress} · Energy ${e.energy}',
                  style: TextStyle(fontSize: 11, color: SageColors.inkSoft)),
              if (e.note != null) ...[
                const SizedBox(height: 2),
                Text('"${e.note}"',
                    style: TextStyle(
                        fontSize: 11,
                        color: SageColors.inkSoft,
                        fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, size: 15, color: SageColors.clay),
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: SageColors.card,
                title: Text('Delete check-in?',
                    style: TextStyle(color: SageColors.ink, fontSize: 15)),
                content: Text('Remove this entry from your history?',
                    style: TextStyle(color: SageColors.inkSoft)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Delete',
                          style: TextStyle(color: SageColors.clay))),
                ],
              ),
            );
            if (confirm == true) {
              await _bella.deleteCheckin(e);
              setState(() {});
            }
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  Widget _trendInsightBanner(_TrendInsight ins) {
    final content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ins.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ins.color.withValues(alpha: 0.22)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ins.icon, size: 15, color: ins.color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(ins.text,
                style: TextStyle(fontSize: 12, color: ins.color, height: 1.4))),
        if (ins.onTap != null) ...[
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 15, color: ins.color),
        ],
      ]),
    );
    if (ins.onTap == null) return content;
    return GestureDetector(onTap: ins.onTap, child: content);
  }

  Widget _contextBanner(_CheckinContext c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.color.withValues(alpha: 0.22)),
      ),
      child: Row(children: [
        Icon(c.icon, size: 16, color: c.color),
        const SizedBox(width: 10),
        Expanded(
            child: Text(c.text,
                style: TextStyle(fontSize: 12.5, color: c.color, height: 1.4))),
      ]),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: SageColors.inkSoft),
    );
  }

  String _dayLabel(DateTime t) {
    const days = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    return days[t.weekday - 1];
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SageColors.card,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        border: Border.all(color: SageColors.line),
      ),
      child: child,
    );
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _CheckinContext {
  final IconData icon;
  final Color color;
  final String text;
  const _CheckinContext(
      {required this.icon, required this.color, required this.text});
}

class _Recommendation {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _Recommendation({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _TrendInsight {
  final IconData icon;
  final Color color;
  final String text;

  /// When set, the banner is tappable and shows a trailing chevron.
  final VoidCallback? onTap;
  const _TrendInsight({
    required this.icon,
    required this.color,
    required this.text,
    this.onTap,
  });
}

class _CheckinReport {
  final int count;
  final double? avgMood;
  final double? avgStress;
  final double? avgEnergy;
  final double? avgWellbeing;
  final int lowDays;
  final int goodDays;
  final String narrative;

  const _CheckinReport({
    required this.count,
    required this.avgMood,
    required this.avgStress,
    required this.avgEnergy,
    required this.avgWellbeing,
    required this.lowDays,
    required this.goodDays,
    required this.narrative,
  });
}