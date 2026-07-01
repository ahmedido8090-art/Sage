// screens/chronic_care_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/bella_service.dart';
import '../services/user_service.dart';
import '../services/care_rules.dart';
import '../models/bella_data.dart';
import '../widgets/reveal.dart';
import 'breathwork_screen.dart';
import 'zzzify_screen.dart';
import 'pure_plate_screen.dart';
import 'walking_screen.dart';

/// Bella · Chronic Care.
/// Improvements over v1:
///  • Readings carry an optional free-text note (add / edit).
///  • Every reading in the history list can be edited or deleted via a
///    long-press menu or the trailing icon button.
///  • The symptom guide is condition-aware and context-aware: it weaves in
///    the user's most-recent reading, today's food quality, sleep average,
///    and check-in stress so the advice is genuinely personalised.
///  • Cross-screen insight banners connect to Sleep, Breathwork, and food data.
class ChronicCareScreen extends StatefulWidget {
  const ChronicCareScreen({super.key});

  @override
  State<ChronicCareScreen> createState() => _ChronicCareScreenState();
}

class _ChronicCareScreenState extends State<ChronicCareScreen>
    with SingleTickerProviderStateMixin {
  final BellaService _bella = BellaService();
  String? _selectedCondition;
  String? _selectedSymptom;
  SymptomGuidance? _result;

  final _valueController = TextEditingController();
  final _secondaryController = TextEditingController();
  final _noteController = TextEditingController();

  late TabController _tabController;

  List<String> get _conditions =>
      UserService().currentUserObject?.chronicDiseases ?? [];

  // ── Reading-type metadata ─────────────────────────────────────────────────

  static const Map<String, Map<String, String>> _readingTypeForCondition = {
    'Diabetes': {'type': 'Blood Glucose', 'unit': 'mg/dL'},
    'Hypertension': {'type': 'Blood Pressure', 'unit': 'mmHg'},
    'Heart Disease': {'type': 'Blood Pressure', 'unit': 'mmHg'},
    'Asthma': {'type': 'Peak Flow', 'unit': 'L/min'},
    'Chronic Kidney Disease': {'type': 'Blood Pressure', 'unit': 'mmHg'},
    'High Cholesterol': {'type': 'Cholesterol', 'unit': 'mg/dL'},
    'Arthritis': {'type': 'Pain Level', 'unit': '/10'},
    'Thyroid Disorder': {'type': 'Weight', 'unit': 'kg'},
  };

  // ── Normal-range helpers (per condition) ─────────────────────────────────

  static const Map<String, Map<String, dynamic>> _normalRanges = {
    'Diabetes': {'low': 70, 'high': 180, 'optLow': 80, 'optHigh': 130},
    'Hypertension': {'low': 0, 'high': 139, 'optLow': 0, 'optHigh': 119},
    'Heart Disease': {'low': 0, 'high': 139, 'optLow': 0, 'optHigh': 119},
    'Chronic Kidney Disease': {
      'low': 0,
      'high': 129,
      'optLow': 0,
      'optHigh': 119
    },
    'Asthma': {'low': 300, 'high': 700, 'optLow': 400, 'optHigh': 700},
    'High Cholesterol': {'low': 0, 'high': 200, 'optLow': 0, 'optHigh': 170},
    'Arthritis': {'low': 0, 'high': 5, 'optLow': 0, 'optHigh': 3},
    'Thyroid Disorder': {'low': 40, 'high': 130, 'optLow': 50, 'optHigh': 90},
  };

  bool _isFlagged(ReadingEntry r, String condition) {
    final range = _normalRanges[condition];
    if (range == null) return false;
    if (condition == 'Asthma') return r.value < (range['low'] as num);
    final high = range['high'] as num;
    final low = range['low'] as num;
    final flagSystolic = r.value > high || r.value < low;
    final flagDiastolic = r.secondaryValue != null && r.secondaryValue! >= 90;
    return flagSystolic || flagDiastolic;
  }

  String _rangeHint(String condition) {
    final meta = _readingTypeForCondition[condition];
    if (meta == null) return '';
    final range = _normalRanges[condition];
    if (range == null) return '';
    final unit = meta['unit']!;
    if (condition == 'Asthma') return 'Target ≥ ${range['optLow']} $unit';
    if (condition == 'Arthritis') {
      return 'Well-managed: ≤ ${range['optHigh']} $unit';
    }
    if (condition == 'Hypertension' ||
        condition == 'Heart Disease' ||
        condition == 'Chronic Kidney Disease') {
      return 'Target: < ${range['optHigh']} / < 80 $unit';
    }
    return 'Target: ${range['optLow']}–${range['optHigh']} $unit';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (_conditions.isNotEmpty) _selectedCondition = _conditions.first;
  }

  @override
  void dispose() {
    _valueController.dispose();
    _secondaryController.dispose();
    _noteController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  bool get _isBloodPressure =>
      _readingTypeForCondition[_selectedCondition]?['type'] == 'Blood Pressure';

  // ── Save reading ──────────────────────────────────────────────────────────

  Future<void> _saveReading() async {
    if (_selectedCondition == null) return;
    final val = double.tryParse(_valueController.text.trim());
    if (val == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: const Text('Please enter a valid number'),
            backgroundColor: SageColors.clay),
      );
      return;
    }
    final meta = _readingTypeForCondition[_selectedCondition]!;
    final entry = ReadingEntry(
      id: 'rdg_${DateTime.now().millisecondsSinceEpoch}',
      time: DateTime.now(),
      condition: _selectedCondition!,
      type: meta['type']!,
      value: val,
      secondaryValue: _isBloodPressure
          ? double.tryParse(_secondaryController.text.trim())
          : null,
      unit: meta['unit']!,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );
    await _bella.addReading(entry);
    _valueController.clear();
    _secondaryController.clear();
    _noteController.clear();
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: const Text('Reading saved'),
          backgroundColor: SageColors.moss),
    );
  }

  // ── Edit reading dialog ───────────────────────────────────────────────────

  Future<void> _showEditDialog(ReadingEntry entry) async {
    final valCtrl = TextEditingController(text: entry.value.toStringAsFixed(1));
    final secCtrl = TextEditingController(
        text: entry.secondaryValue?.toStringAsFixed(0) ?? '');
    final noteCtrl = TextEditingController(text: entry.note ?? '');
    final meta = _readingTypeForCondition[entry.condition] ??
        {'type': entry.type, 'unit': entry.unit};
    final isBP = meta['type'] == 'Blood Pressure';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SageColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit ${meta['type']}',
            style: SageText.headline(color: SageColors.ink)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: valCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: isBP ? 'Systolic' : meta['type'],
                  suffixText: meta['unit'],
                  filled: true,
                  fillColor: SageColors.linen,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            if (isBP) ...[
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: secCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Diastolic',
                    filled: true,
                    fillColor: SageColors.linen,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'e.g. after meal, felt dizzy…',
              filled: true,
              fillColor: SageColors.linen,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: SageColors.inkSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: SageColors.sage,
                foregroundColor: SageColors.linen,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              final newVal = double.tryParse(valCtrl.text.trim());
              if (newVal == null) return;
              await _bella.editReading(entry.copyWith(
                value: newVal,
                secondaryValue:
                    isBP ? double.tryParse(secCtrl.text.trim()) : null,
                note:
                    noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              ));
              if (!mounted) return;
              Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Reading updated'),
                  backgroundColor: SageColors.moss));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    valCtrl.dispose();
    secCtrl.dispose();
    noteCtrl.dispose();
  }

  // ── Delete reading ────────────────────────────────────────────────────────

  Future<void> _confirmDelete(ReadingEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SageColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete reading?',
            style: SageText.headline(color: SageColors.ink)),
        content: Text(
          'This will permanently remove the ${entry.type} reading '
          '(${entry.value.toStringAsFixed(0)}${entry.secondaryValue != null ? '/${entry.secondaryValue!.toStringAsFixed(0)}' : ''} ${entry.unit}) '
          'from ${_formatDate(entry.time)}.',
          style: TextStyle(color: SageColors.inkSoft, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: SageColors.inkSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: SageColors.clay,
                foregroundColor: SageColors.linen,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _bella.deleteReading(entry);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Reading deleted'),
            backgroundColor: SageColors.clay));
      }
    }
  }

  // ── Symptom check ─────────────────────────────────────────────────────────

  void _checkSymptom(String symptom) {
    if (_selectedCondition == null) return;
    final readings = _bella.getReadings(condition: _selectedCondition);
    final mostRecent = readings.isEmpty ? null : readings.first;
    final foodToday = _bella.getFoodEntries(onDate: DateTime.now());
    setState(() {
      _selectedSymptom = symptom;
      _result = CareRules.guidanceFor(
        _selectedCondition!,
        symptom,
        mostRecentReading: mostRecent,
        recentFood: foodToday,
      );
    });
  }

  // ── Cross-screen context insights ─────────────────────────────────────────

  List<_CareInsight> _buildContextInsights() {
    if (_selectedCondition == null) return [];
    final insights = <_CareInsight>[];
    final cond = _selectedCondition!;

    // ── Sleep ──────────────────────────────────────────────────────────────
    final sleepAvg = _bella.averageSleepQuality();
    if (sleepAvg != null && sleepAvg < 2.5) {
      final detail = cond == 'Diabetes'
          ? 'Poor sleep impairs glucose regulation and insulin sensitivity. '
              'Aim for 7–9 h of quality sleep.'
          : cond == 'Hypertension'
              ? 'Sleep deprivation elevates cortisol and raises blood pressure. '
                  'Consistent sleep reduces systolic readings.'
              : cond == 'Arthritis'
                  ? 'Poor sleep amplifies pain perception and fatigue. '
                      'A bedtime wind-down routine can break the cycle.'
                  : cond == 'Asthma'
                      ? 'Night-time symptoms often interrupt sleep; '
                          'elevating your head and avoiding late meals can help.'
                      : 'Poor sleep can worsen symptoms of $cond over time.';
      insights.add(_CareInsight(
        icon: Icons.bedtime_outlined,
        color: SageColors.moss,
        title: 'Poor sleep this week (avg ${sleepAvg.toStringAsFixed(1)}/5)',
        detail: detail,
        actionLabel: 'Open Sleep tools',
        onAction: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ZZZifyScreen())),
      ));
    }

    // ── Diet quality ───────────────────────────────────────────────────────
    final foodToday = _bella.getFoodEntries(onDate: DateTime.now());
    final highSodium = foodToday.any((f) => f.tag == 'high-sodium');
    final highCarb = foodToday.any((f) => f.tag == 'high-carb');
    final totalCal = foodToday.fold<int>(0, (s, f) => s + (f.calories ?? 0));

    if ((cond == 'Hypertension' ||
            cond == 'Heart Disease' ||
            cond == 'Chronic Kidney Disease') &&
        highSodium) {
      insights.add(_CareInsight(
        icon: Icons.water_drop_outlined,
        color: SageColors.clay,
        title: 'High-sodium food logged today',
        detail: 'Sodium raises fluid retention and blood pressure. '
            'Aim for under 1,500 mg/day for your condition.',
      ));
    }
    if (cond == 'Diabetes' && highCarb) {
      insights.add(_CareInsight(
        icon: Icons.bakery_dining_outlined,
        color: SageColors.amber,
        title: 'High-carb meal today',
        detail: 'A large carbohydrate load can spike post-meal blood glucose. '
            'Pairing carbs with protein or fibre slows absorption.',
      ));
    }
    if (cond == 'High Cholesterol' && highSodium) {
      insights.add(_CareInsight(
        icon: Icons.favorite_border,
        color: SageColors.clay,
        title: 'High-sodium food today',
        detail: 'Elevated sodium strains the cardiovascular system and '
            'compounds the risk from high cholesterol.',
      ));
    }
    if (totalCal > 2500 &&
        (cond == 'Diabetes' ||
            cond == 'High Cholesterol' ||
            cond == 'Heart Disease')) {
      insights.add(_CareInsight(
        icon: Icons.local_fire_department_outlined,
        color: SageColors.amber,
        title: 'High calorie day ($totalCal kcal)',
        detail: 'Excess calories contribute to weight gain which worsens '
            '$cond management over time.',
      ));
    }

    // ── Daily check-in: stress ─────────────────────────────────────────────
    final checkin = _bella.lastCheckin;
    if (checkin != null) {
      final todayCheckin = checkin.time.year == DateTime.now().year &&
          checkin.time.month == DateTime.now().month &&
          checkin.time.day == DateTime.now().day;

      if (checkin.stress >= 4) {
        final detail = cond == 'Hypertension'
            ? 'Stress triggers adrenaline spikes that directly raise '
                'blood pressure. Short breathing exercises can offset this.'
            : cond == 'Diabetes'
                ? 'Stress hormones (cortisol, adrenaline) cause blood '
                    'glucose to rise even without food intake.'
                : cond == 'Asthma'
                    ? 'Emotional stress is a recognised asthma trigger. '
                        'Slow diaphragmatic breathing can reduce airway tension.'
                    : cond == 'Heart Disease'
                        ? 'Chronic stress increases heart rate and blood '
                            'pressure, straining the cardiovascular system.'
                        : 'High stress can aggravate $cond symptoms and '
                            'undermine daily management.';
        insights.add(_CareInsight(
          icon: Icons.bolt,
          color: SageColors.amber,
          title: todayCheckin
              ? 'High stress reported today (${checkin.stress}/5)'
              : 'High stress in last check-in (${checkin.stress}/5)',
          detail: detail,
          actionLabel: 'Try calming breathwork',
          onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      const BreathworkScreen(initialHeartRate: 72))),
        ));
      }

      // Low energy insight
      if (checkin.energy <= 2 &&
          (cond == 'Diabetes' ||
              cond == 'Thyroid Disorder' ||
              cond == 'Arthritis')) {
        insights.add(_CareInsight(
          icon: Icons.battery_2_bar,
          color: SageColors.inkSoft,
          title: 'Low energy reported',
          detail: cond == 'Diabetes'
              ? 'Fatigue can signal blood glucose fluctuations — '
                  'check your last reading if you haven\'t already.'
              : cond == 'Thyroid Disorder'
                  ? 'Persistent fatigue is a key thyroid symptom. '
                      'Track weight alongside energy to spot trends.'
                  : 'Rest and gentle movement both help manage energy in arthritis.',
        ));
      }
    }

    // ── Trend-based insight ────────────────────────────────────────────────
    final meta = _readingTypeForCondition[cond];
    if (meta != null) {
      final trend = _bella.readingTrend(cond, meta['type']!, n: 5);
      if (trend.length >= 3) {
        final rising = trend.last.value > trend.first.value;
        final range = _normalRanges[cond];
        if (range != null) {
          final allHigh = trend.every((r) => r.value > (range['high'] as num));
          if (allHigh) {
            insights.add(_CareInsight(
              icon: Icons.trending_up,
              color: SageColors.clay,
              title: '${meta['type']} consistently elevated',
              detail: 'Your last ${trend.length} readings are all above the '
                  'recommended range. Consider discussing a medication or '
                  'lifestyle review with your care team.',
            ));
          } else if (rising) {
            insights.add(_CareInsight(
              icon: Icons.show_chart,
              color: SageColors.amber,
              title: '${meta['type']} trending upward',
              detail: 'Your readings have increased over the past '
                  '${trend.length} measurements. Keep an eye on this trend.',
            ));
          }
        }
      }
    }

    // ── Hydration (Kidney Disease + Hypertension) ─────────────────────────
    // Water intake is clinically meaningful for these two conditions specifically.
    // We only surface this when the user is genuinely under-hydrated for the
    // time of day — not as a generic reminder shown to everyone.
    final isHydrationCondition =
        cond == 'Chronic Kidney Disease' || cond == 'Hypertension';
    if (isHydrationCondition) {
      final waterMl = _bella.todayWaterMl();
      final hour = DateTime.now().hour;
      final underHydrated =
          (hour >= 10 && waterMl < 500) || (hour >= 14 && waterMl < 1000);
      if (underHydrated) {
        final detail = cond == 'Chronic Kidney Disease'
            ? 'Adequate hydration supports kidney filtration and helps prevent '
                'further decline. Aim for ~2 L/day unless your care team advises '
                'otherwise. You\'ve logged ${waterMl}ml so far today.'
            : 'Staying well hydrated supports healthy blood pressure. '
                'Dehydration can cause a compensatory rise in BP. '
                'You\'ve logged ${waterMl}ml so far today — aim for 2 L.';
        insights.add(_CareInsight(
          icon: Icons.water_drop_outlined,
          color: SageColors.moss,
          title: 'Low hydration today (${waterMl}ml logged)',
          detail: detail,
          actionLabel: 'Log water in PurePlate',
          onAction: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PurePlateScreen())),
        ));
      }
    }

    // ── Activity sessions — exercise directly affects chronic conditions ───
    // Walking in particular has well-documented effects on glucose and BP.
    // We read today's sessions and surface a personalised insight so the
    // user understands the direct link between what they did and their reading.
    final walkMin = _bella.sessionMinutesToday('walking');
    final medMin = _bella.sessionMinutesToday('meditation');
    final bwCount = _bella.sessionsToday('breathwork');
    final latestReading = _bella.getReadings(condition: cond).isNotEmpty
        ? _bella.getReadings(condition: cond).first
        : null;
    final readingFlagged =
        latestReading != null && _isFlagged(latestReading, cond);

    if (walkMin > 0 &&
        (cond == 'Diabetes' ||
            cond == 'Hypertension' ||
            cond == 'Heart Disease' ||
            cond == 'High Cholesterol')) {
      final detail = cond == 'Diabetes'
          ? 'You walked ${walkMin}min today — physical activity lowers blood glucose '
              'by increasing muscle glucose uptake independent of insulin.'
          : cond == 'Hypertension' || cond == 'Heart Disease'
              ? 'You walked ${walkMin}min today — regular aerobic activity lowers '
                  'resting blood pressure and strengthens the cardiovascular system.'
              : 'You walked ${walkMin}min today — aerobic exercise raises HDL '
                  '(good cholesterol) and helps manage your levels over time.';
      insights.add(_CareInsight(
        icon: Icons.directions_walk_outlined,
        color: SageColors.moss,
        title: 'Active today — ${walkMin}min walk',
        detail: detail,
      ));
    } else if (walkMin == 0 &&
        readingFlagged &&
        (cond == 'Diabetes' || cond == 'Hypertension')) {
      // Flagged reading and no walk today — suggest one as a direct action.
      final detail = cond == 'Diabetes'
          ? 'Your reading is outside range. A 15–20 min walk right now '
              'is one of the fastest non-medication ways to lower blood glucose.'
          : 'Your reading is elevated. A gentle 20-min walk can have an '
              'immediate modest effect on blood pressure.';
      insights.add(_CareInsight(
        icon: Icons.directions_walk_outlined,
        color: SageColors.clay,
        title: 'A walk could help right now',
        detail: detail,
        actionLabel: 'Start a walk',
        onAction: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const WalkingScreen(
                initialHeartRate: 72,
                initialSteps: 0,
              ),
            ),
          );
        },
      ));
    }

    if ((medMin >= 5 || bwCount > 0) &&
        (cond == 'Hypertension' ||
            cond == 'Heart Disease' ||
            cond == 'Asthma')) {
      final detail = cond == 'Hypertension' || cond == 'Heart Disease'
          ? '${medMin + (bwCount > 0 ? 10 : 0)} min of mindfulness today — '
              'breathing and meditation reduce cortisol and can lower resting BP.'
          : 'Breathwork today supports diaphragmatic control and may reduce '
              'airway sensitivity over time.';
      insights.add(_CareInsight(
        icon: Icons.self_improvement_outlined,
        color: SageColors.sage,
        title: 'Mind practice today',
        detail: detail,
      ));
    }

    return insights;
  }

  // ── Trend bar chart helpers ───────────────────────────────────────────────

  String _trendLabel(List<ReadingEntry> trend, String condition) {
    if (trend.length < 2) return '';
    final last = trend.last.value;
    final prev = trend[trend.length - 2].value;
    final delta = last - prev;
    final dir = delta > 0 ? '↑' : '↓';
    if (_isFlagged(trend.last, condition)) {
      return '$dir Last reading outside target range — worth monitoring.';
    }
    if (delta.abs() < 1) return 'Stable over recent readings.';
    return '$dir ${delta.abs().toStringAsFixed(0)} from previous.';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_conditions.isEmpty) {
      return Scaffold(
        backgroundColor: SageColors.linen,
        appBar: AppBar(
            title: Text('Chronic Care',
                style: SageText.headline(color: SageColors.ink))),
        body: const Reveal(size: RevealSize.large, child: _NoConditionsBody()),
      );
    }

    return Scaffold(
      backgroundColor: SageColors.linen,
      appBar: AppBar(
        title: Text('Chronic Care',
            style: SageText.headline(color: SageColors.ink)),
        bottom: _conditions.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(50),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _conditions.map((c) {
                        final selected = c == _selectedCondition;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: selected
                                        ? SageColors.linen
                                        : SageColors.ink)),
                            selected: selected,
                            selectedColor: SageColors.sage,
                            backgroundColor: SageColors.card,
                            onSelected: (_) => setState(() {
                              _selectedCondition = c;
                              _selectedSymptom = null;
                              _result = null;
                            }),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: _conditions.isNotEmpty && _selectedCondition != null
          ? Reveal(size: RevealSize.large, child: _buildBody())
          : const SizedBox.shrink(),
    );
  }

  Widget _buildBody() {
    final cond = _selectedCondition!;
    final meta =
        _readingTypeForCondition[cond] ?? {'type': 'Reading', 'unit': ''};
    final trend = _bella.readingTrend(cond, meta['type']!);
    final trendNote = _trendLabel(trend, cond);
    final contextInsights = _buildContextInsights();
    final allReadings = _bella.getReadings(condition: cond);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Context insight banners ──────────────────────────────────────
          if (contextInsights.isNotEmpty) ...[
            Text(
              'FACTORS AFFECTING YOUR ${cond.toUpperCase()}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: SageColors.inkSoft),
            ),
            const SizedBox(height: 10),
            ...contextInsights.map((ins) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _insightBanner(ins),
                )),
            const SizedBox(height: 8),
          ],

          // ── Log reading card ─────────────────────────────────────────────
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.monitor_heart_outlined,
                      color: SageColors.sage, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Log ${meta['type']}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: SageColors.ink),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Text(_rangeHint(cond),
                      style: TextStyle(fontSize: 11, color: SageColors.inkSoft),
                      overflow: TextOverflow.ellipsis),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _valueController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: _isBloodPressure ? 'Systolic' : meta['type'],
                        suffixText: meta['unit'],
                        filled: true,
                        fillColor: SageColors.linen,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  if (_isBloodPressure) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _secondaryController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Diastolic',
                          filled: true,
                          fillColor: SageColors.linen,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 10),
                // Note field
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'e.g. after meal, feeling tired…',
                    filled: true,
                    fillColor: SageColors.linen,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _saveReading,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Save reading'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SageColors.sage,
                      foregroundColor: SageColors.linen,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                // Trend mini chart
                if (trend.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Row(children: [
                    Text('Trend',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: SageColors.inkSoft)),
                    const SizedBox(width: 8),
                    if (trendNote.isNotEmpty)
                      Expanded(
                        child: Text(trendNote,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: trendNote.contains('outside')
                                    ? SageColors.clay
                                    : SageColors.inkSoft)),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 60,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: trend.map((r) {
                        final maxVal = trend
                            .map((e) => e.value)
                            .reduce((a, b) => a > b ? a : b);
                        final h =
                            maxVal > 0 ? (r.value / maxVal) * 50 + 8 : 8.0;
                        final flagged = _isFlagged(r, cond);
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Tooltip(
                              message:
                                  '${r.value.toStringAsFixed(0)}${r.secondaryValue != null ? '/${r.secondaryValue!.toStringAsFixed(0)}' : ''} ${r.unit}',
                              child: Container(
                                height: h,
                                decoration: BoxDecoration(
                                  color: (flagged
                                          ? SageColors.clay
                                          : SageColors.sage)
                                      .withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(3),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${trend.length} readings',
                          style: TextStyle(
                              fontSize: 11, color: SageColors.inkSoft)),
                      Text(
                        'Latest: ${trend.last.value.toStringAsFixed(0)}'
                        '${trend.last.secondaryValue != null ? '/${trend.last.secondaryValue!.toStringAsFixed(0)}' : ''}'
                        ' ${meta['unit']}',
                        style: SageText.mono(
                            size: 11,
                            weight: FontWeight.w600,
                            color: SageColors.ink),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Symptom guide ────────────────────────────────────────────────
          _card(child: _buildSymptomGuide(cond)),
          const SizedBox(height: 18),

          // ── Reading history ───────────────────────────────────────────────
          if (allReadings.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('READING HISTORY',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: SageColors.inkSoft)),
                Text('${allReadings.length} total',
                    style: TextStyle(fontSize: 11, color: SageColors.inkSoft)),
              ],
            ),
            const SizedBox(height: 10),
            _card(
              child: Column(
                children: allReadings.map((r) {
                  final flagged = _isFlagged(r, cond);
                  return _ReadingRow(
                    entry: r,
                    flagged: flagged,
                    onEdit: () => _showEditDialog(r),
                    onDelete: () => _confirmDelete(r),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Symptom guide widget ──────────────────────────────────────────────────

  Widget _buildSymptomGuide(String cond) {
    final symptoms = CareRules.symptomsFor(cond);
    // Enrich the symptom guide with context from other modules
    final checkin = _bella.lastCheckin;
    final lastReading = _bella.getReadings(condition: cond);
    final reading = lastReading.isEmpty ? null : lastReading.first;

    // Contextual preamble shown above the symptom chips
    String? preamble;
    if (reading != null && _isFlagged(reading, cond)) {
      preamble =
          'Your last reading (${reading.value.toStringAsFixed(0)} ${reading.unit}) '
          'is outside the target range — symptoms may be connected.';
    } else if (checkin != null && checkin.stress >= 4) {
      preamble = 'You reported high stress recently. Stress can trigger or '
          'amplify many ${cond.toLowerCase()} symptoms.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.health_and_safety_outlined,
              color: SageColors.clay, size: 18),
          const SizedBox(width: 8),
          Text('Symptom guide',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: SageColors.ink)),
        ]),
        const SizedBox(height: 4),
        Text('What are you feeling right now?',
            style: TextStyle(fontSize: 12, color: SageColors.inkSoft)),
        if (preamble != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: SageColors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: SageColors.amber.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: SageColors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(preamble,
                    style: TextStyle(
                        fontSize: 12, color: SageColors.ink, height: 1.4)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: symptoms.map((s) {
            final selected = s == _selectedSymptom;
            return ChoiceChip(
              label: Text(s,
                  style: TextStyle(
                      fontSize: 12,
                      color: selected ? SageColors.linen : SageColors.ink)),
              selected: selected,
              selectedColor: SageColors.clay,
              backgroundColor: SageColors.linen,
              onSelected: (_) => _checkSymptom(s),
            );
          }).toList(),
        ),
        if (_result != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: (_result!.urgent ? SageColors.clay : SageColors.moss)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (_result!.urgent ? SageColors.clay : SageColors.moss)
                      .withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                    _result!.urgent
                        ? Icons.warning_amber_rounded
                        : Icons.lightbulb_outline,
                    color: _result!.urgent ? SageColors.clay : SageColors.moss,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _result!.advice,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: _result!.urgent
                              ? SageColors.clay
                              : SageColors.moss,
                          height: 1.45),
                    ),
                  ),
                ]),
                // Reading-aware addendum
                if (reading != null && _isFlagged(reading, cond)) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Combined with your out-of-range reading, '
                    'consider contacting your doctor sooner rather than later.',
                    style: TextStyle(
                        fontSize: 12,
                        color: SageColors.clay,
                        fontStyle: FontStyle.italic,
                        height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          if (_result!.urgent) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const BreathworkScreen(initialHeartRate: 72))),
              icon: Icon(Icons.air, color: SageColors.clay, size: 16),
              label: Text('Try calming breathwork',
                  style: TextStyle(color: SageColors.clay, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: SageColors.clay.withValues(alpha: 0.4))),
            ),
          ],
          // Clear selection
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _selectedSymptom = null;
                _result = null;
              }),
              style: TextButton.styleFrom(
                  foregroundColor: SageColors.inkSoft,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('Clear', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDate(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${t.day}/${t.month}/${t.year}';
  }

  Widget _insightBanner(_CareInsight ins) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ins.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ins.color.withValues(alpha: 0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ins.icon, size: 15, color: ins.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(ins.title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ins.color)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(ins.detail,
            style: TextStyle(
                fontSize: 12, color: SageColors.inkSoft, height: 1.4)),
        if (ins.actionLabel != null && ins.onAction != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: ins.onAction,
            style: TextButton.styleFrom(
                foregroundColor: ins.color,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(ins.actionLabel!,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
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

// ── Reading row with edit / delete ────────────────────────────────────────────

class _ReadingRow extends StatelessWidget {
  final ReadingEntry entry;
  final bool flagged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ReadingRow({
    required this.entry,
    required this.flagged,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final valueLabel =
        '${entry.value.toStringAsFixed(entry.unit == '/10' ? 0 : 0)}'
        '${entry.secondaryValue != null ? '/${entry.secondaryValue!.toStringAsFixed(0)}' : ''} '
        '${entry.unit}';
    final diff = DateTime.now().difference(entry.time);
    final timeLabel = diff.inMinutes < 60
        ? '${diff.inMinutes}m ago'
        : diff.inHours < 24
            ? '${diff.inHours}h ago'
            : diff.inDays == 1
                ? 'Yesterday'
                : '${entry.time.day}/${entry.time.month}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            flagged ? Icons.warning_amber_rounded : Icons.circle,
            size: flagged ? 14 : 6,
            color: flagged ? SageColors.clay : SageColors.inkSoft,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    '${entry.type}: $valueLabel',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: flagged ? SageColors.clay : SageColors.ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(timeLabel,
                        style:
                            TextStyle(fontSize: 11, color: SageColors.inkSoft)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: onEdit,
                      child: Icon(Icons.edit_outlined,
                          size: 16, color: SageColors.sage),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onDelete,
                      child: Icon(Icons.delete_outline,
                          size: 16, color: SageColors.clay),
                    ),
                  ],
                ),
              ]),
              if (entry.note != null && entry.note!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  entry.note!,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: SageColors.inkSoft,
                      fontStyle: FontStyle.italic,
                      height: 1.35),
                ),
              ],
              const Divider(height: 14, thickness: 0.5),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Insight data class ────────────────────────────────────────────────────────

class _CareInsight {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _CareInsight({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });
}

// ── Empty-state body ──────────────────────────────────────────────────────────

class _NoConditionsBody extends StatelessWidget {
  const _NoConditionsBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                  color: SageColors.moss.withValues(alpha: 0.12),
                  shape: BoxShape.circle),
              child:
                  Icon(Icons.favorite_border, size: 36, color: SageColors.moss),
            ),
            const SizedBox(height: 20),
            Text('No conditions on file',
                style: SageText.headline(), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              'Chronic Care tailors itself to conditions you add in your '
              'Profile. Add one there to unlock readings, a symptom guide, '
              'and personalised cross-feature insights.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: SageColors.inkSoft, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
