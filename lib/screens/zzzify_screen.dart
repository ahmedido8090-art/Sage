// screens/zzzify_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/bella_service.dart';
import '../services/user_service.dart';
import '../models/bella_data.dart';
import '../widgets/reveal.dart';
import 'sleep_sounds_screen.dart';
import 'breathwork_screen.dart';

/// Which session type to show in graphs/lists.
enum _SleepView { all, night, naps }

/// Time period options for the analytics tab.
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

/// ZZZify — sleep logger + analytics.
/// Log tab   : log/edit night sleep and naps, wind-down checklist.
/// Analytics : period-aware graphs, averages, detailed report,
///             sleep-sounds CTA (glows when sleep quality is low),
///             cross-screen insights, and a factors panel.
class ZZZifyScreen extends StatefulWidget {
  const ZZZifyScreen({super.key, this.initialTabIndex = 0});
  final int initialTabIndex;

  @override
  State<ZZZifyScreen> createState() => _ZZZifyScreenState();
}

class _ZZZifyScreenState extends State<ZZZifyScreen>
    with SingleTickerProviderStateMixin {
  final BellaService _bella = BellaService();

  // ── Log-tab state ──────────────────────────────────────────────────────────
  TimeOfDay? _bedtime;
  TimeOfDay? _wakeTime;
  int _quality = 3;
  final Set<String> _windDownDone = {};
  bool _isNap = false;
  String? _editingId; // non-null → editing an existing entry

  // ── Analytics-tab state ────────────────────────────────────────────────────
  _SleepView _view = _SleepView.all;
  _Period _period = _Period.week;
  bool _showToday = true; // toggle today's bar in graph

  late TabController _tabController;

  static const _windDownItems = [
    'Screens off 30 min before bed',
    'Lights dimmed',
    'Room cool & dark',
    'No caffeine after 2 pm',
    'Tomorrow\'s to-do jotted down',
    'Light stretch or breathing done',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTabIndex);

    // Pre-fill form from last night's values for convenience
    final last = _bella.lastNightSleep;
    if (last != null) {
      if (last.bedtime != null) {
        _bedtime = TimeOfDay.fromDateTime(last.bedtime!);
      }
      if (last.wakeTime != null) {
        _wakeTime = TimeOfDay.fromDateTime(last.wakeTime!);
      }
      _quality = last.quality;
      _windDownDone.addAll(last.windDownDone);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openSleepSounds() => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => const SleepSoundsScreen(embedded: false)));

  // ── Log tab helpers ────────────────────────────────────────────────────────

  Future<void> _pickTime({required bool isBedtime}) async {
    final initial = (isBedtime ? _bedtime : _wakeTime) ?? TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() => isBedtime ? _bedtime = picked : _wakeTime = picked);
  }

  Future<void> _save() async {
    final now = DateTime.now();
    DateTime? bedtimeDt = _bedtime == null
        ? null
        : DateTime(
            now.year, now.month, now.day, _bedtime!.hour, _bedtime!.minute);
    DateTime? wakeDt = _wakeTime == null
        ? null
        : DateTime(
            now.year, now.month, now.day, _wakeTime!.hour, _wakeTime!.minute);

    final entryId = _editingId ??
        '${now.year}-${now.month}-${now.day}T${now.hour}:${now.minute}:${now.second}';

    await _bella.saveSleepEntry(SleepEntry(
      id: entryId,
      date: DateTime(now.year, now.month, now.day),
      bedtime: bedtimeDt,
      wakeTime: wakeDt,
      quality: _quality,
      windDownDone: _windDownDone.toList(),
      isNap: _isNap,
    ));

    if (!mounted) return;

    final savedQuality = _quality; // capture before reset
    final savedIsNap = _isNap;
    final savedWindDown =
        Set<String>.from(_windDownDone); // capture before reset

    setState(() {
      _editingId = null;
      _bedtime = null;
      _wakeTime = null;
      _quality = 3;
      _windDownDone.clear();
      _isNap = false;
    });

    // Show the nudge modal if quality was poor and it was a proper night sleep.
    if (savedQuality <= 3 && !savedIsNap) {
      await _showSleepSoundsNudge(savedQuality);
    } else {
      // For good/okay nights: acknowledge skipped wind-down steps so the
      // checklist feels accountable rather than decorative.
      final skipped = _windDownItems
          .where((item) => !savedWindDown.contains(item))
          .toList();
      final String msg;
      if (savedIsNap) {
        msg = 'Nap logged.';
      } else if (skipped.isEmpty) {
        msg = 'Sleep logged. Full wind-down routine — well done.';
      } else if (skipped.length == 1) {
        msg = 'Sleep logged. You skipped: ${skipped.first.toLowerCase()}.';
      } else {
        msg = 'Sleep logged. ${skipped.length} wind-down steps skipped.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(msg),
            backgroundColor:
                skipped.isEmpty ? SageColors.moss : SageColors.amber),
      );
    }
  }

  /// Analyses food logs relative to the user's actual logged bedtime.
  /// Returns a record with: whether a heavy meal was close to bed,
  /// a human-readable badge label (e.g. "Meal at 10:30 PM — 45 min before bed"),
  /// and the closest offending meal time if any.
  /// Analyses food logs relative to the user's actual logged bedtime.
  /// Returns a record with: whether a heavy meal was close to bed,
  /// and a human-readable badge label (e.g. "Meal at 10:30 PM — 45 min before bed").
  ///
  /// When bedtime is set: checks meals in a 3-hour window before bedtime.
  /// When bedtime is not set: falls back to scanning all meals today for high
  /// calorie content or bad tags (not just evening hours, since a large meal
  /// at any time of day still matters when we don't know the user's bedtime).
  ({bool flagged, String? badgeLabel}) _analyseFoodTiming() {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    if (_bedtime == null) {
      // No bedtime logged — scan all food today (not just after 6 PM).
      final todayFood = _bella.getFoodEntries(onDate: now);
      final totalCals = todayFood.fold<int>(0, (s, f) => s + (f.calories ?? 0));
      final hasBadTag =
          todayFood.any((f) => f.tag == 'high-carb' || f.tag == 'high-sodium');
      final hasHeavySingle = todayFood.any((f) => (f.calories ?? 0) >= 700);
      final flagged = hasBadTag || hasHeavySingle || totalCals > 2000;
      if (!flagged) return (flagged: false, badgeLabel: null);
      final String badge;
      if (hasBadTag) {
        badge = 'High-sodium or high-carb meal logged today';
      } else if (hasHeavySingle) {
        final heaviest = todayFood
            .reduce((a, b) => (a.calories ?? 0) >= (b.calories ?? 0) ? a : b);
        badge =
            'Heavy meal today (${heaviest.calories} kcal) — log your bedtime for precise timing';
      } else {
        badge =
            'High-calorie day ($totalCals kcal) — log your bedtime for precise timing';
      }
      return (flagged: true, badgeLabel: badge);
    }

    // We have a logged bedtime — compare meals against it.
    final allFood = [
      ..._bella.getFoodEntries(onDate: now),
      ..._bella.getFoodEntries(onDate: yesterday),
    ];

    final bedtimeDt = DateTime(
      now.year,
      now.month,
      now.day,
      _bedtime!.hour,
      _bedtime!.minute,
    );

    // Window: meals within 3 hours before bedtime.
    final windowStart = bedtimeDt.subtract(const Duration(hours: 3));
    final nearBedMeals = allFood.where((f) {
      return !f.time.isBefore(windowStart) && !f.time.isAfter(bedtimeDt);
    }).toList()
      ..sort((a, b) => b.time.compareTo(a.time));

    if (nearBedMeals.isEmpty) return (flagged: false, badgeLabel: null);

    final windowCals =
        nearBedMeals.fold<int>(0, (s, f) => s + (f.calories ?? 0));

    // Identify the "representative" meal for the badge:
    // prefer bad-tag meals first, then high-cal, then heaviest in window.
    FoodEntry? badTagMeal;
    FoodEntry? highCalMeal;
    for (final f in nearBedMeals) {
      if (f.tag == 'high-carb' || f.tag == 'high-sodium') badTagMeal ??= f;
      if ((f.calories ?? 0) >= 600) highCalMeal ??= f;
    }

    final flagged =
        badTagMeal != null || highCalMeal != null || windowCals > 800;
    if (!flagged) return (flagged: false, badgeLabel: null);

    final badgeMeal = badTagMeal ??
        highCalMeal ??
        nearBedMeals
            .reduce((a, b) => (a.calories ?? 0) >= (b.calories ?? 0) ? a : b);

    final mealTime = badgeMeal.time;
    final minutesBefore = bedtimeDt.difference(mealTime).inMinutes.abs();
    final timeStr = TimeOfDay.fromDateTime(mealTime).format(
      context, // ignore: use_build_context_synchronously
    );
    final proximityStr = minutesBefore < 60
        ? '$minutesBefore min before bed'
        : '${(minutesBefore / 60).toStringAsFixed(1).replaceAll('.0', '')} h before bed';
    final calNote =
        badgeMeal.calories != null ? ' · ${badgeMeal.calories} kcal' : '';
    final badge = 'Meal at $timeStr — $proximityStr$calNote';

    return (flagged: true, badgeLabel: badge);
  }

  /// Bottom-sheet nudge shown after logging poor/average sleep quality.
  /// Combines food-timing, check-in stress/mood, and chronic-care readings
  /// into a single prioritised message. If multiple signals are bad, it
  /// says so explicitly — e.g. "Three things worked against your sleep".
  Future<void> _showSleepSoundsNudge(int quality) async {
    if (!mounted) return;

    // ── Signal 1: food close to bedtime ──────────────────────────────────────
    final foodAnalysis = _analyseFoodTiming();
    final hasFoodSignal = foodAnalysis.flagged;

    // ── Signal 2: check-in (stress, mood, OR energy) — today only ────────────
    final checkin = _bella.lastCheckin;
    final today = DateTime.now();
    final checkinIsToday = checkin != null &&
        checkin.time.year == today.year &&
        checkin.time.month == today.month &&
        checkin.time.day == today.day;
    // Also accept yesterday's check-in if it's late at night (before midnight)
    // and the user logged sleep for "last night" — keeps the signal meaningful.
    final checkinIsYesterday = checkin != null &&
        !checkinIsToday &&
        today.difference(checkin.time).inHours <= 20;
    final checkinRecent = checkinIsToday || checkinIsYesterday;
    final hasCheckinSignal = checkinRecent &&
        (checkin.stress >= 4 || checkin.mood <= 2 || checkin.energy <= 2);

    // Human-readable label for what triggered the check-in signal
    // (used in composite bodies so we don't hardcode "stress").
    String checkinLabel() {
      if (!hasCheckinSignal) return 'poor wellbeing';
      final parts = <String>[];
      if (checkin.stress >= 4) parts.add('high stress');
      if (checkin.mood <= 2) parts.add('low mood');
      if (checkin.energy <= 2) parts.add('low energy');
      return parts.join(' & ');
    }

    String checkinLabelCap() {
      final s = checkinLabel();
      return s.isEmpty ? 'Poor wellbeing' : s[0].toUpperCase() + s.substring(1);
    }

    // ── Signal 3: chronic-care readings out of range (all 8 conditions) ───────
    // Collect EVERY flagged condition — multiple out-of-range readings all
    // matter and should all be mentioned in the nudge, not just the first one.
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];
    final flaggedConditions = <String>[];
    for (final cond in conditions) {
      final readings = _bella.getReadings(condition: cond);
      if (readings.isEmpty) continue;
      final r = readings.first;
      // Only flag readings that are recent (within 7 days) to avoid stale data.
      final readingAge = today.difference(r.time).inDays;
      if (readingAge > 7) continue;
      final outOfRange = switch (cond) {
        'Diabetes' => r.value < 70 || r.value > 180,
        'Hypertension' => r.value >= 140 || (r.secondaryValue ?? 0) >= 90,
        'Heart Disease' => r.value >= 140 || (r.secondaryValue ?? 0) >= 90,
        'Asthma' => r.value < 80, // peak flow % predicted
        'Chronic Kidney Disease' =>
          r.value > 1.2, // creatinine mg/dL rough threshold
        'High Cholesterol' => r.value > 200, // total cholesterol mg/dL
        'Arthritis' => false, // no standard numeric flag for pain scores
        'Thyroid Disorder' => false, // TSH varies by lab; don't auto-flag
        _ => false,
      };
      if (outOfRange) flaggedConditions.add(cond);
    }
    final hasChronicSignal = flaggedConditions.isNotEmpty;
    // Human-readable: "Diabetes & Hypertension" or just "Diabetes"
    final chronicDetail = flaggedConditions.join(' & ');

    // ── Count active signals ──────────────────────────────────────────────────
    final activeSignals = [hasFoodSignal, hasCheckinSignal, hasChronicSignal]
        .where((s) => s)
        .length;

    // ── Build headline & body based on signal count ───────────────────────────
    final headline = quality <= 2
        ? 'That sounds like a rough night.'
        : 'Sleep could be better.';
    // Specific food description for composite messages
    final foodDesc = foodAnalysis.badgeLabel ?? 'a heavy meal close to bedtime';
    final String body;

    if (activeSignals == 3) {
      body = 'Three things worked against your sleep: ${checkinLabel()}, '
          '$foodDesc, and an out-of-range $chronicDetail reading. '
          'Each disrupts rest on its own — together they make recovery harder. '
          'Sleep sounds can help your nervous system wind down tonight.';
    } else if (activeSignals == 2) {
      if (hasCheckinSignal && hasChronicSignal) {
        body =
            '${checkinLabelCap()} and an out-of-range $chronicDetail reading '
            'both affect sleep quality tonight. Cortisol and uncontrolled $chronicDetail are a tough combination — '
            'a calming sleep sounds session can help take the edge off.';
      } else if (hasFoodSignal && hasChronicSignal) {
        body =
            '$foodDesc and an out-of-range $chronicDetail reading are both working against you tonight. '
            'Your body is already managing $chronicDetail — digestion on top of that steals energy from recovery. '
            'Try sleep sounds to ease the transition.';
      } else {
        // hasFoodSignal && hasCheckinSignal
        body = '${checkinLabelCap()} and $foodDesc are '
            'both affecting your rest tonight. Elevated stress keeps you wired while digestion keeps your body busy — '
            'not a great combo. Sleep sounds can help settle both.';
      }
    } else if (hasCheckinSignal) {
      body =
          '${checkinLabelCap()} today can raise cortisol and delay sleep onset. '
          'A few minutes of sleep sounds can help your nervous system settle before bed.';
    } else if (hasChronicSignal) {
      body =
          'Your recent $chronicDetail reading was out of range, which can directly affect sleep depth and continuity. '
          'A calm wind-down routine — starting with sleep sounds — may help your body shift into rest mode.';
    } else if (hasFoodSignal) {
      body =
          '$foodDesc. A heavy meal close to bedtime keeps your body busy digesting instead of resting, '
          'which can fragment deep sleep. Tonight, try winding down with some sleep sounds.';
    } else {
      body =
          'Why not set the scene for better rest tonight? A few minutes of sleep sounds can help your body shift into sleep mode.';
    }
    await showModalBottomSheet(
      context: context,
      backgroundColor: SageColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        return ConstrainedBox(
          // Never taller than 90% of the screen — if content is shorter it
          // shrinks to fit; if longer it scrolls. isScrollControlled: true
          // above lifts the default 50% cap so this constraint takes over.
          constraints: BoxConstraints(
            maxHeight: mq.size.height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + mq.viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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

                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: SageColors.moss.withValues(alpha: 0.1),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Icon(Icons.nights_stay_outlined,
                        color: SageColors.moss, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      headline,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: SageColors.ink,
                      ),
                    ),
                  ),
                ]),

                const SizedBox(height: 14),

                // Signal badges — shown when at least one signal is active.
                // Each badge is its own pill so multiple can stack.
                if (hasFoodSignal) ...[
                  _NudgeBadge(
                    icon: Icons.restaurant_outlined,
                    color: SageColors.amber,
                    label: foodAnalysis.badgeLabel ?? 'Heavy meal near bedtime',
                  ),
                  const SizedBox(height: 6),
                ],
                if (hasCheckinSignal) ...[
                  _NudgeBadge(
                    icon: Icons.bolt,
                    color: SageColors.clay,
                    label: () {
                      final parts = <String>[];
                      if (checkin.stress >= 4) parts.add('High stress');
                      if (checkin.mood <= 2) parts.add('Low mood');
                      if (checkin.energy <= 2) parts.add('Low energy');
                      return '${parts.join(' · ')} logged today';
                    }(),
                  ),
                  const SizedBox(height: 6),
                ],
                // One badge per flagged condition so each is named explicitly.
                for (final flaggedCond in flaggedConditions) ...[
                  _NudgeBadge(
                    icon: Icons.monitor_heart_outlined,
                    color: SageColors.clay,
                    label: '$flaggedCond reading out of range',
                  ),
                  const SizedBox(height: 6),
                ],
                if (activeSignals > 0) const SizedBox(height: 6),

                Text(
                  body,
                  style: TextStyle(
                      fontSize: 13.5, color: SageColors.inkSoft, height: 1.55),
                ),

                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.music_note_outlined, size: 18),
                    label: const Text('Try sleep sounds tonight'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SageColors.moss,
                      foregroundColor: SageColors.linen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(14),
                          bottomLeft: Radius.circular(14),
                          bottomRight: Radius.circular(14),
                        ),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const SleepSoundsScreen(embedded: false)),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),

                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Maybe later',
                      style: TextStyle(color: SageColors.inkSoft, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _loadEntryForEdit(SleepEntry e) {
    setState(() {
      _editingId = e.id;
      _bedtime = e.bedtime != null ? TimeOfDay.fromDateTime(e.bedtime!) : null;
      _wakeTime =
          e.wakeTime != null ? TimeOfDay.fromDateTime(e.wakeTime!) : null;
      _quality = e.quality;
      _windDownDone
        ..clear()
        ..addAll(e.windDownDone);
      _isNap = e.isNap;
    });
    _tabController.animateTo(0);
  }

  Future<void> _deleteEntry(SleepEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SageColors.card,
        title: Text('Delete entry?',
            style: TextStyle(color: SageColors.ink, fontSize: 15)),
        content: Text('Remove this sleep session?',
            style: TextStyle(color: SageColors.inkSoft)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete', style: TextStyle(color: SageColors.clay))),
        ],
      ),
    );
    if (confirm == true) {
      await _bella.deleteSleepEntry(entry);
      if (mounted) {
        setState(() {
          if (_editingId == entry.id) {
            _editingId = null;
            _bedtime = null;
            _wakeTime = null;
            _quality = 3;
            _windDownDone.clear();
            _isNap = false;
          }
        });
      }
    }
  }

  // ── Smart sleep score ──────────────────────────────────────────────────────

  double? _smartSleepScore(List<SleepEntry> periodEntries) {
    final nights = periodEntries.where((e) => !e.isNap).toList();
    if (nights.isEmpty) return null;
    final nightAvg =
        nights.map((e) => e.quality).reduce((a, b) => a + b) / nights.length;
    final naps = periodEntries.where((e) => e.isNap).toList();
    if (naps.isEmpty) return nightAvg;

    final avgNapMin = naps
            .map((e) => e.duration?.inMinutes ?? 0)
            .fold<int>(0, (a, b) => a + b) /
        naps.length;
    final napsPerNight = naps.length / nights.length;

    double adj = 0;
    if (avgNapMin > 0 && avgNapMin <= 30) {
      adj += 0.2;
    } else if (avgNapMin > 90)
      adj -= 0.4;
    else if (avgNapMin > 30) adj -= 0.15;
    if (napsPerNight > 1.5) adj -= 0.2;

    return (nightAvg + adj).clamp(0.0, 5.0);
  }

  // ── Cross-screen insights ──────────────────────────────────────────────────

  List<_SleepInsight> _buildTodayInsights(List<SleepEntry> todaySessions) {
    final insights = <_SleepInsight>[];
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];
    final totalMin =
        todaySessions.fold<int>(0, (s, e) => s + (e.duration?.inMinutes ?? 0));
    final totalHours = totalMin / 60.0;

    if (todaySessions.isNotEmpty) {
      if (totalHours < 6) {
        insights.add(_SleepInsight(
          icon: Icons.battery_0_bar,
          color: SageColors.clay,
          text: 'Only ${_hm(totalMin)} of sleep logged today — '
              'well below the 7–9 h adults need. Sleep deprivation raises '
              'cortisol and impairs glucose regulation.',
        ));
      } else if (totalHours >= 7 && totalHours <= 9) {
        insights.add(_SleepInsight(
          icon: Icons.check_circle_outline,
          color: SageColors.moss,
          text: '${_hm(totalMin)} total today — right in the 7–9 h sweet spot. '
              'Keep it consistent for best results.',
        ));
      } else if (totalHours > 9) {
        insights.add(_SleepInsight(
          icon: Icons.info_outline,
          color: SageColors.amber,
          text: '${_hm(totalMin)} logged — sleeping over 9 h regularly can '
              'indicate poor sleep quality. Worth mentioning to your doctor.',
        ));
      }
    }

    // Nap commentary
    final naps = todaySessions.where((e) => e.isNap).toList();
    final nights = todaySessions.where((e) => !e.isNap).toList();
    if (naps.isNotEmpty && nights.isNotEmpty) {
      final napMin =
          naps.fold<int>(0, (s, e) => s + (e.duration?.inMinutes ?? 0));
      if (napMin > 90) {
        insights.add(_SleepInsight(
          icon: Icons.wb_sunny_outlined,
          color: SageColors.clay,
          text: 'Your nap today was ${_hm(napMin)} — over 90 min can '
              'reduce sleep pressure tonight. '
              '${conditions.any((c) => [
                    'Diabetes',
                    'Heart Disease',
                    'Hypertension'
                  ].contains(c)) ? "Chronic-condition management benefits from stable overnight sleep." : ""}',
        ));
      } else if (napMin <= 30) {
        insights.add(_SleepInsight(
          icon: Icons.wb_sunny_outlined,
          color: SageColors.moss,
          text: 'A short ${_hm(napMin)} nap is well-timed — improves afternoon '
              'alertness without stealing from tonight.',
        ));
      }
    }

    // Food cross-links — calorie-aware and timing-aware.
    final foodToday = _bella.getFoodEntries(onDate: DateTime.now());
    if (foodToday.any((f) => f.tag == 'high-sodium')) {
      insights.add(_SleepInsight(
        icon: Icons.water_drop_outlined,
        color: SageColors.clay,
        text: 'High-sodium meal logged today — salt raises blood pressure and '
            'can disrupt deep sleep.',
      ));
    }
    if (foodToday.any((f) => f.tag == 'high-carb')) {
      insights.add(_SleepInsight(
        icon: Icons.bakery_dining_outlined,
        color: SageColors.amber,
        text: 'A high-carb meal close to bed can cause blood sugar swings '
            'that fragment sleep.',
      ));
    }

    // Flag high-calorie meals even when the tag is 'balanced' or absent.
    // If we have a bedtime, check proximity; otherwise check evening hours.
    if (_bedtime != null) {
      final bedtimeDt = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        _bedtime!.hour,
        _bedtime!.minute,
      );
      final windowStart = bedtimeDt.subtract(const Duration(hours: 3));
      final nearBedMeals = foodToday
          .where((f) =>
              !f.time.isBefore(windowStart) && !f.time.isAfter(bedtimeDt))
          .toList();
      final windowCals =
          nearBedMeals.fold<int>(0, (s, f) => s + (f.calories ?? 0));
      final singleHighCal = nearBedMeals.any((f) => (f.calories ?? 0) >= 600);
      if ((singleHighCal || windowCals > 800) &&
          !foodToday
              .any((f) => f.tag == 'high-carb' || f.tag == 'high-sodium')) {
        insights.add(_SleepInsight(
          icon: Icons.local_fire_department_outlined,
          color: SageColors.amber,
          text: 'Heavy meal logged within 3 hours of your bedtime '
              '(${windowCals > 0 ? "$windowCals kcal" : "high calorie"}) — '
              'digestion can raise core body temperature and reduce deep sleep.',
        ));
      }
    } else {
      // Fallback: no bedtime logged — scan all meals today (not just after 6 PM).
      // A 20,000 kcal meal at 3 PM is still relevant if we don't know bedtime.
      final totalCalsToday =
          foodToday.fold<int>(0, (s, f) => s + (f.calories ?? 0));
      final hasHeavySingle = foodToday.any((f) => (f.calories ?? 0) >= 700);
      if ((hasHeavySingle || totalCalsToday > 2000) &&
          !foodToday
              .any((f) => f.tag == 'high-carb' || f.tag == 'high-sodium')) {
        final heaviest = foodToday.isEmpty
            ? null
            : foodToday.reduce(
                (a, b) => (a.calories ?? 0) >= (b.calories ?? 0) ? a : b);
        insights.add(_SleepInsight(
          icon: Icons.local_fire_department_outlined,
          color: SageColors.amber,
          text: 'High-calorie intake logged today '
              '(${heaviest?.calories != null ? "${heaviest!.calories} kcal single meal" : "$totalCalsToday kcal total"}) — '
              'log your bedtime for timing-aware advice.',
        ));
      }
    }

    // Check-in cross-link: stress, mood, and energy — today's entry only.
    final checkin = _bella.lastCheckin;
    final checkinToday = checkin != null &&
        checkin.time.year == DateTime.now().year &&
        checkin.time.month == DateTime.now().month &&
        checkin.time.day == DateTime.now().day;
    if (checkinToday) {
      if (checkin.stress >= 4) {
        insights.add(_SleepInsight(
          icon: Icons.bolt,
          color: SageColors.amber,
          text: 'High stress today — cortisol delays sleep onset. '
              'Try a short breathwork session before bed.',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const BreathworkScreen(
                    initialHeartRate: 72, autoStart: true)),
          ),
        ));
      }
      if (checkin.mood <= 2) {
        insights.add(_SleepInsight(
          icon: Icons.sentiment_very_dissatisfied_outlined,
          color: SageColors.clay,
          text:
              'Low mood logged today — emotional state affects sleep architecture. '
              'A wind-down routine can help ease the transition to rest.',
        ));
      }
      if (checkin.energy <= 2) {
        insights.add(_SleepInsight(
          icon: Icons.battery_1_bar,
          color: SageColors.amber,
          text:
              'Low energy logged today — may indicate accumulated sleep debt. '
              'Prioritise an earlier bedtime tonight.',
        ));
      }
    }

    // Condition-specific
    if (conditions.contains('Heart Disease') ||
        conditions.contains('Hypertension')) {
      insights.add(_SleepInsight(
        icon: Icons.monitor_heart_outlined,
        color: SageColors.moss,
        text:
            'Consistent sleep timing is especially important for cardiovascular health.',
      ));
    }
    if (conditions.contains('Diabetes')) {
      insights.add(_SleepInsight(
        icon: Icons.science_outlined,
        color: SageColors.amber,
        text: '7–8 h of consistent sleep helps stabilise insulin sensitivity.',
      ));
    }

    // ── Activity session insights ─────────────────────────────────────────
    final walkingMin = _bella.sessionMinutesToday('walking');
    final meditationMin = _bella.sessionMinutesToday('meditation');
    final breathworkMin = _bella.sessionMinutesToday('breathwork');
    final now = DateTime.now();

    if (walkingMin >= 20) {
      final walkSessions = _bella.getSessions(type: 'walking');
      final lastWalk = walkSessions.isNotEmpty ? walkSessions.first : null;
      if (lastWalk != null &&
          now.hour >= 20 &&
          now.difference(lastWalk.date).inMinutes < 120) {
        insights.add(_SleepInsight(
          icon: Icons.directions_walk_outlined,
          color: SageColors.amber,
          text:
              'Your walk was less than 2 hours ago — vigorous exercise near bedtime '
              'can raise core body temperature and delay sleep onset. '
              'A wind-down routine will help.',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SleepSoundsScreen(embedded: false))),
        ));
      } else if (walkingMin >= 20) {
        insights.add(_SleepInsight(
          icon: Icons.directions_walk_outlined,
          color: SageColors.moss,
          text: 'You walked $walkingMin min today — regular daytime activity '
              'deepens sleep and helps you fall asleep faster.',
        ));
      }
    }

    if (meditationMin >= 5 || breathworkMin >= 5) {
      insights.add(_SleepInsight(
        icon: Icons.self_improvement_outlined,
        color: SageColors.moss,
        text: '${meditationMin + breathworkMin} min of mind practice today — '
            'this lowers cortisol and prepares your nervous system for deep sleep.',
      ));
    }

    // Sleep sounds used today = positive wind-down signal
    final sleepSoundsMin = _bella.sessionMinutesToday('sleep_sounds');
    if (sleepSoundsMin >= 10) {
      insights.add(_SleepInsight(
        icon: Icons.music_note_outlined,
        color: SageColors.moss,
        text: 'You used sleep sounds for $sleepSoundsMin min today — '
            'a consistent wind-down audio routine deepens sleep onset and improves continuity.',
      ));
    }

    if (walkingMin == 0 &&
        meditationMin == 0 &&
        breathworkMin == 0 &&
        now.hour >= 16) {
      insights.add(_SleepInsight(
        icon: Icons.directions_walk_outlined,
        color: SageColors.inkSoft,
        text: 'No activity logged today — even a 15-minute evening walk '
            'can meaningfully improve sleep quality tonight.',
      ));
    }

    // ── Water / hydration insight ─────────────────────────────────────────
    // Dehydration causes leg cramps, restless sleep, and nighttime waking.
    // Only surface this in the afternoon / evening when there's still time
    // to act on it — a morning nudge here would feel off-context.
    final waterMl = _bella.todayWaterMl();
    if (now.hour >= 15 && waterMl < 1200) {
      final waterStr = waterMl > 0
          ? '${(waterMl / 1000).toStringAsFixed(1)}L logged'
          : 'none logged';
      insights.add(_SleepInsight(
        icon: Icons.water_drop_outlined,
        color: SageColors.clay,
        text: 'Low hydration today ($waterStr) — dehydration causes '
            'leg cramps and restless sleep. Drink a glass of water '
            'before bed to help your body rest.',
      ));
    } else if (now.hour >= 15 && waterMl >= 1200 && waterMl < 1800) {
      insights.add(_SleepInsight(
        icon: Icons.water_drop_outlined,
        color: SageColors.amber,
        text: 'Hydration is a little low today '
            '(${(waterMl / 1000).toStringAsFixed(1)}L) — a small glass '
            'before bed can prevent nighttime cramps.',
      ));
    }

    return insights;
  }

  List<_SleepFactor> _buildFactors() {
    final factors = <_SleepFactor>[];
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final today = DateTime.now();
    final foodYest = _bella.getFoodEntries(onDate: yesterday);
    final foodToday = _bella.getFoodEntries(onDate: today);
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];

    // ── Yesterday's food factors ──────────────────────────────────────────────
    if (foodYest.any((f) => f.tag == 'high-sodium')) {
      factors.add(_SleepFactor(
        icon: Icons.water_drop_outlined,
        color: SageColors.clay,
        label: 'High-sodium meal yesterday',
        detail: 'Salt raises blood pressure and can disrupt deep sleep.',
      ));
    }
    if (foodYest.any((f) => f.tag == 'high-carb')) {
      factors.add(_SleepFactor(
        icon: Icons.bakery_dining_outlined,
        color: SageColors.amber,
        label: 'High-carb meal yesterday',
        detail:
            'Large carb loads can cause blood sugar swings that fragment sleep.',
      ));
    }

    // Heavy calorie day yesterday — catches 'balanced'-tagged but huge meals.
    final calYest = foodYest.fold<int>(0, (s, f) => s + (f.calories ?? 0));
    if (calYest > 2400) {
      factors.add(_SleepFactor(
        icon: Icons.local_fire_department_outlined,
        color: SageColors.clay,
        label: 'Heavy calorie day yesterday ($calYest kcal)',
        detail:
            'Overeating can cause discomfort and raised body temp at night.',
      ));
    }

    // ── Today's meal timing against logged bedtime ────────────────────────────
    if (_bedtime != null) {
      final bedtimeDt = DateTime(
        today.year,
        today.month,
        today.day,
        _bedtime!.hour,
        _bedtime!.minute,
      );
      final windowStart = bedtimeDt.subtract(const Duration(hours: 3));
      final nearBedMeals = foodToday
          .where((f) =>
              !f.time.isBefore(windowStart) && !f.time.isAfter(bedtimeDt))
          .toList();
      final windowCals =
          nearBedMeals.fold<int>(0, (s, f) => s + (f.calories ?? 0));
      final singleHighCal = nearBedMeals.any((f) => (f.calories ?? 0) >= 600);
      if (singleHighCal || windowCals > 800) {
        final timeStr = _bedtime!.format(context);
        factors.add(_SleepFactor(
          icon: Icons.restaurant_outlined,
          color: SageColors.amber,
          label: 'Heavy meal within 3 h of bedtime ($timeStr)',
          detail: windowCals > 0
              ? '$windowCals kcal consumed close to bed — digestion competes with deep sleep.'
              : 'A high-calorie meal near bedtime can raise core body temperature and fragment rest.',
        ));
      }
    } else {
      // No bedtime logged — scan all food today (not just after 6 PM).
      final totalCalsToday =
          foodToday.fold<int>(0, (s, f) => s + (f.calories ?? 0));
      final hasHeavySingle = foodToday.any((f) => (f.calories ?? 0) >= 700);
      if (totalCalsToday > 2000 || hasHeavySingle) {
        factors.add(_SleepFactor(
          icon: Icons.restaurant_outlined,
          color: SageColors.amber,
          label: 'High-calorie intake today ($totalCalsToday kcal)',
          detail:
              'Log your bedtime to see whether any meals fall too close to sleep.',
        ));
      }
    }

    for (final cond in conditions) {
      final readings = _bella.getReadings(condition: cond);
      if (readings.isNotEmpty) {
        final r = readings.first;
        // Only flag readings within the last 7 days to avoid stale data.
        final readingAge = today.difference(r.time).inDays;
        if (readingAge > 7) continue;
        final flagged = switch (cond) {
          'Diabetes' => r.value < 70 || r.value > 180,
          'Hypertension' => r.value >= 140 || (r.secondaryValue ?? 0) >= 90,
          'Heart Disease' => r.value >= 140 || (r.secondaryValue ?? 0) >= 90,
          'Asthma' => r.value < 80,
          'Chronic Kidney Disease' => r.value > 1.2,
          'High Cholesterol' => r.value > 200,
          _ => false,
        };
        if (flagged) {
          factors.add(_SleepFactor(
            icon: Icons.monitor_heart_outlined,
            color: SageColors.clay,
            label: 'Recent $cond reading out of range',
            detail: 'Uncontrolled $cond can directly impact sleep quality.',
          ));
        }
      }
    }

    final checkin = _bella.lastCheckin;
    // Only use check-in data if it's from today or yesterday (not stale).
    final checkinAge =
        checkin != null ? today.difference(checkin.time).inHours : 999;
    final checkinFresh = checkinAge <= 20;
    if (checkin != null && checkinFresh) {
      if (checkin.stress >= 4) {
        factors.add(_SleepFactor(
          icon: Icons.bolt,
          color: SageColors.amber,
          label: 'High stress today',
          detail:
              'Elevated cortisol delays sleep onset and reduces deep sleep.',
        ));
      }
      if (checkin.mood <= 2) {
        factors.add(_SleepFactor(
          icon: Icons.sentiment_very_dissatisfied_outlined,
          color: SageColors.clay,
          label: 'Low mood today',
          detail:
              'Emotional state affects how quickly and deeply you fall asleep.',
        ));
      }
      if (checkin.energy <= 2) {
        factors.add(_SleepFactor(
          icon: Icons.battery_0_bar,
          color: SageColors.moss,
          label: 'Low energy today',
          detail:
              'May indicate sleep debt — an earlier bedtime tonight may help.',
        ));
      }
    }

    // ── Activity session factors ───────────────────────────────────────────
    // Exercise timing and intensity directly affect sleep quality and onset.
    final walkingMinToday = _bella.sessionMinutesToday('walking');
    final meditationMinToday = _bella.sessionMinutesToday('meditation');
    final breathworkMinToday = _bella.sessionMinutesToday('breathwork');

    if (walkingMinToday >= 20) {
      // Check if the walk was recent (within 2 hours of now — potential
      // stimulant effect on sleep onset if close to bedtime).
      final walkSessions = _bella.getSessions(type: 'walking');
      final lastWalk = walkSessions.isNotEmpty ? walkSessions.first : null;
      if (lastWalk != null) {
        final hoursSinceWalk = today.difference(lastWalk.date).inMinutes / 60;
        final isEvening = today.hour >= 20;
        if (isEvening && hoursSinceWalk < 2) {
          factors.add(_SleepFactor(
            icon: Icons.directions_walk_outlined,
            color: SageColors.amber,
            label: 'Walk completed within 2 h of bedtime',
            detail:
                'Vigorous exercise too close to sleep can raise core temperature and delay onset. A gentle wind-down helps.',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SleepSoundsScreen(embedded: false))),
          ));
        } else {
          factors.add(_SleepFactor(
            icon: Icons.directions_walk_outlined,
            color: SageColors.moss,
            label: 'Walking session logged today ($walkingMinToday min)',
            detail:
                'Regular daytime exercise deepens sleep and reduces time to fall asleep.',
          ));
        }
      }
    }

    if (meditationMinToday >= 5 || breathworkMinToday >= 5) {
      final totalMindMin = meditationMinToday + breathworkMinToday;
      factors.add(_SleepFactor(
        icon: Icons.self_improvement_outlined,
        color: SageColors.moss,
        label: 'Mind practice today ($totalMindMin min)',
        detail:
            'Meditation and breathwork lower cortisol and prepare the nervous system for deep sleep.',
      ));
    }

    return factors;
  }

  // ── Period report builder ──────────────────────────────────────────────────

  _PeriodReport _buildReport(List<SleepEntry> entries) {
    final nights = entries.where((e) => !e.isNap).toList();
    final naps = entries.where((e) => e.isNap).toList();

    // Night averages
    final avgNightQ = nights.isEmpty
        ? null
        : nights.map((e) => e.quality).reduce((a, b) => a + b) / nights.length;
    final avgNightMin = nights.isEmpty
        ? null
        : nights
                .map((e) => e.duration?.inMinutes ?? 0)
                .fold<int>(0, (a, b) => a + b) /
            nights.length;

    // Days with good sleep (≥ 7 h night + quality ≥ 3)
    final goodDays = nights.where((e) {
      final dur = e.duration?.inHours ?? 0;
      return dur >= 7 && e.quality >= 3;
    }).length;

    // Avg wind-down steps
    final avgWD = nights.isEmpty
        ? null
        : nights
                .map((e) => e.windDownDone.length)
                .fold<int>(0, (a, b) => a + b) /
            nights.length;

    // Score
    final score = _smartSleepScore(entries);

    // Narrative
    String narrative;
    if (nights.isEmpty) {
      narrative = 'No night-sleep sessions logged in this period.';
    } else {
      final dq = avgNightQ!;
      final dm = avgNightMin!;
      if (dq >= 4 && dm >= 7 * 60) {
        narrative = 'Excellent period — your sleep quality and duration are '
            'both in a healthy range. Keep your current routine going.';
      } else if (dq >= 3 && dm >= 6 * 60) {
        narrative = 'Decent sleep period with room to improve. Aim to push '
            'duration above 7 h and complete more wind-down steps to lift '
            'quality further.';
      } else if (dm < 6 * 60) {
        narrative = 'Duration is the main concern this period — you\'re '
            'consistently under 6 h. Prioritise an earlier bedtime and try '
            'to reduce screen time before sleep.';
      } else {
        narrative = 'Quality is pulling the score down this period. '
            'Wind-down steps, consistent timing, and limiting high-sodium or '
            'high-carb meals near bedtime all tend to help.';
      }
      if (naps.isNotEmpty) {
        final avgNapMin = naps
                .map((e) => e.duration?.inMinutes ?? 0)
                .fold<int>(0, (a, b) => a + b) /
            naps.length;
        if (avgNapMin > 90) {
          narrative +=
              ' Long naps (avg ${_hm(avgNapMin.round())}) this period suggest '
              'accumulated night-sleep debt — addressing night duration should '
              'reduce daytime drowsiness.';
        }
      }
    }

    return _PeriodReport(
      nights: nights.length,
      naps: naps.length,
      avgNightQuality: avgNightQ,
      avgNightDurationMin: avgNightMin,
      goodDaysCount: goodDays,
      avgWindDown: avgWD,
      score: score,
      narrative: narrative,
    );
  }

  // ── Helper formatters ──────────────────────────────────────────────────────

  String _fmt(TimeOfDay? t) => t == null ? '—' : t.format(context);

  String _dateLabel(DateTime d) {
    final today = DateTime.now();
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yest.';
    return '${d.day}/${d.month}';
  }

  Duration? _duration(SleepEntry e) {
    if (e.bedtime == null || e.wakeTime == null) return null;
    var d = e.wakeTime!.difference(e.bedtime!);
    if (d.isNegative) d += const Duration(hours: 24);
    return d;
  }

  String _durationLabel(Duration? d) {
    if (d == null) return '—';
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  String _hm(int totalMin) => '${totalMin ~/ 60}h ${totalMin % 60}m';

  Duration? _formDuration() {
    if (_bedtime == null || _wakeTime == null) return null;
    final now = DateTime.now();
    var d = DateTime(
            now.year, now.month, now.day, _wakeTime!.hour, _wakeTime!.minute)
        .difference(DateTime(
            now.year, now.month, now.day, _bedtime!.hour, _bedtime!.minute));
    if (d.isNegative) d += const Duration(hours: 24);
    return d;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // --- Data for analytics tab ---
    final today = DateTime.now();
    final cutoff = today.subtract(Duration(days: _period.days));

    // All entries in the selected period
    final periodEntries = _bella
        .getSleepEntries()
        .where((e) =>
            e.date.isAfter(cutoff) ||
            (e.date.year == cutoff.year &&
                e.date.month == cutoff.month &&
                e.date.day == cutoff.day))
        .toList();

    // Graph entries: optionally hide today
    final graphEntries = _showToday
        ? periodEntries
        : periodEntries
            .where((e) => !(e.date.year == today.year &&
                e.date.month == today.month &&
                e.date.day == today.day))
            .toList();

    // Filter by type (all/night/naps)
    final filteredGraph = _view == _SleepView.all
        ? graphEntries
        : graphEntries
            .where((e) => _view == _SleepView.naps ? e.isNap : !e.isNap)
            .toList();

    final todaySessions = _bella.getSleepEntriesForDate(today);
    final factors = _buildFactors();
    final todayInsights = _buildTodayInsights(todaySessions);
    final totalTodayMin =
        todaySessions.fold<int>(0, (s, e) => s + (e.duration?.inMinutes ?? 0));

    final report = _buildReport(periodEntries);
    final score = report.score;

    // Wind-down insight
    final allEntries = _bella.getSleepEntries().take(30).toList();
    final goodNights =
        allEntries.where((e) => e.quality >= 4 && !e.isNap).toList();
    final badNights =
        allEntries.where((e) => e.quality <= 2 && !e.isNap).toList();
    final avgWDGood = goodNights.isEmpty
        ? 0.0
        : goodNights
                .map((e) => e.windDownDone.length)
                .fold<int>(0, (a, b) => a + b) /
            goodNights.length;
    final avgWDBad = badNights.isEmpty
        ? 0.0
        : badNights
                .map((e) => e.windDownDone.length)
                .fold<int>(0, (a, b) => a + b) /
            badNights.length;
    final showWindDownInsight = goodNights.isNotEmpty &&
        badNights.isNotEmpty &&
        avgWDGood > avgWDBad + 0.5;

    return Scaffold(
      backgroundColor: SageColors.linen,
      appBar: AppBar(
        backgroundColor: SageColors.linen,
        title: Text('ZZZify', style: SageText.headline(color: SageColors.ink)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: SageColors.moss,
          labelColor: SageColors.moss,
          unselectedLabelColor: SageColors.inkSoft,
          tabs: const [
            Tab(text: 'Log Sleep'),
            Tab(text: 'Analytics'),
          ],
        ),
      ),
      body: Reveal(size: RevealSize.large,
        child: TabBarView(
        controller: _tabController,
        children: [
          // ════════════════════════════════════════════════════════════════
          // TAB 1 — LOG SLEEP
          // ════════════════════════════════════════════════════════════════
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _card(child: _buildLogForm()),
              ],
            ),
          ),

          // ════════════════════════════════════════════════════════════════
          // TAB 2 — ANALYTICS
          // ════════════════════════════════════════════════════════════════
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Period picker ─────────────────────────────────────────
                _buildPeriodRow(),
                const SizedBox(height: 16),

                // ── Sleep score summary ───────────────────────────────────
                _buildScoreCard(score, report),
                const SizedBox(height: 16),

                // ── Graph section ─────────────────────────────────────────
                _buildGraphSection(filteredGraph, graphEntries),
                const SizedBox(height: 16),

                // ── Entry list ────────────────────────────────────────────
                if (periodEntries.isNotEmpty) _buildEntryList(periodEntries),
                const SizedBox(height: 16),

                // ── Today's session insights ──────────────────────────────
                if (todaySessions.isNotEmpty)
                  _buildTodayInsightCard(
                      todaySessions, todayInsights, totalTodayMin),

                // ── Detailed report ───────────────────────────────────────
                const SizedBox(height: 16),
                _buildDetailedReport(report),

                // ── Factors affecting tonight ─────────────────────────────
                if (factors.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _buildSectionLabel('WHAT MAY AFFECT YOUR SLEEP'),
                  const SizedBox(height: 10),
                  _buildFactorsCard(factors),
                ],

                // ── Wind-down correlation insight ─────────────────────────
                if (showWindDownInsight) ...[
                  const SizedBox(height: 12),
                  _buildWindDownInsight(avgWDGood, avgWDBad),
                ],

                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  // ══ Log tab widgets ════════════════════════════════════════════════════════

  // ── Wind-down accountability helpers ──────────────────────────────────────

  /// Consecutive nights (non-nap) where at least 4/6 wind-down steps were done.
  int _windDownStreak() {
    final nights = _bella
        .getSleepEntries()
        .where((e) => !e.isNap)
        .toList(); // already sorted newest-first
    int streak = 0;
    for (final e in nights) {
      if (e.windDownDone.length >= 4) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  /// For each wind-down item, computes the average sleep quality on nights
  /// when it was done vs. nights when it was skipped (last 14 non-nap nights).
  /// Returns a map of item → quality lift (positive = doing it helped).
  Map<String, double> _windDownItemImpact() {
    final nights =
        _bella.getSleepEntries().where((e) => !e.isNap).take(14).toList();
    if (nights.length < 3) return {};
    final impact = <String, double>{};
    for (final item in _windDownItems) {
      final withItem =
          nights.where((e) => e.windDownDone.contains(item)).toList();
      final withoutItem =
          nights.where((e) => !e.windDownDone.contains(item)).toList();
      if (withItem.isEmpty || withoutItem.isEmpty) continue;
      final avgWith = withItem.map((e) => e.quality).reduce((a, b) => a + b) /
          withItem.length;
      final avgWithout =
          withoutItem.map((e) => e.quality).reduce((a, b) => a + b) /
              withoutItem.length;
      impact[item] = avgWith - avgWithout;
    }
    return impact;
  }

  Widget _buildLogForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(children: [
          Expanded(
            child: Text(
              _editingId != null ? 'Edit session' : 'Log a sleep session',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: SageColors.ink),
            ),
          ),
          if (_editingId != null)
            TextButton(
              onPressed: () => setState(() {
                _editingId = null;
                _bedtime = null;
                _wakeTime = null;
                _quality = 3;
                _windDownDone.clear();
                _isNap = false;
              }),
              child: Text('Cancel',
                  style: TextStyle(fontSize: 12, color: SageColors.inkSoft)),
            ),
        ]),
        const SizedBox(height: 2),
        Text(
          _editingId != null
              ? 'Editing existing session'
              : 'Log night sleep and naps separately.',
          style: TextStyle(fontSize: 12, color: SageColors.inkSoft),
        ),

        // Type chips
        const SizedBox(height: 14),
        Row(children: [
          Text('Type:',
              style: TextStyle(fontSize: 13, color: SageColors.inkSoft)),
          const SizedBox(width: 12),
          _typeChip(
              'Night sleep', !_isNap, () => setState(() => _isNap = false)),
          const SizedBox(width: 8),
          _typeChip('Nap', _isNap, () => setState(() => _isNap = true)),
        ]),

        // Time pickers
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _timeButton(
                  'Bedtime', _fmt(_bedtime), () => _pickTime(isBedtime: true))),
          const SizedBox(width: 12),
          Expanded(
              child: _timeButton('Wake time', _fmt(_wakeTime),
                  () => _pickTime(isBedtime: false))),
        ]),

        // Duration pill
        if (_bedtime != null && _wakeTime != null) ...[
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: SageColors.moss.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.access_time, size: 14, color: SageColors.moss),
                const SizedBox(width: 6),
                Text(
                  _durationLabel(_formDuration()),
                  style: SageText.mono(
                      size: 13,
                      weight: FontWeight.w600,
                      color: SageColors.moss),
                ),
              ]),
            ),
          ),
        ],

        // Quality stars
        const SizedBox(height: 18),
        Text('Sleep quality',
            style: TextStyle(fontSize: 13, color: SageColors.inkSoft)),
        const SizedBox(height: 6),
        Row(
          children: List.generate(5, (i) {
            final val = i + 1;
            final selected = val <= _quality;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _quality = val),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    selected ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: selected ? SageColors.amber : SageColors.inkSoft,
                    size: 30,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            ['', 'Poor', 'Fair', 'Okay', 'Good', 'Great'][_quality],
            style: TextStyle(
                fontSize: 12,
                color: SageColors.amber,
                fontWeight: FontWeight.w600),
          ),
        ),

        // Wind-down checklist (night only) — with streak + per-item impact hints
        if (!_isNap) ...[
          const SizedBox(height: 18),
          _buildWindDownChecklist(),
        ],

        // Save button
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: SageColors.moss,
              foregroundColor: SageColors.linen,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              _editingId != null ? 'Update session' : 'Save session',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        // The sleep sounds button has been removed from here.
      ],
    );
  }

  Widget _buildWindDownChecklist() {
    final streak = _windDownStreak();
    final impact = _windDownItemImpact();
    final done = _windDownDone.length;
    final total = _windDownItems.length;

    // Streak label and color
    final streakColor = streak >= 5
        ? SageColors.moss
        : streak >= 2
            ? SageColors.amber
            : SageColors.inkSoft;
    final streakLabel = streak == 0
        ? 'No streak yet'
        : streak == 1
            ? '1-night streak'
            : '$streak-night streak';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: title + progress + streak
        Row(children: [
          Text('Wind-down checklist',
              style: TextStyle(fontSize: 13, color: SageColors.inkSoft)),
          const Spacer(),
          // Streak pill
          if (streak > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: streakColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: streakColor.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.local_fire_department_rounded,
                    size: 11, color: streakColor),
                const SizedBox(width: 3),
                Text(streakLabel,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: streakColor,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(width: 8),
          ],
          Text('$done/$total',
              style: TextStyle(
                  fontSize: 12,
                  color: done == total ? SageColors.moss : SageColors.inkSoft,
                  fontWeight: FontWeight.w600)),
        ]),

        // Progress bar
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total > 0 ? done / total : 0,
            minHeight: 4,
            backgroundColor: SageColors.line,
            valueColor: AlwaysStoppedAnimation<Color>(
              done == total ? SageColors.moss : SageColors.amber,
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Items — each shows an impact hint when we have enough data
        ..._windDownItems.map((item) {
          final checked = _windDownDone.contains(item);
          final lift = impact[item]; // null = not enough data
          // Show hint only for unchecked items with a meaningful positive lift
          final showHint = !checked && lift != null && lift >= 0.3;

          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  value: checked,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _windDownDone.add(item);
                    } else {
                      _windDownDone.remove(item);
                    }
                  }),
                  title: Text(
                    item,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: checked ? SageColors.inkSoft : SageColors.ink,
                      decoration: checked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  activeColor: SageColors.moss,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                // Impact hint: shown under unchecked items with proven lift
                if (showHint)
                  Padding(
                    padding: const EdgeInsets.only(left: 52, bottom: 4),
                    child: Row(children: [
                      Icon(Icons.trending_up_rounded,
                          size: 12, color: SageColors.moss),
                      const SizedBox(width: 4),
                      Text(
                        'Your sleep quality is ${lift >= 1.0 ? "noticeably" : "slightly"} better when you do this',
                        style: TextStyle(fontSize: 11, color: SageColors.moss),
                      ),
                    ]),
                  ),
              ],
            ),
          );
        }),

        // Skipped-items callout when user hasn't checked everything
        if (done > 0 && done < total) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: SageColors.amber.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: SageColors.amber.withValues(alpha: 0.2)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 13, color: SageColors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${total - done} step${total - done == 1 ? "" : "s"} skipped tonight. '
                  'These are saved with your sleep log — your analytics will show how they affect your quality over time.',
                  style: TextStyle(
                      fontSize: 11.5, color: SageColors.amber, height: 1.4),
                ),
              ),
            ]),
          ),
        ],
        if (done == total && total > 0) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: SageColors.moss.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SageColors.moss.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.check_circle_outline,
                  size: 13, color: SageColors.moss),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Full wind-down routine done. ${streak >= 3 ? "That's $streak nights in a row — keep it up." : "Great habit building."}',
                  style: TextStyle(
                      fontSize: 11.5, color: SageColors.moss, height: 1.4),
                ),
              ),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _buildPeriodRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                            color: sel ? SageColors.moss : SageColors.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: sel ? SageColors.moss : SageColors.line),
                          ),
                          child: Text(p.label,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? SageColors.linen
                                      : SageColors.inkSoft)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Type filter + today toggle on same row
        Row(children: [
          _segChip('All', _SleepView.all),
          const SizedBox(width: 8),
          _segChip('Night', _SleepView.night),
          const SizedBox(width: 8),
          _segChip('Naps', _SleepView.naps),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _showToday = !_showToday),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _showToday
                    ? SageColors.amber.withValues(alpha: 0.12)
                    : SageColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _showToday ? SageColors.amber : SageColors.line,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                    _showToday
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_outlined,
                    size: 13,
                    color: _showToday ? SageColors.amber : SageColors.inkSoft),
                const SizedBox(width: 5),
                Text('Today',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _showToday
                            ? SageColors.amber
                            : SageColors.inkSoft)),
              ]),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildScoreCard(double? score, _PeriodReport report) {
    return _card(
      child: Row(children: [
        // Score circle
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: score == null
                ? SageColors.line
                : score >= 4
                    ? SageColors.moss.withValues(alpha: 0.15)
                    : score >= 3
                        ? SageColors.amber.withValues(alpha: 0.15)
                        : SageColors.clay.withValues(alpha: 0.15),
          ),
          child: Center(
            child: score == null
                ? Icon(Icons.bedtime_outlined,
                    color: SageColors.inkSoft, size: 22)
                : Text(
                    score.toStringAsFixed(1),
                    style: SageText.mono(
                      size: 20,
                      weight: FontWeight.w700,
                      color: score >= 4
                          ? SageColors.moss
                          : score >= 3
                              ? SageColors.amber
                              : SageColors.clay,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              score == null
                  ? 'No data yet'
                  : score >= 4
                      ? 'Great sleep score'
                      : score >= 3
                          ? 'Fair sleep score'
                          : 'Sleep needs attention',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: SageColors.ink),
            ),
            const SizedBox(height: 3),
            if (report.avgNightQuality != null)
              Text(
                'Avg quality ${report.avgNightQuality!.toStringAsFixed(1)}/5'
                '${report.avgNightDurationMin != null ? "  ·  ${_hm(report.avgNightDurationMin!.round())} avg" : ""}',
                style: TextStyle(fontSize: 12, color: SageColors.inkSoft),
              ),
            if (score == null)
              Text('Log your first night sleep to see your score',
                  style: TextStyle(fontSize: 12, color: SageColors.inkSoft)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildGraphSection(
      List<SleepEntry> filtered, List<SleepEntry> graphEntries) {
    if (filtered.isEmpty) {
      return _card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text('No entries for this period',
                style: TextStyle(color: SageColors.inkSoft, fontSize: 13)),
          ),
        ),
      );
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_view == _SleepView.all || _view == _SleepView.night)
            _sleepBarGraph(
              title: 'Night sleep quality',
              entries: graphEntries.where((e) => !e.isNap).toList(),
              color: SageColors.moss,
            ),
          if (_view == _SleepView.all &&
              graphEntries.any((e) => !e.isNap) &&
              graphEntries.any((e) => e.isNap))
            const SizedBox(height: 16),
          if (_view == _SleepView.all || _view == _SleepView.naps)
            _sleepBarGraph(
              title: 'Nap quality',
              entries: graphEntries.where((e) => e.isNap).toList(),
              color: SageColors.amber,
            ),
        ],
      ),
    );
  }

  Widget _buildEntryList(List<SleepEntry> entries) {
    final shown = (_view == _SleepView.all
            ? entries
            : entries
                .where((e) => _view == _SleepView.naps ? e.isNap : !e.isNap)
                .toList())
        .take(10)
        .toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sessions',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: SageColors.ink)),
          const SizedBox(height: 10),
          ...shown.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (e.isNap ? SageColors.amber : SageColors.moss)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(e.isNap ? 'Nap' : 'Night',
                        style: TextStyle(
                            fontSize: 10,
                            color:
                                e.isNap ? SageColors.amber : SageColors.moss)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_dateLabel(e.date)}  ·  ${_durationLabel(_duration(e))}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: SageColors.ink),
                    ),
                  ),
                  ...List.generate(
                      5,
                      (i) => Icon(
                            i < e.quality
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 12,
                            color: i < e.quality
                                ? SageColors.amber
                                : SageColors.line,
                          )),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _loadEntryForEdit(e),
                    child: Icon(Icons.edit_outlined,
                        size: 15, color: SageColors.inkSoft),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _deleteEntry(e),
                    child: Icon(Icons.delete_outline,
                        size: 15, color: SageColors.clay),
                  ),
                ]),
              )),
          if (entries.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${entries.length - 10} more entries in this period',
                style: TextStyle(fontSize: 11.5, color: SageColors.inkSoft),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTodayInsightCard(
      List<SleepEntry> sessions, List<_SleepInsight> insights, int totalMin) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.today_outlined, color: SageColors.moss, size: 17),
            const SizedBox(width: 8),
            Text("Today's sessions",
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: SageColors.ink)),
            const Spacer(),
            Text('Total: ${_hm(totalMin)}',
                style: SageText.mono(size: 11.5, color: SageColors.moss)),
          ]),
          if (insights.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...insights.map((ins) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _insightBanner(ins),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailedReport(_PeriodReport report) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.assessment_outlined, color: SageColors.moss, size: 17),
            const SizedBox(width: 8),
            Text('${_period.label} Report',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: SageColors.ink)),
          ]),
          const SizedBox(height: 14),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _reportStat('${report.nights}', 'Night sessions'),
              _reportStat(
                  report.avgNightQuality != null
                      ? '${report.avgNightQuality!.toStringAsFixed(1)}/5'
                      : '—',
                  'Avg quality'),
              _reportStat(
                  report.avgNightDurationMin != null
                      ? _hm(report.avgNightDurationMin!.round())
                      : '—',
                  'Avg duration'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _reportStat('${report.naps}', 'Naps'),
              _reportStat('${report.goodDaysCount}', 'Good-sleep days'),
              _reportStat(
                  report.avgWindDown != null
                      ? report.avgWindDown!.toStringAsFixed(1)
                      : '—',
                  'Avg wind-down steps'),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Narrative
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.auto_awesome_outlined, size: 15, color: SageColors.moss),
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

  Widget _buildFactorsCard(List<_SleepFactor> factors) {
    return _card(
      child: Column(
        children: factors
            .map((f) => GestureDetector(
                  onTap: f.onTap,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: f.color.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(f.icon, size: 14, color: f.color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(f.label,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: SageColors.ink)),
                                const SizedBox(height: 2),
                                Text(f.detail,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: SageColors.inkSoft,
                                        height: 1.4)),
                              ])),
                          if (f.onTap != null)
                            Icon(Icons.chevron_right,
                                size: 15, color: SageColors.inkSoft),
                        ]),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildWindDownInsight(double avgGood, double avgBad) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SageColors.moss.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SageColors.moss.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(Icons.insights, color: SageColors.moss, size: 17),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Your best nights correlate with more wind-down steps completed '
            '(avg ${avgGood.toStringAsFixed(1)} vs '
            '${avgBad.toStringAsFixed(1)} on poor nights).',
            style:
                TextStyle(fontSize: 12.5, color: SageColors.moss, height: 1.4),
          ),
        ),
      ]),
    );
  }

  // ══ Shared small widgets ═══════════════════════════════════════════════════

  Widget _sleepBarGraph({
    required String title,
    required List<SleepEntry> entries,
    required Color color,
  }) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('No $title sessions in this period',
            style: TextStyle(fontSize: 11.5, color: SageColors.inkSoft)),
      );
    }
    final ordered = entries.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 6),
        SizedBox(
          height: 64,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: ordered.map((e) {
              final isToday = e.date.year == DateTime.now().year &&
                  e.date.month == DateTime.now().month &&
                  e.date.day == DateTime.now().day;
              final h = 11.0 * e.quality + 6;
              final col = e.quality >= 4
                  ? SageColors.moss
                  : e.quality >= 3
                      ? SageColors.amber
                      : SageColors.clay;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Tooltip(
                    message:
                        '${_dateLabel(e.date)}: ${e.quality}/5 · ${_durationLabel(_duration(e))}',
                    child: Container(
                      height: h,
                      decoration: BoxDecoration(
                        color: col.withValues(alpha: isToday ? 1.0 : 0.7),
                        borderRadius: BorderRadius.circular(4),
                        border:
                            isToday ? Border.all(color: col, width: 1.5) : null,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: ordered.map((e) {
            final isToday = e.date.year == DateTime.now().year &&
                e.date.month == DateTime.now().month &&
                e.date.day == DateTime.now().day;
            return Expanded(
              child: Text(
                _dateLabel(e.date),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  color: isToday ? SageColors.moss : SageColors.inkSoft,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _segChip(String label, _SleepView value) {
    final selected = _view == value;
    return GestureDetector(
      onTap: () => setState(() => _view = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? SageColors.moss : SageColors.card,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? SageColors.moss : SageColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? SageColors.linen : SageColors.inkSoft),
        ),
      ),
    );
  }

  Widget _typeChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? SageColors.moss : SageColors.linen,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? SageColors.moss : SageColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? SageColors.linen : SageColors.inkSoft),
        ),
      ),
    );
  }

  Widget _insightBanner(_SleepInsight insight) {
    final content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: insight.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: insight.color.withValues(alpha: 0.22)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(insight.icon, size: 15, color: insight.color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(insight.text,
                style: TextStyle(
                    fontSize: 12, color: insight.color, height: 1.4))),
        if (insight.onTap != null) ...[
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 15, color: insight.color),
        ],
      ]),
    );
    if (insight.onTap == null) return content;
    return GestureDetector(onTap: insight.onTap, child: content);
  }

  Widget _timeButton(String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: SageColors.linen,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SageColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(fontSize: 11.5, color: SageColors.inkSoft)),
          const SizedBox(height: 4),
          Text(value, style: SageText.mono(size: 16, weight: FontWeight.w600)),
        ]),
      ),
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

