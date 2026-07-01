// screens/pure_plate_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/bella_service.dart';
import '../services/user_service.dart';
import '../services/care_rules.dart';
import '../models/bella_data.dart';
import '../widgets/reveal.dart';
import 'walking_screen.dart';
import 'meditation_screen.dart';
import 'breathwork_screen.dart';

/// PurePlate (formerly "Diet & Water").
///
/// Three connected tabs instead of one long scroll:
///   Water  — hydration tracking + rich, condition-aware hydration commentary
///   Food   — meal logging, calories, context tips
///   Fitly  — movement plan: Sage suggestion card, starter templates, and a
///            fully custom plan (with water + calorie targets), all persisted
///            as targets other screens read from.
class PurePlateScreen extends StatefulWidget {
  const PurePlateScreen({super.key});

  @override
  State<PurePlateScreen> createState() => _PurePlateScreenState();
}

class _PurePlateScreenState extends State<PurePlateScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final BellaService _bella = BellaService();

  final TextEditingController _foodController = TextEditingController();
  final TextEditingController _caloriesController = TextEditingController();
  String _foodTag = 'balanced';

  // Whether the Sage Suggestion card in Fitly is expanded
  bool _sageSuggestionExpanded = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _foodController.dispose();
    _caloriesController.dispose();
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

  List<String> get _conditions =>
      UserService().currentUserObject?.chronicDiseases ?? [];

  // ── Sage suggestion computation ────────────────────────────────────────

  /// Computes a recommended daily water target (ml) with a specific reason.
  _SageSuggestionValue _suggestWater() {
    final bmi = _bmi;
    final conditions = _conditions;
    final weight = UserService().currentUserObject?.weight ?? 70.0;

    // Base: 35 ml per kg body weight
    int base = (weight * 35).round();

    String reason =
        'Your base target is calculated at 35 ml per kg of body weight '
        '(${weight.toStringAsFixed(0)} kg × 35 = $base ml), '
        'which reflects standard hydration science for your size.';

    if (conditions.contains('Chronic Kidney Disease')) {
      // CKD often requires fluid restriction — use a lower conservative target
      base = (weight * 25).round().clamp(1200, 1800);
      reason =
          'Chronic Kidney Disease limits how much fluid your kidneys can safely '
          'filter. Your target ($base ml/day) is intentionally lower than the '
          'general recommendation — always follow your nephrologist\'s guidance.';
    } else if (conditions.contains('Heart Disease')) {
      base = (weight * 30).round().clamp(1500, 2200);
      reason =
          'Heart Disease can make fluid management more sensitive. Your target '
          '($base ml/day) is slightly conservative to avoid unnecessary strain '
          'on your cardiovascular system while keeping you well-hydrated.';
    } else if (conditions.contains('Diabetes')) {
      base = (base + 300).clamp(2000, 3200);
      reason =
          'Diabetes raises your hydration needs: elevated blood glucose draws '
          'water from cells, and adequate hydration helps kidneys clear excess '
          'glucose. Your target ($base ml/day) adds 300 ml above baseline.';
    } else if (conditions.contains('Hypertension')) {
      base = base.clamp(2000, 2800);
      reason =
          'Staying well-hydrated supports healthy blood vessel tone and can '
          'moderately lower systolic pressure. Your target ($base ml/day) keeps '
          'you in the optimal range for blood pressure management.';
    } else if (conditions.contains('Asthma')) {
      base = (base + 200).clamp(2000, 3000);
      reason =
          'Asthma causes additional respiratory water loss and thicker mucus '
          'when you\'re dehydrated. An extra 200 ml/day ($base ml total) helps '
          'keep airways moist and mucus easier to clear.';
    } else if (conditions.contains('Arthritis')) {
      base = base.clamp(2000, 2800);
      reason =
          'Cartilage is ~80% water. Consistent hydration ($base ml/day) helps '
          'maintain joint lubrication and can reduce the stiffness common with '
          'Arthritis, especially in the morning.';
    } else if (bmi >= 30) {
      base = (base + 500).clamp(2500, 3500);
      reason =
          'With a BMI of ${bmi.toStringAsFixed(1)}, your metabolic rate and '
          'body surface area are higher, increasing water needs. Your target '
          '($base ml/day) accounts for this with an extra 500 ml above baseline.';
    } else if (bmi >= 25) {
      base = (base + 200).clamp(2200, 3000);
      reason =
          'Your BMI of ${bmi.toStringAsFixed(1)} puts you slightly above the '
          'healthy range. An extra 200 ml/day ($base ml total) supports your '
          'metabolism and can help manage appetite during weight management.';
    } else if (bmi < 18.5) {
      base = base.clamp(1800, 2500);
      reason =
          'For a BMI of ${bmi.toStringAsFixed(1)}, your hydration needs are '
          'modest. Your target ($base ml/day) is calibrated to your lighter '
          'body mass — don\'t over-hydrate, as it can dilute electrolytes.';
    }

    // Activity adjustment — walking already handled in _suggestCalories but
    // water loss is separate. Breathwork and meditation both involve sustained
    // controlled breathing that increases respiratory water loss. Small but real.
    final walkMin = _bella.sessionMinutesToday('walking');
    final medMin = _bella.sessionMinutesToday('meditation');
    final bwCount = _bella.sessionsToday('breathwork');

    int activityBonus = 0;
    final activityParts = <String>[];

    if (walkMin >= 20) {
      final bonus = walkMin >= 45 ? 400 : 200;
      activityBonus += bonus;
      activityParts.add('${walkMin}min walk (+${bonus}ml)');
    }
    if (medMin >= 10) {
      activityBonus += 100;
      activityParts.add('${medMin}min meditation (+100ml)');
    }
    if (bwCount > 0) {
      activityBonus += 100;
      activityParts.add('breathwork (+100ml)');
    }

    if (activityBonus > 0) {
      base += activityBonus;
      reason +=
          ' Today\'s activity increases your fluid needs: ${activityParts.join(', ')}. '
          'Updated target: ${base}ml.';
    }

    return _SageSuggestionValue(value: base, reason: reason);
  }

  /// Computes a recommended daily calorie target with a specific reason.
  _SageSuggestionValue _suggestCalories() {
    final bmi = _bmi;
    final conditions = _conditions;
    final user = UserService().currentUserObject;
    final weight = user?.weight ?? 70.0;
    final age = user?.age ?? 30;
    final isMale = (user?.gender ?? '').toLowerCase() == 'male';

    // Mifflin-St Jeor BMR, moderate activity (×1.4)
    final bmr = isMale
        ? (10 * weight + 6.25 * (user?.height ?? 170) - 5 * age + 5)
        : (10 * weight + 6.25 * (user?.height ?? 165) - 5 * age - 161);
    int base = (bmr * 1.4).round();

    // Adjust for actual activity logged today — walking burns roughly
    // 4–5 kcal/min at moderate pace; meditation/breathwork are negligible
    // for calories but confirm the 1.4 multiplier assumption is fair.
    final walkingMinToday = _bella.sessionMinutesToday('walking');
    if (walkingMinToday >= 20) {
      // Estimated additional burn beyond the 1.4 sedentary-adjusted baseline.
      // 1.4 assumes ~30 min light activity; anything above that adds extra.
      final extraMin = (walkingMinToday - 30).clamp(0, 120);
      final extraKcal = (extraMin * 4.5 * (weight / 70)).round();
      if (extraKcal > 0) base += extraKcal;
    }

    // Save the walking note now, before any condition block overwrites `reason`.
    // It will be appended to whichever condition reason wins below.
    final walkingNote = walkingMinToday >= 20
        ? ' Your $walkingMinToday-min walk today has been factored into this target.'
        : '';

    // Snapshot base BEFORE any condition adjusts it so reason strings can
    // reference the pre-reduction estimated need accurately (bug fix: previously
    // $base was already post-reduction when interpolated into the reason).
    final preConditionBase = base;

    String reason =
        'Your estimated daily need is $preConditionBase kcal, calculated from your body '
        'stats using the Mifflin-St Jeor formula at moderate activity (BMR × 1.4).$walkingNote';

    if (conditions.contains('Diabetes')) {
      // Slight deficit to improve insulin sensitivity, avoid very low
      base = (base - 200).clamp(1400, 2500);
      reason =
          'For Diabetes management, a modest 200 kcal reduction below your '
          'estimated need ($preConditionBase kcal/day) gives a target of $base kcal/day, '
          'which improves insulin sensitivity without causing hypoglycaemia. '
          'Distribute calories across 4–5 small meals.$walkingNote';
    } else if (conditions.contains('Heart Disease') ||
        conditions.contains('High Cholesterol')) {
      base = (base - 150).clamp(1400, 2500);
      reason =
          'For Heart Disease / High Cholesterol, a slight reduction from your '
          'estimated need ($preConditionBase kcal/day) to $base kcal/day reduces '
          'cardiovascular load. Quality matters more than quantity: '
          'prioritise fibre, omega-3s, and unsaturated fats over total calories.$walkingNote';
    } else if (conditions.contains('Hypertension')) {
      reason =
          'Your target of $base kcal/day is standard for your stats. The most '
          'impactful dietary change for Hypertension is sodium reduction '
          '(<2,300 mg/day) rather than calorie restriction.$walkingNote';
    } else if (bmi >= 30) {
      base = (base - 500).clamp(1200, 2200);
      reason =
          'A 500 kcal daily deficit from your estimated need ($preConditionBase kcal/day) '
          'gives a target of $base kcal/day — the clinically recommended rate for '
          '0.5 kg/week weight loss without metabolic slowdown at a BMI of '
          '${bmi.toStringAsFixed(1)}.$walkingNote';
    } else if (bmi >= 25) {
      base = (base - 300).clamp(1400, 2400);
      reason =
          'A 300 kcal deficit from your estimated need ($preConditionBase kcal/day) '
          'gives $base kcal/day — enough for gradual weight management (≈0.3 kg/week) '
          'at your BMI without feeling deprived.$walkingNote';
    } else if (bmi < 18.5) {
      base = (base + 400).clamp(1800, 3200);
      reason =
          'At a BMI of ${bmi.toStringAsFixed(1)}, you need a caloric surplus above '
          'your estimated need ($preConditionBase kcal/day). Your target of $base kcal/day '
          'adds 400 kcal to support reaching a healthy weight — focus on '
          'nutrient-dense whole foods.$walkingNote';
    }

    // When more than one condition would independently affect calorie
    // guidance, the chain above only applies the first match's logic.
    // Name the others here so the user understands the target accounts
    // for multiple conditions rather than just whichever came first.
    const calorieRelevant = [
      'Diabetes',
      'Heart Disease',
      'High Cholesterol',
      'Hypertension',
    ];
    final matched = conditions.where(calorieRelevant.contains).toList();
    if (matched.length > 1) {
      final others = matched.skip(1).join(' and ');
      reason +=
          ' You also have $others, which carries similar dietary guidance — '
          'this target and its sodium/fibre advice apply to both.';
    }

    return _SageSuggestionValue(value: base, reason: reason);
  }

  // ── Water actions ──────────────────────────────────────────────────────

  Future<void> _addWater(int ml) async {
    await _bella.addWater(ml);
    setState(() {});
  }

  Future<void> _removeWater(int ml) async {
    await _bella.removeWater(ml);
    setState(() {});
  }

  // ── Food actions ───────────────────────────────────────────────────────

  Future<void> _logFood() async {
    final text = _foodController.text.trim();
    if (text.isEmpty) return;
    final cal = int.tryParse(_caloriesController.text.trim());
    await _bella.addFood(FoodEntry(
      time: DateTime.now(),
      description: text,
      tag: _foodTag,
      calories: cal,
    ));
    _foodController.clear();
    _caloriesController.clear();
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: const Text('Logged'), backgroundColor: SageColors.moss),
    );
  }

  Future<void> _removeFood(FoodEntry entry) async {
    await _bella.removeFood(entry);
    setState(() {});
  }

  void _showEditFoodDialog(FoodEntry entry) {
    final descCtrl = TextEditingController(text: entry.description);
    final calCtrl =
        TextEditingController(text: entry.calories?.toString() ?? '');
    String tag = entry.tag ?? 'balanced';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: SageColors.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Edit entry',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: SageColors.ink,
                  fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: 'Food description',
                  filled: true,
                  fillColor: SageColors.linen,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: calCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Calories (optional)',
                  suffixText: 'kcal',
                  filled: true,
                  fillColor: SageColors.linen,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  _dlgTagChip('balanced', 'Balanced', tag,
                      (v) => setDlg(() => tag = v)),
                  _dlgTagChip('high-sodium', 'High sodium', tag,
                      (v) => setDlg(() => tag = v)),
                  _dlgTagChip('high-carb', 'High carb', tag,
                      (v) => setDlg(() => tag = v)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('Cancel', style: TextStyle(color: SageColors.inkSoft)),
            ),
            ElevatedButton(
              onPressed: () async {
                final newDesc = descCtrl.text.trim();
                if (newDesc.isEmpty) return;
                await _bella.editFood(
                  entry,
                  FoodEntry(
                    time: entry.time,
                    description: newDesc,
                    tag: tag,
                    calories: int.tryParse(calCtrl.text.trim()),
                  ),
                );
                if (!mounted) return;
                Navigator.pop(ctx);
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: SageColors.moss,
                  foregroundColor: SageColors.linen),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dlgTagChip(String value, String label, String current,
      ValueChanged<String> onSelect) {
    final selected = current == value;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: selected ? SageColors.linen : SageColors.ink)),
      selected: selected,
      selectedColor: SageColors.moss,
      backgroundColor: SageColors.linen,
      onSelected: (_) => onSelect(value),
    );
  }

  // ── Context tips (shared across tabs) ────────────────────────────────

  List<_ContextTip> _buildWaterTips(DietGuideline plan) {
    final tips = <_ContextTip>[];
    final sleepAvg = _bella.averageSleepQuality();
    if (sleepAvg != null && sleepAvg < 2.5) {
      tips.add(_ContextTip(
        icon: Icons.bedtime_outlined,
        color: SageColors.moss,
        text: 'Poor sleep this week often masks itself as thirst. Sip water '
            'steadily through the morning instead of large amounts late.',
      ));
    }
    final lastCheckin = _bella.lastCheckin;
    if (lastCheckin != null && lastCheckin.isLow) {
      tips.add(_ContextTip(
        icon: Icons.mood_outlined,
        color: SageColors.amber,
        text: 'Your last check-in showed low energy — mild dehydration is a '
            'common, easy-to-fix contributor. Keep sipping today.',
      ));
    }
    return tips;
  }

  List<_ContextTip> _buildFoodTips(DietGuideline plan) {
    final tips = <_ContextTip>[];

    final sleepAvg = _bella.averageSleepQuality();
    if (sleepAvg != null && sleepAvg < 2.5) {
      tips.add(_ContextTip(
        icon: Icons.bedtime_outlined,
        color: SageColors.moss,
        text:
            'Your sleep has been poor this week. Avoiding caffeine after 2 pm '
            'and heavy meals within 3 h of bedtime can help.',
      ));
    }

    final lastCheckin = _bella.lastCheckin;
    if (lastCheckin != null && lastCheckin.isLow) {
      tips.add(_ContextTip(
        icon: Icons.mood_outlined,
        color: SageColors.amber,
        text:
            'Your last check-in showed low energy. Complex carbs at breakfast '
            'and steady hydration can support your mood today.',
      ));
    }

    for (final cond in _conditions) {
      final readings = _bella.getReadings(condition: cond);
      if (readings.isNotEmpty) {
        final r = readings.first;
        final bool flagged;
        final String advice;
        switch (cond) {
          case 'Diabetes':
            flagged = r.value < 70 || r.value > 180;
            advice = 'Your last glucose reading was out of range. '
                '${plan.carbGuidance ?? "Keep carbs consistent today."}';
          case 'Hypertension':
          case 'Heart Disease':
          case 'Chronic Kidney Disease':
            flagged = r.value >= 140 || (r.secondaryValue ?? 0) >= 90;
            advice = 'Your last blood pressure reading was elevated. '
                '${plan.sodiumLimit ?? "Avoid high-sodium foods today."}';
          case 'Arthritis':
            flagged = r.value >= 6;
            advice = 'Pain level logged at ${r.value.toStringAsFixed(0)}/10 — '
                'anti-inflammatory foods (turmeric, ginger, berries, olive oil) '
                'may help reduce joint inflammation today.';
          case 'Asthma':
            flagged = r.value < 300;
            advice = 'Low peak flow reading — stay well-hydrated and avoid '
                'dairy-heavy meals today, which can thicken mucus.';
          case 'High Cholesterol':
            flagged = r.value > 240;
            advice = 'Cholesterol reading is elevated. Focus on soluble fibre '
                '(oats, apples, lentils) and avoid saturated fats today.';
          case 'Thyroid Disorder':
            flagged = r.value > 120 || r.value < 40;
            advice = 'Your logged weight is outside the typical range for your '
                'profile — keep meals nutrient-dense and consistent.';
          default:
            flagged = false;
            advice = '';
        }
        if (flagged && advice.isNotEmpty) {
          tips.add(_ContextTip(
              icon: Icons.monitor_heart_outlined,
              color: SageColors.clay,
              text: advice));
        }
      }
    }

    final totalCal = _bella
        .getFoodEntries(onDate: DateTime.now())
        .fold<int>(0, (s, f) => s + (f.calories ?? 0));
    if (totalCal > 0) {
      final target =
          _bella.getTarget<int>('calorieTarget') ?? _suggestCalories().value;
      if (totalCal > target) {
        tips.add(_ContextTip(
          icon: Icons.local_fire_department_outlined,
          color: SageColors.clay,
          text:
              'You\'ve logged $totalCal kcal today — over your rough target of '
              '$target kcal. Consider a lighter dinner.',
        ));
      }
    }

    return tips;
  }

  List<_ContextTip> _buildFitlyTips() {
    final tips = <_ContextTip>[];
    final foodToday = _bella.getFoodEntries(onDate: DateTime.now());
    final hasHighSodium = foodToday.any((f) => f.tag == 'high-sodium');
    if (hasHighSodium &&
        (_conditions.contains('Hypertension') ||
            _conditions.contains('Heart Disease'))) {
      tips.add(_ContextTip(
        icon: Icons.restaurant_outlined,
        color: SageColors.clay,
        text: 'You logged a high-sodium meal today — a brisk walk can help '
            'offset some of the blood-pressure impact.',
      ));
    }
    final waterToday = _bella.todayWaterMl();
    if (waterToday < 500) {
      tips.add(_ContextTip(
        icon: Icons.water_drop_outlined,
        color: SageColors.sage,
        text: 'Low on water so far today — hydrate before a workout to avoid '
            'cramping and fatigue.',
      ));
    }
    return tips;
  }

  // ── Custom Fitly plan commentary ─────────────────────────────────────
  //
  // Evaluates the user's saved custom plan targets against their BMI, age,
  // and chronic conditions and returns a list of feedback items.

  List<_PlanFeedback> _buildCustomPlanFeedback(Map<String, dynamic> targets) {
    final bmi = _bmi;
    final conditions = _conditions;
    final user = UserService().currentUserObject;
    final age = user?.age ?? 30;
    final feedback = <_PlanFeedback>[];

    final int steps = (targets['steps'] as num?)?.toInt() ?? 0;
    final int walkMin = (targets['walkMinutes'] as num?)?.toInt() ?? 0;
    final int medMin = (targets['meditationMinutes'] as num?)?.toInt() ?? 0;
    final int breathSessions =
        (targets['breathworkSessions'] as num?)?.toInt() ?? 0;
    final int waterMl = (targets['waterMl'] as num?)?.toInt() ?? 0;
    final int calTarget = (targets['calorieTarget'] as num?)?.toInt() ?? 0;

    // ── Steps ────────────────────────────────────────────────────────────
    if (steps > 0) {
      if (conditions.contains('Arthritis') && steps > 7000) {
        feedback.add(_PlanFeedback(
          icon: Icons.directions_walk,
          color: SageColors.amber,
          severity: _FeedbackSeverity.warning,
          title: 'Steps target may be high for Arthritis',
          body:
              'You set $steps steps/day. With Arthritis, high-impact walking can aggravate joints. '
              'Consider 4,000–6,000 steps on gentle, flat terrain and listen to your body.',
        ));
      } else if ((conditions.contains('Heart Disease') ||
              conditions.contains('Hypertension')) &&
          steps > 8000) {
        feedback.add(_PlanFeedback(
          icon: Icons.directions_walk,
          color: SageColors.amber,
          severity: _FeedbackSeverity.warning,
          title: 'Steps target: start conservatively',
          body:
              'Your target of $steps steps/day is ambitious with ${conditions.contains('Heart Disease') ? 'Heart Disease' : 'Hypertension'}. '
              'A safer start is 5,000–6,000 steps, increasing by 500/week as tolerated.',
        ));
      } else if (bmi >= 30 && steps < 6000) {
        feedback.add(_PlanFeedback(
          icon: Icons.directions_walk,
          color: SageColors.clay,
          severity: _FeedbackSeverity.low,
          title: 'Steps target could be higher',
          body:
              'At a BMI of ${bmi.toStringAsFixed(1)}, at least 6,000–8,000 steps/day '
              'is recommended to support weight loss. Your target of $steps may not be enough '
              'to create a meaningful activity deficit.',
        ));
      } else if (steps >= 8000 &&
          bmi < 25 &&
          !conditions.any((c) =>
              ['Heart Disease', 'Hypertension', 'Arthritis'].contains(c))) {
        feedback.add(_PlanFeedback(
          icon: Icons.directions_walk,
          color: SageColors.moss,
          severity: _FeedbackSeverity.good,
          title: 'Great step target',
          body:
              '$steps steps/day is excellent for your profile. This level of daily movement '
              'supports cardiovascular health, metabolic rate, and mental wellbeing.',
        ));
      }

      if (age >= 60 && steps > 9000) {
        feedback.add(_PlanFeedback(
          icon: Icons.elderly_outlined,
          color: SageColors.amber,
          severity: _FeedbackSeverity.warning,
          title: 'Consider your age when setting steps',
          body:
              'At age $age, $steps steps/day is achievable but can increase fall risk if done too fast. '
              'Aim for 7,000–9,000 and prioritise balance exercises alongside walking.',
        ));
      }
    }

    // ── Walking minutes ───────────────────────────────────────────────────
    if (walkMin > 0) {
      if (walkMin < 20 && bmi >= 25) {
        feedback.add(_PlanFeedback(
          icon: Icons.timer_outlined,
          color: SageColors.clay,
          severity: _FeedbackSeverity.low,
          title: 'Walking duration is short for weight management',
          body:
              'You set $walkMin min/day. For meaningful calorie burn at a BMI of ${bmi.toStringAsFixed(1)}, '
              '25–45 min of brisk walking is more effective. Even 5 extra minutes helps.',
        ));
      } else if (walkMin >= 30 && walkMin <= 60) {
        feedback.add(_PlanFeedback(
          icon: Icons.timer_outlined,
          color: SageColors.moss,
          severity: _FeedbackSeverity.good,
          title: 'Walking duration is well set',
          body:
              '$walkMin min/day of brisk walking meets WHO guidelines for moderate aerobic activity '
              'and supports heart, joint, and metabolic health.',
        ));
      } else if (walkMin > 90) {
        feedback.add(_PlanFeedback(
          icon: Icons.timer_outlined,
          color: SageColors.amber,
          severity: _FeedbackSeverity.warning,
          title: 'Very long walking target',
          body:
              '$walkMin min/day is a high target. While more movement is generally good, '
              'excessive walking without recovery can cause overuse injuries — '
              'especially if you\'re just starting out.',
        ));
      }
    }

    // ── Meditation ────────────────────────────────────────────────────────
    if (medMin > 0) {
      if (conditions.contains('Hypertension') && medMin < 10) {
        feedback.add(_PlanFeedback(
          icon: Icons.self_improvement,
          color: SageColors.amber,
          severity: _FeedbackSeverity.low,
          title: 'Meditation too brief for Hypertension',
          body:
              'Studies show ≥15 min/day of mindfulness meditation produces meaningful reductions '
              'in blood pressure. Your target of $medMin min may not be enough to see that benefit.',
        ));
      } else if (conditions.contains('Diabetes') && medMin < 10) {
        feedback.add(_PlanFeedback(
          icon: Icons.self_improvement,
          color: SageColors.amber,
          severity: _FeedbackSeverity.low,
          title: 'Consider more meditation for Diabetes',
          body:
              'Stress directly raises blood glucose via cortisol. Even 10 min/day '
              'of meditation helps stabilise HbA1c over time. You set $medMin min — '
              'try increasing to at least 10.',
        ));
      } else if (medMin >= 10) {
        feedback.add(_PlanFeedback(
          icon: Icons.self_improvement,
          color: SageColors.moss,
          severity: _FeedbackSeverity.good,
          title: 'Solid meditation goal',
          body:
              '$medMin min/day of daily meditation is consistent with evidence for reducing '
              'stress, improving sleep quality, and supporting emotional resilience.',
        ));
      }
    }

    // ── Breathwork ────────────────────────────────────────────────────────
    if (breathSessions > 0) {
      if ((conditions.contains('Hypertension') ||
              conditions.contains('Heart Disease')) &&
          breathSessions < 2) {
        feedback.add(_PlanFeedback(
          icon: Icons.air,
          color: SageColors.amber,
          severity: _FeedbackSeverity.low,
          title: 'More breathwork sessions recommended',
          body:
              'For ${conditions.contains('Hypertension') ? 'Hypertension' : 'Heart Disease'}, '
              '2 breathwork sessions/day (morning + evening) are more effective at lowering '
              'resting heart rate and blood pressure than a single session.',
        ));
      } else if (conditions.contains('Asthma') && breathSessions < 2) {
        feedback.add(_PlanFeedback(
          icon: Icons.air,
          color: SageColors.amber,
          severity: _FeedbackSeverity.low,
          title: 'Consider 2 breathwork sessions for Asthma',
          body:
              'Twice-daily breathwork (morning to start the day, evening to unwind) '
              'strengthens respiratory muscles and reduces Asthma trigger sensitivity '
              'more effectively than a single daily session.',
        ));
      }
    }

    // ── Water target ──────────────────────────────────────────────────────
    if (waterMl > 0) {
      final suggested = _suggestWater().value;
      final diff = waterMl - suggested;
      if (conditions.contains('Chronic Kidney Disease') && waterMl > 1800) {
        feedback.add(_PlanFeedback(
          icon: Icons.water_drop_outlined,
          color: SageColors.clay,
          severity: _FeedbackSeverity.warning,
          title: 'Water target may be too high for CKD',
          body:
              'You set $waterMl ml/day. With Chronic Kidney Disease, excess fluid '
              'strains the kidneys. The safe range is typically 1,200–1,800 ml/day — '
              'always confirm with your nephrologist.',
        ));
      } else if (diff < -600 &&
          !conditions.contains('Chronic Kidney Disease')) {
        feedback.add(_PlanFeedback(
          icon: Icons.water_drop_outlined,
          color: SageColors.amber,
          severity: _FeedbackSeverity.low,
          title: 'Water target seems low',
          body:
              'You set $waterMl ml/day, but based on your weight, BMI, and conditions, '
              '$suggested ml is recommended. Under-hydration affects energy, '
              'digestion, and (for Diabetes) glucose clearance.',
        ));
      } else if (diff >= -300 && diff <= 400) {
        feedback.add(_PlanFeedback(
          icon: Icons.water_drop_outlined,
          color: SageColors.moss,
          severity: _FeedbackSeverity.good,
          title: 'Water target is well calibrated',
          body:
              'Your $waterMl ml/day target is close to the $suggested ml Sage calculates '
              'for your profile. Good hydration underpins every other goal here.',
        ));
      }
    }

    // ── Calorie target ────────────────────────────────────────────────────
    if (calTarget > 0) {
      final suggested = _suggestCalories().value;
      final bmiCat = _bmiCategory(bmi);

      if (conditions.contains('Diabetes') && calTarget > suggested + 300) {
        feedback.add(_PlanFeedback(
          icon: Icons.local_fire_department_outlined,
          color: SageColors.clay,
          severity: _FeedbackSeverity.warning,
          title: 'Calorie target high for Diabetes management',
          body:
              'You set $calTarget kcal/day. With Diabetes, a surplus above your estimated '
              'need worsens insulin resistance over time. Consider closer to $suggested kcal '
              'and distribute across 4–5 smaller meals.',
        ));
      } else if (bmi >= 30 && calTarget > suggested + 200) {
        feedback.add(_PlanFeedback(
          icon: Icons.local_fire_department_outlined,
          color: SageColors.amber,
          severity: _FeedbackSeverity.warning,
          title: 'Calorie target above recommended for your BMI',
          body:
              'At a BMI of ${bmi.toStringAsFixed(1)} ($bmiCat), your target of $calTarget kcal '
              'exceeds the recommended deficit target of $suggested kcal. '
              'A 500 kcal daily deficit from maintenance supports ~0.5 kg/week loss.',
        ));
      } else if (bmi < 18.5 && calTarget < suggested - 200) {
        feedback.add(_PlanFeedback(
          icon: Icons.local_fire_department_outlined,
          color: SageColors.clay,
          severity: _FeedbackSeverity.warning,
          title: 'Calorie target too low for your weight',
          body:
              'At a BMI of ${bmi.toStringAsFixed(1)} (Underweight), you need a caloric surplus '
              'to reach a healthy weight. Your target of $calTarget kcal is below the recommended '
              '$suggested kcal. Eating too little slows recovery and metabolism.',
        ));
      } else if (calTarget < 1200) {
        feedback.add(_PlanFeedback(
          icon: Icons.local_fire_department_outlined,
          color: SageColors.clay,
          severity: _FeedbackSeverity.warning,
          title: 'Calorie target is dangerously low',
          body:
              'You set $calTarget kcal/day. Anything below 1,200 kcal (women) or 1,500 kcal (men) '
              'risks nutrient deficiencies, muscle loss, and metabolic slowdown — '
              'regardless of weight goals.',
        ));
      } else if ((calTarget - suggested).abs() <= 250) {
        feedback.add(_PlanFeedback(
          icon: Icons.local_fire_department_outlined,
          color: SageColors.moss,
          severity: _FeedbackSeverity.good,
          title: 'Calorie target looks good',
          body:
              'Your $calTarget kcal/day is well aligned with the $suggested kcal Sage recommends '
              'for your BMI${conditions.isNotEmpty ? ", age ($age), and conditions" : " and age ($age)"}. '
              'Stick to it consistently for the best results.',
        ));
      }

      if (age >= 60 && calTarget < 1500) {
        feedback.add(_PlanFeedback(
          icon: Icons.elderly_outlined,
          color: SageColors.amber,
          severity: _FeedbackSeverity.warning,
          title: 'Low calorie target for your age',
          body:
              'At age $age, adequate protein and calories are critical to prevent muscle loss '
              '(sarcopenia). Going below 1,500 kcal/day makes it harder to meet protein '
              'requirements — consider at least 1,600–1,800 kcal with high protein density.',
        ));
      }
    }

    // ── Overall balance check ─────────────────────────────────────────────
    if (steps > 0 && calTarget > 0) {
      // Rough estimated burn: steps × 0.04 kcal (average 70 kg person)
      final weight = user?.weight ?? 70.0;
      final estimatedBurn = (steps * 0.04 * (weight / 70)).round();
      final suggested = _suggestCalories().value;
      // If calorie target + estimated step burn still below BMR proxy
      final bmrProxy = (suggested * 0.7).round();
      if (calTarget - estimatedBurn < bmrProxy && bmi >= 25) {
        feedback.add(_PlanFeedback(
          icon: Icons.balance_outlined,
          color: SageColors.amber,
          severity: _FeedbackSeverity.warning,
          title: 'Activity vs. calories may be imbalanced',
          body:
              'Your step goal burns roughly $estimatedBurn kcal/day. Combined with your '
              '$calTarget kcal intake target, net calories could fall too low for sustained energy. '
              'Make sure you\'re fuelling your activity adequately.',
        ));
      }
    }

    return feedback;
  }

  // ── Water commentary ──────────────────────────────────────────────────

  /// Returns a rich, condition-aware comment about hydration progress.
  /// Returns null only if there is genuinely nothing useful to say.
  _WaterComment? _waterComment(int todayMl, int targetMl) {
    final conditions = _conditions;
    final bmi = _bmi;
    final ratio = targetMl > 0 ? todayMl / targetMl : 0.0;
    final remaining = targetMl - todayMl;

    // ── 0 ml logged ──────────────────────────────────────────────────────
    if (todayMl == 0) {
      if (conditions.contains('Diabetes')) {
        return _WaterComment(
          icon: Icons.water_drop_outlined,
          color: SageColors.amber,
          text: 'No water logged yet today. For Diabetes management, '
              'starting your morning with a large glass of water (300–500 ml) '
              'helps your kidneys clear overnight glucose and reduces morning '
              'blood sugar spikes.',
        );
      }
      if (conditions.contains('Hypertension')) {
        return _WaterComment(
          icon: Icons.water_drop_outlined,
          color: SageColors.amber,
          text: 'No water logged yet. Dehydration raises blood viscosity '
              'and can cause a temporary spike in blood pressure. Start '
              'your day with at least 300 ml to get ahead of it.',
        );
      }
      if (conditions.contains('Chronic Kidney Disease')) {
        return _WaterComment(
          icon: Icons.water_drop_outlined,
          color: SageColors.clay,
          text: 'No water logged yet. With CKD your fluid target is carefully '
              'calibrated — spread your ${targetMl}ml evenly across the day '
              'rather than drinking large amounts at once.',
        );
      }
      if (conditions.contains('Asthma')) {
        return _WaterComment(
          icon: Icons.water_drop_outlined,
          color: SageColors.amber,
          text: 'No water logged yet. Airway mucus thickens when you\'re '
              'dehydrated, which can worsen Asthma symptoms. Starting the '
              'day hydrated keeps airways clear.',
        );
      }
      if (bmi >= 25) {
        return _WaterComment(
          icon: Icons.water_drop_outlined,
          color: SageColors.amber,
          text: 'No water logged yet. Drinking water before meals reduces '
              'appetite and boosts metabolism — a simple daily habit that '
              'supports weight management alongside your calorie target.',
        );
      }
      return _WaterComment(
        icon: Icons.water_drop_outlined,
        color: SageColors.amber,
        text: 'No water logged yet today. Your body wakes up slightly '
            'dehydrated after 7–8 hours of sleep. Drink 300–500 ml in '
            'the first hour to kickstart energy and focus.',
      );
    }

    // ── 1–25% ────────────────────────────────────────────────────────────
    if (ratio < 0.25) {
      if (conditions.contains('Diabetes')) {
        return _WaterComment(
          icon: Icons.local_drink_outlined,
          color: SageColors.amber,
          text: 'Good start — $todayMl ml logged. Aim to reach '
              '${(targetMl * 0.5).round()} ml by midday. '
              'Consistent hydration through the day helps maintain stable '
              'blood glucose levels.',
        );
      }
      if (conditions.contains('Heart Disease') ||
          conditions.contains('Hypertension')) {
        return _WaterComment(
          icon: Icons.local_drink_outlined,
          color: SageColors.amber,
          text: 'Off to a start — $todayMl ml in. Try to pace yourself: '
              'aim for ${(targetMl / 4).round()} ml every few hours '
              'rather than large amounts at once to support healthy '
              'cardiovascular function.',
        );
      }
      return _WaterComment(
        icon: Icons.local_drink_outlined,
        color: SageColors.amber,
        text: 'Off to a start — $todayMl ml logged. You still need '
            '$remaining ml to hit your target. Setting a reminder every '
            '90 minutes is the single best habit to close the gap.',
      );
    }

    // ── 25–50% ───────────────────────────────────────────────────────────
    if (ratio < 0.5) {
      if (conditions.contains('Arthritis')) {
        return _WaterComment(
          icon: Icons.local_drink_outlined,
          color: SageColors.moss,
          text:
              'You\'re at ${(ratio * 100).round()}% of your goal ($todayMl ml). '
              'Well done — consistent hydration lubricates cartilage and '
              'reduces the joint stiffness that\'s common at this stage of '
              'the day. Keep going.',
        );
      }
      if (bmi >= 25) {
        return _WaterComment(
          icon: Icons.local_drink_outlined,
          color: SageColors.moss,
          text: 'Quarter-way there — $todayMl ml logged. '
              'Try drinking a glass 20–30 minutes before your next meal: '
              'research shows it reduces meal size by up to 13%, '
              'supporting your weight goals.',
        );
      }
      return _WaterComment(
        icon: Icons.local_drink_outlined,
        color: SageColors.moss,
        text: 'Making progress — $todayMl ml in, $remaining ml to go. '
            'If you\'re feeling hungry between meals, try a glass of '
            'water first — the thirst signal is often mistaken for hunger.',
      );
    }

    // ── 50–75% ───────────────────────────────────────────────────────────
    if (ratio < 0.75) {
      if (conditions.contains('Diabetes')) {
        return _WaterComment(
          icon: Icons.check_circle_outline,
          color: SageColors.moss,
          text: 'Halfway there — $todayMl / $targetMl ml. '
              'Great consistency. Staying hydrated in this range helps '
              'your kidneys filter excess glucose efficiently. '
              'Keep a glass within sight for the second half of the day.',
        );
      }
      if (conditions.contains('Asthma')) {
        return _WaterComment(
          icon: Icons.check_circle_outline,
          color: SageColors.moss,
          text: 'Past halfway — $todayMl ml logged. '
              'Well-hydrated airways are less reactive to triggers. '
              'If you exercise later, drink an extra 200 ml beforehand '
              'to keep airways moist during exertion.',
        );
      }
      return _WaterComment(
        icon: Icons.check_circle_outline,
        color: SageColors.moss,
        text: 'Past halfway — $todayMl ml, $remaining ml to go. '
            'You\'re doing well. Your skin, kidneys, and digestion are '
            'already benefiting. Keep the same pace through the afternoon.',
      );
    }

    // ── 75–99% ───────────────────────────────────────────────────────────
    if (ratio < 1.0) {
      if (conditions.contains('Chronic Kidney Disease')) {
        return _WaterComment(
          icon: Icons.check_circle_outline,
          color: SageColors.moss,
          text: 'Almost at your target — $todayMl / $targetMl ml. '
              'With CKD, finishing your prescribed amount (but not '
              'exceeding it significantly) is exactly right. '
              'Almost there — just $remaining ml left.',
        );
      }
      return _WaterComment(
        icon: Icons.check_circle_outline,
        color: SageColors.moss,
        text: 'Almost there — just $remaining ml left to hit your '
            '$targetMl ml target. At this level your body is running '
            'well-hydrated: energy, concentration, and digestion all '
            'benefit. Finish strong.',
      );
    }

    // ── 100%+ ────────────────────────────────────────────────────────────
    if (conditions.contains('Chronic Kidney Disease')) {
      return _WaterComment(
        icon: Icons.water_drop,
        color: SageColors.sage,
        text: 'Daily target reached — $todayMl ml. With CKD, try '
            'not to go significantly over $targetMl ml today unless '
            'your doctor has advised otherwise. Well done.',
      );
    }
    if (conditions.contains('Heart Disease')) {
      return _WaterComment(
        icon: Icons.water_drop,
        color: SageColors.sage,
        text: 'Target reached — $todayMl ml! Great work. With Heart Disease, '
            'going moderately over your fluid target is generally fine '
            'unless you\'ve been advised to restrict fluids by your cardiologist.',
      );
    }
    if (ratio >= 1.5) {
      return _WaterComment(
        icon: Icons.info_outline,
        color: SageColors.inkSoft,
        text:
            'You\'ve logged $todayMl ml — well over your ${targetMl}ml target. '
            'While staying hydrated is good, drinking excessively '
            'can dilute electrolytes. Unless it\'s very hot or you\'ve '
            'exercised intensely, you can ease off for the rest of the day.',
      );
    }
    return _WaterComment(
      icon: Icons.water_drop,
      color: SageColors.sage,
      text: 'Daily target hit — $todayMl ml! Your body is well-hydrated. '
          'Every cell, organ, and joint is benefiting. If it\'s been '
          'a particularly hot or active day, a little more is fine.',
    );
  }

  // ── Calorie commentary ────────────────────────────────────────────────
  //
  // Considers total calories, meal count, calorie distribution, BMI, age,
  // and chronic conditions for a rich, contextual comment.

  String? _calorieComment(int totalCal, int target) {
    if (totalCal == 0) return null;
    final conditions = _conditions;
    final bmi = _bmi;
    final user = UserService().currentUserObject;
    final age = user?.age ?? 30;
    final ratio = totalCal / target;
    final foodToday = _bella.getFoodEntries(onDate: DateTime.now());
    final mealCount = foodToday.length;
    final entriesWithCals = foodToday.where((f) => f.calories != null).toList();

    // Meal distribution note
    String mealNote = '';
    if (mealCount >= 2 && entriesWithCals.length >= 2) {
      final maxMealCal = entriesWithCals
          .map((f) => f.calories!)
          .reduce((a, b) => a > b ? a : b);
      final dominates = maxMealCal > totalCal * 0.6;
      if (dominates) {
        mealNote =
            ' One meal accounts for over 60% of your intake — spreading calories more evenly across $mealCount meals helps avoid energy crashes and glucose spikes.';
      } else if (conditions.contains('Diabetes') &&
          mealCount < 4 &&
          ratio > 0.7) {
        mealNote =
            ' With $mealCount meals so far, try splitting remaining intake into smaller portions — frequent small meals stabilise blood glucose better.';
      }
    } else if (mealCount == 1 && ratio > 0.4) {
      mealNote =
          ' Youve only logged 1 meal — spreading calories across 3–4 meals supports steadier energy.';
    }

    // Age-specific note
    String ageNote = '';
    if (age >= 60 && ratio < 0.6) {
      ageNote =
          ' At age $age, under-eating raises the risk of muscle loss — prioritise protein-rich meals.';
    } else if (age < 25 && ratio < 0.5) {
      ageNote =
          ' Young adults need sufficient calories for growth and repair — dont skip meals.';
    }

    final mealSuffix = '$mealCount meal${mealCount != 1 ? "s" : ""}';
    if (ratio < 0.5) {
      if (conditions.contains('Diabetes')) {
        return 'Very low calories today ($totalCal / $target kcal, $mealSuffix) — skipping meals can cause blood glucose to drop dangerously.$mealNote Eat small, balanced meals regularly.';
      }
      if (bmi < 18.5) {
        return 'You are underweight and eating well under your target ($totalCal kcal, $mealSuffix). Not fuelling enough slows metabolism and worsens fatigue.$ageNote';
      }
      return 'You are at \${(ratio * 100).round()}% of your daily target ($mealSuffix). Make sure you are eating enough to support your energy and recovery.$mealNote$ageNote';
    }
    if (ratio <= 1.0) {
      if (conditions.contains('Diabetes')) {
        return 'Good balance — $totalCal / $target kcal, $mealSuffix.$mealNote Keep meals spaced evenly to avoid glucose spikes.';
      }
      if (conditions.contains('Hypertension') ||
          conditions.contains('Heart Disease')) {
        return 'On track — $totalCal / $target kcal, $mealSuffix.$mealNote Focus on low-sodium, fibre-rich choices to support heart health.';
      }
      if (bmi >= 25) {
        return 'On track — $totalCal / $target kcal, $mealSuffix.$mealNote Consistent days like this support steady progress at BMI \${bmi.toStringAsFixed(1)}.';
      }
      return 'On track — $totalCal / $target kcal, $mealSuffix. Well done keeping it balanced.$mealNote$ageNote';
    }
    if (ratio <= 1.2) {
      if (conditions.contains('Diabetes')) {
        return 'Slightly over target ($totalCal / $target kcal, $mealSuffix). Extra carbs can raise fasting glucose overnight.$mealNote Consider a light, low-carb dinner.';
      }
      if (bmi >= 25) {
        return 'A little over target ($totalCal / $target kcal, $mealSuffix). At BMI \${bmi.toStringAsFixed(1)}, staying within $target kcal consistently supports gradual weight loss.$mealNote';
      }
      return 'Slightly over target ($totalCal / $target kcal, $mealSuffix) — not a problem if it happens occasionally.$mealNote';
    }
    // >120% of target
    if (conditions.contains('Diabetes')) {
      return 'Significantly over target ($totalCal kcal vs $target, $mealSuffix). High intake worsens insulin resistance.$mealNote A light walk after eating helps lower the glucose spike.';
    }
    if (conditions.contains('High Cholesterol') ||
        conditions.contains('Heart Disease')) {
      return 'Over target by \${totalCal - target} kcal ($mealSuffix). Excess calories convert to triglycerides, worsening cholesterol and cardiovascular risk.$mealNote';
    }
    if (bmi >= 30) {
      return 'Over target by \${totalCal - target} kcal ($mealSuffix). Consistent over-eating stresses joints and makes weight management harder.$mealNote Try a 20-min walk to offset some of the surplus.';
    }
    return 'Over your daily target ($totalCal kcal, $mealSuffix).$mealNote$ageNote Your body will store the excess — try lighter snacks tomorrow.';
  }

  // ── Rich diet plan ────────────────────────────────────────────────────

  List<_DietRich> _buildRichDietPlan() {
    final bmi = _bmi;
    final conditions = _conditions;
    final items = <_DietRich>[];

    items.add(_DietRich(
        icon: Icons.grain,
        color: SageColors.moss,
        label: 'Leafy greens & fibre',
        detail:
            'Spinach, kale, lentils, oats — slow digestion, reduce inflammation, and support heart health.'));
    items.add(_DietRich(
        icon: Icons.opacity,
        color: SageColors.sage,
        label: 'Hydration',
        detail:
            'Aim for ${_bella.getTargets()['waterMl'] ?? 2000} ml/day. Dehydration worsens fatigue, raises blood pressure, and impairs glucose control.'));

    if (conditions.contains('Diabetes')) {
      items.add(_DietRich(
          icon: Icons.science_outlined,
          color: SageColors.amber,
          label: 'Low-glycaemic carbs',
          detail:
              'Whole grains, sweet potato, legumes. Avoid white bread, sugary drinks, and processed cereals.'));
      items.add(_DietRich(
          icon: Icons.egg_alt_outlined,
          color: SageColors.moss,
          label: 'Lean protein at every meal',
          detail:
              'Chicken, fish, tofu, eggs. Protein slows glucose absorption and keeps you full longer.'));
    }
    if (conditions.contains('Hypertension') ||
        conditions.contains('Heart Disease')) {
      items.add(_DietRich(
          icon: Icons.monitor_heart_outlined,
          color: SageColors.clay,
          label: 'Potassium-rich foods',
          detail:
              'Bananas, avocado, sweet potato, white beans — potassium counteracts sodium and relaxes blood vessel walls.'));
      items.add(_DietRich(
          icon: Icons.set_meal_outlined,
          color: SageColors.sage,
          label: 'Omega-3 fatty acids',
          detail:
              'Salmon, walnuts, flaxseeds — reduce triglycerides and blood pressure.'));
    }
    if (conditions.contains('High Cholesterol')) {
      items.add(_DietRich(
          icon: Icons.fiber_smart_record,
          color: SageColors.moss,
          label: 'Soluble fibre',
          detail:
              'Oatmeal, apples, barley, psyllium — binds to cholesterol in the gut and removes it before absorption.'));
    }
    if (conditions.contains('Arthritis')) {
      items.add(_DietRich(
          icon: Icons.local_fire_department_outlined,
          color: SageColors.clay,
          label: 'Anti-inflammatory foods',
          detail:
              'Turmeric, ginger, berries, olive oil — reduce prostaglandins that drive joint inflammation.'));
    }
    if (conditions.contains('Asthma')) {
      items.add(_DietRich(
          icon: Icons.air,
          color: SageColors.sage,
          label: 'Antioxidant-rich foods',
          detail:
              'Vitamin C (citrus, peppers) and Vitamin E (nuts, seeds) reduce airway inflammation.'));
    }
    if (conditions.contains('Chronic Kidney Disease')) {
      items.add(_DietRich(
          icon: Icons.opacity,
          color: SageColors.amber,
          label: 'Low potassium & phosphorus',
          detail:
              'Limit bananas, oranges, dairy, and dark colas. Kidneys struggle to filter excess electrolytes.'));
    }
    if (bmi >= 25) {
      items.add(_DietRich(
          icon: Icons.restaurant_outlined,
          color: SageColors.amber,
          label: 'Portion control & calorie awareness',
          detail:
              'A 300–500 kcal daily deficit through food choices leads to sustainable weight loss without metabolic stress.'));
    }
    if (bmi < 18.5) {
      items.add(_DietRich(
          icon: Icons.add_circle_outline,
          color: SageColors.moss,
          label: 'Calorie-dense whole foods',
          detail:
              'Nuts, avocado, full-fat dairy, whole grains — add healthy calories without excessive volume.'));
    }

    return items;
  }

  // ── Fitly: workout suggestions ────────────────────────────────────────

  List<_WorkoutSuggestion> _buildWorkoutPlan() {
    final bmi = _bmi;
    final conditions = _conditions;
    final suggestions = <_WorkoutSuggestion>[];

    int stepTarget = 10000;
    int walkMinTarget = 30;
    String walkNote =
        'Helps maintain a healthy weight and cardiovascular fitness.';
    if (bmi >= 30 ||
        conditions.contains('Heart Disease') ||
        conditions.contains('Hypertension')) {
      stepTarget = 6000;
      walkMinTarget = 20;
      walkNote =
          'Start with gentle walking — $walkMinTarget min daily lowers blood pressure and improves heart health.';
    } else if (bmi >= 25) {
      stepTarget = 8000;
      walkMinTarget = 25;
      walkNote =
          'Walking $walkMinTarget min/day burns around 100–150 kcal and supports weight management.';
    } else if (bmi < 18.5) {
      stepTarget = 7000;
      walkMinTarget = 20;
      walkNote =
          'Light daily walking maintains cardiovascular health without burning too many calories.';
    }
    if (conditions.contains('Arthritis')) {
      stepTarget = 5000;
      walkMinTarget = 15;
      walkNote =
          'Short, flat walks reduce joint stiffness in arthritis without overloading.';
    }
    suggestions.add(_WorkoutSuggestion(
      icon: Icons.directions_walk,
      color: SageColors.amber,
      title: 'Walking',
      description: walkNote,
      targetLabel: '$stepTarget steps / $walkMinTarget min',
      targetKey: 'steps',
      targetValue: stepTarget,
      secondaryKey: 'walkMinutes',
      secondaryValue: walkMinTarget,
      onGo: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(
              builder: (_) =>
                  WalkingScreen(initialHeartRate: 72, initialSteps: 0))),
    ));

    int meditationMin = 10;
    String meditationNote =
        'Daily meditation reduces cortisol and improves emotional resilience.';
    if (conditions.contains('Hypertension')) {
      meditationMin = 15;
      meditationNote =
          'Mindfulness meditation 15 min/day is clinically shown to lower blood pressure.';
    } else if (conditions.contains('Diabetes')) {
      meditationMin = 10;
      meditationNote =
          'Stress reduction through meditation helps stabilise blood glucose levels.';
    } else if (conditions.contains('Asthma')) {
      meditationMin = 10;
      meditationNote =
          'Calm, focused breathing during meditation can reduce asthma trigger sensitivity.';
    }
    suggestions.add(_WorkoutSuggestion(
      icon: Icons.self_improvement,
      color: SageColors.sage,
      title: 'Meditation',
      description: meditationNote,
      targetLabel: '$meditationMin min/day',
      targetKey: 'meditationMinutes',
      targetValue: meditationMin,
      onGo: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(
              builder: (_) => MeditationScreen(
                  initialHeartRate: 72,
                  bmi: bmi,
                  bmiCategory: _bmiCategory(bmi)))),
    ));

    int breathSessions = 1;
    String breathNote =
        'One short session per day activates your parasympathetic nervous system.';
    if (conditions.contains('Hypertension') ||
        conditions.contains('Heart Disease')) {
      breathSessions = 2;
      breathNote =
          'Twice-daily breathwork (morning + evening) is most effective for managing blood pressure.';
    } else if (conditions.contains('Asthma')) {
      breathSessions = 2;
      breathNote =
          '2 daily breathwork sessions strengthen respiratory muscles and improve lung control.';
    }
    suggestions.add(_WorkoutSuggestion(
      icon: Icons.air,
      color: SageColors.clay,
      title: 'Breathwork',
      description: breathNote,
      targetLabel:
          '$breathSessions session${breathSessions > 1 ? "s" : ""}/day',
      targetKey: 'breathworkSessions',
      targetValue: breathSessions,
      onGo: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(
              builder: (_) => const BreathworkScreen(initialHeartRate: 72))),
    ));

    return suggestions;
  }

  /// Opens the custom-plan editor with optional pre-filled values.
  /// [prefill] may contain a pre-computed Sage suggestion to apply as defaults.
  void _showCustomPlanDialog({Map<String, dynamic>? prefill}) {
    final targets = _bella.getTargets();
    final merged = {...targets, ...?prefill};

    final nameCtrl =
        TextEditingController(text: merged['customPlanName'] as String? ?? '');
    final stepsCtrl = TextEditingController(text: '${merged['steps'] ?? 8000}');
    final walkCtrl =
        TextEditingController(text: '${merged['walkMinutes'] ?? 25}');
    final medCtrl =
        TextEditingController(text: '${merged['meditationMinutes'] ?? 10}');
    final breathCtrl =
        TextEditingController(text: '${merged['breathworkSessions'] ?? 1}');
    final waterCtrl = TextEditingController(
        text: '${merged['waterMl'] ?? _suggestWater().value}');
    final calCtrl = TextEditingController(
        text: '${merged['calorieTarget'] ?? _suggestCalories().value}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SageColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Build your own Fitly plan',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: SageColors.ink,
                fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Plan name (optional)',
                  hintText: 'e.g. Morning routine',
                  filled: true,
                  fillColor: SageColors.linen,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              _numField(stepsCtrl, 'Daily steps', 'steps'),
              const SizedBox(height: 10),
              _numField(walkCtrl, 'Walking minutes/day', 'min'),
              const SizedBox(height: 10),
              _numField(medCtrl, 'Meditation minutes/day', 'min'),
              const SizedBox(height: 10),
              _numField(breathCtrl, 'Breathwork sessions/day', 'sessions'),
              const SizedBox(height: 16),
              Divider(color: SageColors.line),
              const SizedBox(height: 10),
              Text(
                'Nutrition targets',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: SageColors.inkSoft),
              ),
              const SizedBox(height: 10),
              _numField(waterCtrl, 'Daily water target', 'ml'),
              const SizedBox(height: 10),
              _numField(calCtrl, 'Daily calorie target', 'kcal'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: SageColors.inkSoft)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final newTargets = {
                ...targets,
                if (name.isNotEmpty) 'customPlanName': name,
                'steps':
                    int.tryParse(stepsCtrl.text) ?? targets['steps'] ?? 8000,
                'walkMinutes':
                    int.tryParse(walkCtrl.text) ?? targets['walkMinutes'] ?? 25,
                'meditationMinutes': int.tryParse(medCtrl.text) ??
                    targets['meditationMinutes'] ??
                    10,
                'breathworkSessions': int.tryParse(breathCtrl.text) ??
                    targets['breathworkSessions'] ??
                    1,
                'waterMl':
                    int.tryParse(waterCtrl.text) ?? targets['waterMl'] ?? 2000,
                'calorieTarget': int.tryParse(calCtrl.text) ??
                    targets['calorieTarget'] ??
                    2000,
              };
              await _bella.saveTargets(newTargets);
              if (!mounted) return;
              Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(name.isNotEmpty
                      ? '"$name" saved'
                      : 'Custom Fitly plan saved'),
                  backgroundColor: SageColors.moss));
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: SageColors.moss,
                foregroundColor: SageColors.linen),
            child: const Text('Save plan'),
          ),
        ],
      ),
    );
  }

  /// Clears the user's saved custom plan after confirmation.
  Future<void> _deleteCustomPlan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SageColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete custom plan?',
            style: TextStyle(
                color: SageColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        content: Text(
          'This will remove your saved targets. You can always build a new plan or apply a template afterwards.',
          style: TextStyle(color: SageColors.inkSoft, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: SageColors.inkSoft)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: SageColors.clay)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final targets = _bella.getTargets();
    for (final k in [
      'steps',
      'walkMinutes',
      'meditationMinutes',
      'breathworkSessions',
      'waterMl',
      'calorieTarget',
      'customPlanName',
    ]) {
      targets.remove(k);
    }
    await _bella.saveTargets(targets);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Custom plan deleted'),
        backgroundColor: SageColors.clay));
  }

  Widget _numField(TextEditingController ctrl, String label, String suffix) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        filled: true,
        fillColor: SageColors.linen,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final plan = CareRules.generatePlan(bmi: _bmi, conditions: _conditions);

    return Scaffold(
      backgroundColor: SageColors.linen,
      appBar: AppBar(
        title:
            Text('PurePlate', style: SageText.headline(color: SageColors.ink)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: SageColors.moss,
          unselectedLabelColor: SageColors.inkSoft,
          indicatorColor: SageColors.moss,
          tabs: const [
            Tab(icon: Icon(Icons.water_drop_outlined), text: 'Water'),
            Tab(icon: Icon(Icons.restaurant_outlined), text: 'Food'),
            Tab(icon: Icon(Icons.fitness_center_outlined), text: 'Fitly'),
          ],
        ),
      ),
      body: Reveal(size: RevealSize.large,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildWaterTab(plan),
            _buildFoodTab(plan),
            _buildFitlyTab(),
          ],
        ),
      ),
    );
  }

  // ── Water tab ──────────────────────────────────────────────────────────

  Widget _buildWaterTab(DietGuideline plan) {
    final todayMl = _bella.todayWaterMl();

    // Prefer saved custom water target, then plan target
    final savedWaterTarget = _bella.getTarget<int>('waterMl');
    final targetMl = savedWaterTarget ?? plan.dailyWaterMlTarget;
    final progress = (todayMl / targetMl).clamp(0.0, 1.0);
    final tips = _buildWaterTips(plan);
    final comment = _waterComment(todayMl, targetMl);

    // Condition-specific "why" explanation
    final conditions = _conditions;
    String whyText =
        'Your target is based on your BMI${conditions.isNotEmpty ? " and chronic conditions" : ""}. '
        'Hydration affects meals (Food tab) and movement recovery (Fitly) — '
        'staying on top of it here helps both.';
    if (conditions.contains('Chronic Kidney Disease')) {
      whyText =
          'With Chronic Kidney Disease, your fluid target ($targetMl ml) is intentionally '
          'lower than the general recommendation to reduce the load on your kidneys. '
          'Spread intake evenly — don\'t drink large amounts at once. '
          'Always confirm with your nephrologist.';
    } else if (conditions.contains('Diabetes')) {
      whyText =
          'Diabetes raises your hydration needs: high blood glucose draws water out '
          'of cells and forces your kidneys to work harder. '
          'Your target ($targetMl ml) is slightly above baseline to support glucose '
          'clearance and reduce fatigue from mild dehydration.';
    } else if (conditions.contains('Hypertension')) {
      whyText =
          'Adequate hydration keeps blood volume stable, which helps prevent the '
          'compensatory vessel constriction that raises blood pressure. '
          'Your target ($targetMl ml) is calibrated to your weight and BMI.';
    } else if (conditions.contains('Heart Disease')) {
      whyText =
          'For Heart Disease, fluid management matters on both sides: too little '
          'raises blood viscosity; too much adds cardiac load. '
          'Your target ($targetMl ml) sits in the safe range for your stats.';
    } else if (conditions.contains('Asthma')) {
      whyText =
          'Dehydration thickens mucus in the airways, making them more reactive '
          'to Asthma triggers. Your target ($targetMl ml) adds a small buffer '
          'above the standard recommendation to keep airways clear.';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tips.isNotEmpty) ...[
            ...tips.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _contextBanner(t),
                )),
            const SizedBox(height: 8),
          ],

          // ── Main water tracker card ────────────────────────────────────
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.water_drop_outlined,
                      color: SageColors.clay, size: 18),
                  const SizedBox(width: 8),
                  Text('Water today',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: SageColors.ink)),
                  if (savedWaterTarget != null) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: SageColors.moss.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Custom target',
                        style:
                            TextStyle(fontSize: 10.5, color: SageColors.moss),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(alignment: Alignment.center, children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: SageColors.line,
                        valueColor: AlwaysStoppedAnimation(
                          progress >= 1.0 ? SageColors.sage : SageColors.clay,
                        ),
                      ),
                      Text(
                        progress >= 1.0 ? '✓' : '${(progress * 100).round()}%',
                        style: TextStyle(
                          fontSize: progress >= 1.0 ? 18 : 11.5,
                          fontWeight: FontWeight.w700,
                          color: progress >= 1.0
                              ? SageColors.sage
                              : SageColors.ink,
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$todayMl / $targetMl ml',
                              style: SageText.mono(
                                  size: 16, weight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            savedWaterTarget != null
                                ? 'Your custom daily target'
                                : 'Adjusted for your BMI${conditions.isNotEmpty ? " & conditions" : ""}',
                            style: TextStyle(
                                fontSize: 11.5, color: SageColors.inkSoft),
                          ),
                        ]),
                  ),
                ]),

                // ── Rich comment ───────────────────────────────────────
                if (comment != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: comment.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: comment.color.withValues(alpha: 0.22)),
                    ),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(comment.icon, size: 16, color: comment.color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              comment.text,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: comment.color,
                                  height: 1.45),
                            ),
                          ),
                        ]),
                  ),
                ],

                const SizedBox(height: 14),
                Text('Add water',
                    style:
                        TextStyle(fontSize: 11.5, color: SageColors.inkSoft)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [200, 350, 500].map((ml) {
                    return OutlinedButton(
                      onPressed: () => _addWater(ml),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SageColors.clay,
                        side: BorderSide(
                            color: SageColors.clay.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      child: Text('+${ml}ml',
                          style: const TextStyle(fontSize: 12.5)),
                    );
                  }).toList(),
                ),
                if (todayMl > 0) ...[
                  const SizedBox(height: 10),
                  Text('Remove',
                      style:
                          TextStyle(fontSize: 11.5, color: SageColors.inkSoft)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [200, 350].map((ml) {
                      return OutlinedButton(
                        onPressed: () => _removeWater(ml),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SageColors.inkSoft,
                          side: BorderSide(
                              color: SageColors.inkSoft.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        child: Text('−${ml}ml',
                            style: const TextStyle(fontSize: 12.5)),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── Why this much water ────────────────────────────────────────
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, color: SageColors.sage, size: 18),
                  const SizedBox(width: 8),
                  Text('Why this much water',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: SageColors.ink)),
                ]),
                const SizedBox(height: 8),
                Text(
                  whyText,
                  style: TextStyle(
                      fontSize: 12.5, color: SageColors.inkSoft, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Food tab ───────────────────────────────────────────────────────────

  Widget _buildFoodTab(DietGuideline plan) {
    final foodToday = _bella.getFoodEntries(onDate: DateTime.now());
    final totalCal = foodToday.fold<int>(0, (s, f) => s + (f.calories ?? 0));

    // Prefer saved custom calorie target
    final savedCalTarget = _bella.getTarget<int>('calorieTarget');
    // Fall back to the Sage-computed suggestion (same formula used in the
    // Fitly tab) so the Food tab always shows a personalised target, never
    // a hardcoded magic number.
    final calorieTarget = savedCalTarget ?? _suggestCalories().value;
    final calorieComment = _calorieComment(totalCal, calorieTarget);
    final tips = _buildFoodTips(plan);
    final richDiet = _buildRichDietPlan();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tips.isNotEmpty) ...[
            ...tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _contextBanner(t))),
            const SizedBox(height: 8),
          ],
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Log food',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: SageColors.ink)),
                  const Spacer(),
                  if (foodToday.isNotEmpty)
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (totalCal > 0)
                            Text('$totalCal kcal',
                                style: SageText.mono(
                                    size: 12,
                                    weight: FontWeight.w600,
                                    color: SageColors.moss)),
                          Text(
                            '${foodToday.length} meal${foodToday.length != 1 ? 's' : ''}${totalCal > 0 && foodToday.isNotEmpty ? ' · ~${(totalCal / foodToday.length).round()} kcal/meal' : ''}',
                            style: TextStyle(
                                fontSize: 10.5, color: SageColors.inkSoft),
                          ),
                        ]),
                ]),
                const SizedBox(height: 4),
                // Progress bar vs daily target
                if (foodToday.isNotEmpty && totalCal > 0) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (totalCal / calorieTarget).clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: SageColors.line,
                          valueColor: AlwaysStoppedAnimation(
                            totalCal > calorieTarget * 1.2
                                ? SageColors.clay
                                : totalCal < calorieTarget * 0.5
                                    ? SageColors.amber
                                    : SageColors.moss,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$totalCal / $calorieTarget kcal',
                      style:
                          TextStyle(fontSize: 10.5, color: SageColors.inkSoft),
                    ),
                  ]),
                  const SizedBox(height: 4),
                ],
                Text('Visible to Chronic Care & ZZZify as context.',
                    style:
                        TextStyle(fontSize: 11.5, color: SageColors.inkSoft)),
                if (calorieComment != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (() {
                        final r = totalCal / calorieTarget;
                        return r > 1.2
                            ? SageColors.clay
                            : r < 0.5
                                ? SageColors.amber
                                : SageColors.moss;
                      }())
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (() {
                          final r = totalCal / calorieTarget;
                          return r > 1.2
                              ? SageColors.clay
                              : r < 0.5
                                  ? SageColors.amber
                                  : SageColors.moss;
                        }())
                            .withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            totalCal / calorieTarget > 1.2
                                ? Icons.warning_amber_outlined
                                : totalCal / calorieTarget < 0.5
                                    ? Icons.battery_alert_outlined
                                    : Icons.check_circle_outline,
                            size: 15,
                            color: totalCal / calorieTarget > 1.2
                                ? SageColors.clay
                                : totalCal / calorieTarget < 0.5
                                    ? SageColors.amber
                                    : SageColors.moss,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              calorieComment,
                              style: TextStyle(
                                fontSize: 12,
                                color: totalCal / calorieTarget > 1.2
                                    ? SageColors.clay
                                    : totalCal / calorieTarget < 0.5
                                        ? SageColors.amber
                                        : SageColors.moss,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ]),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _foodController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Grilled chicken & rice',
                    filled: true,
                    fillColor: SageColors.linen,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _caloriesController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Calories (optional)',
                    suffixText: 'kcal',
                    filled: true,
                    fillColor: SageColors.linen,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  _tagChip('balanced', 'Balanced'),
                  _tagChip('high-sodium', 'High sodium'),
                  _tagChip('high-carb', 'High carb'),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _logFood,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SageColors.moss,
                      foregroundColor: SageColors.linen,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Add entry'),
                  ),
                ),
                if (foodToday.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 6),
                  ...foodToday.map((f) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.circle,
                              size: 6, color: SageColors.inkSoft),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.description,
                                    style: TextStyle(
                                        fontSize: 13, color: SageColors.ink)),
                                Row(children: [
                                  if (f.calories != null)
                                    Text('${f.calories} kcal',
                                        style: SageText.mono(
                                            size: 11, color: SageColors.moss)),
                                  if (f.calories != null &&
                                      f.tag != null &&
                                      f.tag != 'balanced')
                                    Text(' · ',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: SageColors.inkSoft)),
                                  if (f.tag != null && f.tag != 'balanced')
                                    Text(f.tag!,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: SageColors.clay)),
                                ]),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit_outlined,
                                size: 16, color: SageColors.inkSoft),
                            onPressed: () => _showEditFoodDialog(f),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 16, color: SageColors.clay),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: SageColors.card,
                                  title: Text('Remove entry?',
                                      style: TextStyle(
                                          color: SageColors.ink, fontSize: 15)),
                                  content: Text(f.description,
                                      style:
                                          TextStyle(color: SageColors.inkSoft)),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel')),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text('Remove',
                                            style: TextStyle(
                                                color: SageColors.clay))),
                                  ],
                                ),
                              );
                              if (confirm == true) await _removeFood(f);
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.auto_awesome, color: SageColors.moss, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Sage plan · ${plan.title}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: SageColors.ink)),
                  ),
                ]),
                if (_conditions.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'No chronic conditions on file — this is general guidance. Add conditions in your Profile for a tailored plan.',
                    style: TextStyle(fontSize: 12.5, color: SageColors.inkSoft),
                  ),
                ],
                if (plan.sodiumLimit != null) ...[
                  const SizedBox(height: 10),
                  _pill(Icons.science_outlined, plan.sodiumLimit!,
                      SageColors.clay),
                ],
                if (plan.carbGuidance != null) ...[
                  const SizedBox(height: 8),
                  _pill(Icons.bakery_dining_outlined, plan.carbGuidance!,
                      SageColors.amber),
                ],
                const SizedBox(height: 14),
                Text('Do',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: SageColors.moss)),
                const SizedBox(height: 6),
                ...plan.doList.map((d) => _bullet(d, SageColors.moss)),
                const SizedBox(height: 12),
                Text('Limit',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: SageColors.clay)),
                const SizedBox(height: 6),
                ...plan.avoidList.map((d) => _bullet(d, SageColors.clay)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.restaurant_menu_outlined,
                      color: SageColors.moss, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('What to eat — based on your profile',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: SageColors.ink)),
                  ),
                ]),
                if (_conditions.isEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                      'No chronic conditions on file — showing general guidance. Add conditions in Profile for a personalised list.',
                      style:
                          TextStyle(fontSize: 12, color: SageColors.inkSoft)),
                ],
                const SizedBox(height: 14),
                ...richDiet.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                  color: item.color.withValues(alpha: 0.1),
                                  shape: BoxShape.circle),
                              child:
                                  Icon(item.icon, size: 14, color: item.color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.label,
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: SageColors.ink)),
                                    const SizedBox(height: 2),
                                    Text(item.detail,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: SageColors.inkSoft,
                                            height: 1.4)),
                                  ]),
                            ),
                          ]),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Fitly tab ──────────────────────────────────────────────────────────

  Widget _buildFitlyTab() {
    final workoutPlan = _buildWorkoutPlan();
    final tips = _buildFitlyTips();
    final targets = _bella.getTargets();
    final hasCustomPlan = targets.containsKey('steps') ||
        targets.containsKey('walkMinutes') ||
        targets.containsKey('meditationMinutes') ||
        targets.containsKey('breathworkSessions');
    final customPlanName = targets['customPlanName'] as String?;

    final waterSuggestion = _suggestWater();
    final calSuggestion = _suggestCalories();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tips.isNotEmpty) ...[
            ...tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _contextBanner(t))),
            const SizedBox(height: 8),
          ],

          // ── Sage Suggestion card ───────────────────────────────────────
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(
                      () => _sageSuggestionExpanded = !_sageSuggestionExpanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                          color: SageColors.moss.withValues(alpha: 0.12),
                          shape: BoxShape.circle),
                      child: Icon(Icons.auto_awesome,
                          size: 14, color: SageColors.moss),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Sage suggestion',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                    color: SageColors.ink)),
                            Text(
                              'Water & calorie targets based on your profile',
                              style: TextStyle(
                                  fontSize: 11.5, color: SageColors.inkSoft),
                            ),
                          ]),
                    ),
                    Icon(
                      _sageSuggestionExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: SageColors.inkSoft,
                    ),
                  ]),
                ),
                if (_sageSuggestionExpanded) ...[
                  const SizedBox(height: 16),

                  // Two stat tiles side by side
                  Row(children: [
                    _sageSuggestionTile(
                      Icons.water_drop_outlined,
                      '${waterSuggestion.value} ml',
                      'Water / day',
                      SageColors.clay,
                    ),
                    const SizedBox(width: 10),
                    _sageSuggestionTile(
                      Icons.local_fire_department_outlined,
                      '${calSuggestion.value} kcal',
                      'Calories / day',
                      SageColors.amber,
                    ),
                  ]),

                  const SizedBox(height: 14),

                  // Water reason
                  _reasonRow(
                    icon: Icons.water_drop_outlined,
                    color: SageColors.clay,
                    label: 'Water target rationale',
                    text: waterSuggestion.reason,
                  ),

                  const SizedBox(height: 10),

                  // Calorie reason
                  _reasonRow(
                    icon: Icons.local_fire_department_outlined,
                    color: SageColors.amber,
                    label: 'Calorie target rationale',
                    text: calSuggestion.reason,
                  ),

                  const SizedBox(height: 16),

                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await _bella.saveTargets({
                            ..._bella.getTargets(),
                            'waterMl': waterSuggestion.value,
                            'calorieTarget': calSuggestion.value,
                          });
                          setState(() {});
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: const Text('Sage targets applied'),
                              backgroundColor: SageColors.moss));
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SageColors.moss,
                          side: BorderSide(
                              color: SageColors.moss.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: const Text('Apply suggestion',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showCustomPlanDialog(prefill: {
                          'waterMl': waterSuggestion.value,
                          'calorieTarget': calSuggestion.value,
                        }),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SageColors.inkSoft,
                          side: BorderSide(
                              color:
                                  SageColors.inkSoft.withValues(alpha: 0.35)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: const Text('Customise',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Custom plan card ───────────────────────────────────────────
          if (hasCustomPlan) ...[
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                          color: SageColors.moss.withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                      child: Icon(Icons.tune, size: 14, color: SageColors.moss),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customPlanName != null &&
                                      customPlanName.isNotEmpty
                                  ? customPlanName
                                  : 'My custom plan',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                  color: SageColors.ink),
                            ),
                            Text('Custom Fitly plan',
                                style: TextStyle(
                                    fontSize: 11.5, color: SageColors.inkSoft)),
                          ]),
                    ),
                    // Edit button
                    OutlinedButton(
                      onPressed: _showCustomPlanDialog,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SageColors.moss,
                        side: BorderSide(
                            color: SageColors.moss.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Edit', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    // Delete button
                    OutlinedButton(
                      onPressed: _deleteCustomPlan,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SageColors.clay,
                        side: BorderSide(
                            color: SageColors.clay.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child:
                          const Text('Delete', style: TextStyle(fontSize: 12)),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  // Movement targets 2×2
                  Row(children: [
                    _customPlanStat(
                        Icons.directions_walk,
                        '${targets['steps'] ?? 8000}',
                        'steps/day',
                        SageColors.moss),
                    const SizedBox(width: 10),
                    _customPlanStat(
                        Icons.timer_outlined,
                        '${targets['walkMinutes'] ?? 25} min',
                        'walking',
                        SageColors.amber),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _customPlanStat(
                        Icons.self_improvement,
                        '${targets['meditationMinutes'] ?? 10} min',
                        'meditation',
                        SageColors.sage),
                    const SizedBox(width: 10),
                    _customPlanStat(
                        Icons.air,
                        '${targets['breathworkSessions'] ?? 1}×',
                        'breathwork',
                        SageColors.clay),
                  ]),
                  // Nutrition targets (shown only if set)
                  if (targets.containsKey('waterMl') ||
                      targets.containsKey('calorieTarget')) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      if (targets.containsKey('waterMl'))
                        Expanded(
                          child: _customPlanStat(
                              Icons.water_drop_outlined,
                              '${targets['waterMl']} ml',
                              'water/day',
                              SageColors.clay),
                        ),
                      if (targets.containsKey('waterMl') &&
                          targets.containsKey('calorieTarget'))
                        const SizedBox(width: 10),
                      if (targets.containsKey('calorieTarget'))
                        Expanded(
                          child: _customPlanStat(
                              Icons.local_fire_department_outlined,
                              '${targets['calorieTarget']} kcal',
                              'calories/day',
                              SageColors.amber),
                        ),
                    ]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Sage commentary on the custom plan ────────────────────────
            Builder(builder: (_) {
              final planFeedback = _buildCustomPlanFeedback(targets);
              if (planFeedback.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: SageColors.moss.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.auto_awesome,
                                size: 14, color: SageColors.moss),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Sage review of your plan',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.5,
                                        color: SageColors.ink)),
                                Text(
                                  'Based on your BMI, age & conditions',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: SageColors.inkSoft),
                                ),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        ...planFeedback.map((fb) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: fb.color.withValues(
                                      alpha:
                                          fb.severity == _FeedbackSeverity.good
                                              ? 0.06
                                              : 0.09),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: fb.color.withValues(alpha: 0.22)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      fb.severity == _FeedbackSeverity.good
                                          ? Icons.check_circle_outline
                                          : fb.severity ==
                                                  _FeedbackSeverity.warning
                                              ? Icons.warning_amber_outlined
                                              : Icons.info_outline,
                                      size: 15,
                                      color: fb.color,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(fb.title,
                                              style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: fb.color)),
                                          const SizedBox(height: 3),
                                          Text(fb.body,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: SageColors.inkSoft,
                                                  height: 1.4)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            }),
          ],

          // ── Main card: header + build-your-own + templates ─────────────
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.fitness_center_outlined,
                      color: SageColors.clay, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Your movement plan',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: SageColors.ink)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Use a template tailored to your BMI${_conditions.isNotEmpty ? " and conditions" : ""}, '
                  'or build your own from scratch — the numbers you set here drive Walking, '
                  'Meditation and Breathwork targets.',
                  style: TextStyle(
                      fontSize: 12, color: SageColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: 12),
                // Build / Add another plan button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showCustomPlanDialog(),
                    icon: Icon(Icons.tune, size: 16, color: SageColors.moss),
                    label: Text(hasCustomPlan
                        ? 'Add / replace plan'
                        : 'Build your own plan'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SageColors.moss,
                      side: BorderSide(
                          color: SageColors.moss.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Templates',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: SageColors.inkSoft)),
                const SizedBox(height: 10),
                ...workoutPlan.map((w) {
                  final existing = _bella.getTarget<int>(w.targetKey);
                  final isSet = existing != null && existing == w.targetValue;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                                color: w.color.withValues(alpha: 0.1),
                                shape: BoxShape.circle),
                            child: Icon(w.icon, size: 14, color: w.color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(w.title,
                                      style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: SageColors.ink)),
                                  Text(w.targetLabel,
                                      style: SageText.mono(
                                          size: 11.5, color: w.color)),
                                ]),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(w.description,
                            style: TextStyle(
                                fontSize: 12,
                                color: SageColors.inkSoft,
                                height: 1.4)),
                        const SizedBox(height: 8),
                        Row(children: [
                          OutlinedButton(
                            onPressed: () => w.onGo(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: w.color,
                              side: BorderSide(
                                  color: w.color.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            child: Text('Open ${w.title}',
                                style: const TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: isSet
                                ? null
                                : () async {
                                    await _bella.setTarget(
                                        w.targetKey, w.targetValue);
                                    if (w.secondaryKey != null &&
                                        w.secondaryValue != null) {
                                      await _bella.setTarget(
                                          w.secondaryKey!, w.secondaryValue!);
                                    }
                                    setState(() {});
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                '${w.title} target set to ${w.targetLabel}'),
                                            backgroundColor: SageColors.moss));
                                  },
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  isSet ? SageColors.inkSoft : SageColors.moss,
                              side: BorderSide(
                                  color: isSet
                                      ? SageColors.line
                                      : SageColors.moss.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            child: Text(isSet ? '✓ Target set' : 'Use template',
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ]),
                        if (workoutPlan.last != w) const Divider(height: 20),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Fitly helper widgets ───────────────────────────────────────────────

  Widget _sageSuggestionTile(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 6),
            Text(value,
                style: SageText.mono(
                    size: 15, weight: FontWeight.w700, color: color)),
            Text(label,
                style: TextStyle(fontSize: 10.5, color: SageColors.inkSoft)),
          ],
        ),
      ),
    );
  }

  Widget _reasonRow({
    required IconData icon,
    required Color color,
    required String label,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.2)),
          ]),
          const SizedBox(height: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 12, color: SageColors.inkSoft, height: 1.4)),
        ],
      ),
    );
  }

  Widget _customPlanStat(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value,
                  style: SageText.mono(
                      size: 13, weight: FontWeight.w700, color: color)),
              Text(label,
                  style: TextStyle(fontSize: 10.5, color: SageColors.inkSoft)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Shared small widgets ───────────────────────────────────────────────

  Widget _contextBanner(_ContextTip t) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.color.withValues(alpha: 0.22)),
      ),
      child: Row(children: [
        Icon(t.icon, size: 16, color: t.color),
        const SizedBox(width: 10),
        Expanded(
            child: Text(t.text,
                style: TextStyle(fontSize: 12.5, color: t.color, height: 1.4))),
      ]),
    );
  }

  Widget _tagChip(String value, String label) {
    final selected = _foodTag == value;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: selected ? SageColors.linen : SageColors.ink)),
      selected: selected,
      selectedColor: SageColors.moss,
      backgroundColor: SageColors.linen,
      onSelected: (_) => setState(() => _foodTag = value),
    );
  }

  Widget _pill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color))),
      ]),
    );
  }

  Widget _bullet(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 5, color: color)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5, color: SageColors.ink, height: 1.4))),
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

// ── Data models ────────────────────────────────────────────────────────────

class _ContextTip {
  final IconData icon;
  final Color color;
  final String text;
  const _ContextTip(
      {required this.icon, required this.color, required this.text});
}

/// A computed Sage suggestion with a numeric value and a plain-English reason.
class _SageSuggestionValue {
  final int value;
  final String reason;
  const _SageSuggestionValue({required this.value, required this.reason});
}

/// A rich hydration comment for the Water tab.
class _WaterComment {
  final IconData icon;
  final Color color;
  final String text;
  const _WaterComment(
      {required this.icon, required this.color, required this.text});
}

class _WorkoutSuggestion {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String targetLabel;
  final String targetKey;
  final int targetValue;
  final String? secondaryKey;
  final int? secondaryValue;
  final void Function(BuildContext) onGo;

  const _WorkoutSuggestion({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.targetLabel,
    required this.targetKey,
    required this.targetValue,
    this.secondaryKey,
    this.secondaryValue,
    required this.onGo,
  });
}

class _DietRich {
  final IconData icon;
  final Color color;
  final String label;
  final String detail;

  const _DietRich(
      {required this.icon,
      required this.color,
      required this.label,
      required this.detail});
}

enum _FeedbackSeverity { good, low, warning }

/// A single feedback item produced by [_buildCustomPlanFeedback].
/// Displayed in the Fitly tab after the user has saved a custom plan.
class _PlanFeedback {
  final IconData icon;
  final Color color;
  final _FeedbackSeverity severity;
  final String title;
  final String body;

  const _PlanFeedback({
    required this.icon,
    required this.color,
    required this.severity,
    required this.title,
    required this.body,
  });
}