// ── Data classes ─────────────────────────────────────────────────────────────

class _SleepInsight {
  final IconData icon;
  final Color color;
  final String text;

  /// Optional navigation action. When set, the banner renders as tappable
  /// with a trailing chevron so the user can act on the advice immediately.
  final VoidCallback? onTap;
  const _SleepInsight(
      {required this.icon,
      required this.color,
      required this.text,
      this.onTap});
}

class _SleepFactor {
  final IconData icon;
  final Color color;
  final String label;
  final String detail;
  final VoidCallback? onTap;
  const _SleepFactor(
      {required this.icon,
      required this.color,
      required this.label,
      required this.detail,
      this.onTap});
}

class _PeriodReport {
  final int nights;
  final int naps;
  final double? avgNightQuality;
  final double? avgNightDurationMin;
  final int goodDaysCount;
  final double? avgWindDown;
  final double? score;
  final String narrative;

  const _PeriodReport({
    required this.nights,
    required this.naps,
    required this.avgNightQuality,
    required this.avgNightDurationMin,
    required this.goodDaysCount,
    required this.avgWindDown,
    required this.score,
    required this.narrative,
  });
}

/// A small pill badge shown inside the nudge modal for each active signal.
class _NudgeBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _NudgeBadge({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]),
    );
  }
}
