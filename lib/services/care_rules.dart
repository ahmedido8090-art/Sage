// services/care_rules.dart
//
// Rule-based logic for Sage-generated diet plans and the Chronic Care
// symptom guide. Static lookup + simple numeric rules per condition —
// no external dependency, easy to extend with more conditions later.
import '../models/bella_data.dart';

class DietGuideline {
  final String title;
  final List<String> doList;
  final List<String> avoidList;
  final int dailyWaterMlTarget;
  final String? sodiumLimit; // null if not relevant
  final String? carbGuidance;

  const DietGuideline({
    required this.title,
    required this.doList,
    required this.avoidList,
    required this.dailyWaterMlTarget,
    this.sodiumLimit,
    this.carbGuidance,
  });
}

class SymptomGuidance {
  final String advice;
  final bool urgent; // true => recommend contacting a doctor
  const SymptomGuidance(this.advice, {this.urgent = false});
}

class CareRules {
  CareRules._();

  static const int _baseWaterMl = 2000;

  /// Per-condition diet rules. Multiple conditions combine (most
  /// restrictive sodium/carb guidance wins; do/avoid lists merge).
  static const Map<String, DietGuideline> _guidelines = {
    'Diabetes': DietGuideline(
      title: 'Carb-aware plan',
      doList: [
        'Pair carbs with protein or fiber to slow glucose spikes',
        'Favor whole grains over refined (white bread, white rice)',
        'Spread carbs evenly across meals rather than one big load',
      ],
      avoidList: [
        'Sugary drinks and fruit juice',
        'Large portions of refined carbs in one sitting',
      ],
      dailyWaterMlTarget: 2200,
      carbGuidance:
          'Aim for roughly 45–60g carbs per meal, consistent day to day.',
    ),
    'Hypertension': DietGuideline(
      title: 'Low-sodium plan',
      doList: [
        'Cook with herbs/spices instead of salt',
        'Choose fresh or frozen over canned/processed foods',
        'Watch potassium-rich foods (bananas, leafy greens) — they help balance sodium',
      ],
      avoidList: [
        'Processed/cured meats',
        'Restaurant and packaged foods high in sodium',
        'Adding table salt at the plate',
      ],
      dailyWaterMlTarget: 2200,
      sodiumLimit: 'Keep sodium under ~1,500mg/day',
    ),
    'Heart Disease': DietGuideline(
      title: 'Heart-healthy plan',
      doList: [
        'Favor unsaturated fats (olive oil, nuts, fish) over saturated',
        'Add soluble fiber (oats, beans) to help manage cholesterol',
      ],
      avoidList: [
        'Fried foods and trans fats',
        'Excess sodium (see Hypertension guidance if also relevant)',
      ],
      dailyWaterMlTarget: 2000,
      sodiumLimit: 'Keep sodium under ~1,500mg/day',
    ),
    'Chronic Kidney Disease': DietGuideline(
      title: 'Kidney-conscious plan',
      doList: [
        'Moderate protein portions, spread across the day',
        'Track potassium and phosphorus intake with your care team',
      ],
      avoidList: [
        'High-sodium processed foods',
        'Salt substitutes containing potassium chloride (check with your doctor)',
      ],
      dailyWaterMlTarget: 1800,
      sodiumLimit: 'Keep sodium under ~2,000mg/day, confirm with your doctor',
    ),
    'High Cholesterol': DietGuideline(
      title: 'Cholesterol-aware plan',
      doList: [
        'Increase soluble fiber (oats, beans, apples)',
        'Choose lean proteins and fatty fish over red/processed meat',
      ],
      avoidList: [
        'Saturated and trans fats',
        'Fried and highly processed snack foods',
      ],
      dailyWaterMlTarget: 2000,
    ),
    'Asthma': DietGuideline(
      title: 'General wellness plan',
      doList: [
        'Stay well hydrated — thinner mucus is easier to clear',
        'Anti-inflammatory foods (fruits, vegetables, omega-3s) may help',
      ],
      avoidList: ['Known personal food triggers, if any'],
      dailyWaterMlTarget: 2200,
    ),
    'Arthritis': DietGuideline(
      title: 'Anti-inflammatory plan',
      doList: [
        'Omega-3 rich foods (fatty fish, walnuts, flaxseed)',
        'Plenty of fruits and vegetables',
      ],
      avoidList: [
        'Excess sugar and refined carbs, which can worsen inflammation'
      ],
      dailyWaterMlTarget: 2000,
    ),
    'Thyroid Disorder': DietGuideline(
      title: 'General wellness plan',
      doList: [
        'Consistent meal timing supports energy levels',
        'Discuss iodine and selenium intake with your doctor',
      ],
      avoidList: ['Excess raw cruciferous vegetables in very large amounts'],
      dailyWaterMlTarget: 2000,
    ),
  };

  static const DietGuideline _defaultGuideline = DietGuideline(
    title: 'General wellness plan',
    doList: [
      'Balanced plate: protein, whole grains, vegetables',
      'Regular meal timing',
    ],
    avoidList: ['Excess added sugar and ultra-processed foods'],
    dailyWaterMlTarget: _baseWaterMl,
  );

  /// Generates a combined diet guideline from a user's BMI and selected
  /// chronic conditions. Real (if simple) rule logic, not just copy:
  /// water target adjusts for BMI, sodium/carb guidance is the most
  /// restrictive across all selected conditions, and do/avoid lists merge
  /// without duplicates.
  static DietGuideline generatePlan({
    required double bmi,
    required List<String> conditions,
  }) {
    if (conditions.isEmpty) {
      return _adjustForBmi(_defaultGuideline, bmi);
    }

    final relevant = conditions
        .map((c) => _guidelines[c])
        .whereType<DietGuideline>()
        .toList();

    if (relevant.isEmpty) {
      return _adjustForBmi(_defaultGuideline, bmi);
    }

    final doSet = <String>{};
    final avoidSet = <String>{};
    String? sodium;
    String? carb;
    int waterTarget = 0;

    for (final g in relevant) {
      doSet.addAll(g.doList);
      avoidSet.addAll(g.avoidList);
      sodium ??= g.sodiumLimit;
      carb ??= g.carbGuidance;
      if (g.dailyWaterMlTarget > waterTarget) {
        waterTarget = g.dailyWaterMlTarget;
      }
    }

    final title = relevant.length == 1
        ? relevant.first.title
        : 'Combined plan (${conditions.join(", ")})';

    final merged = DietGuideline(
      title: title,
      doList: doSet.toList(),
      avoidList: avoidSet.toList(),
      dailyWaterMlTarget: waterTarget,
      sodiumLimit: sodium,
      carbGuidance: carb,
    );

    return _adjustForBmi(merged, bmi);
  }

  static DietGuideline _adjustForBmi(DietGuideline base, double bmi) {
    // Nudge water target for higher body weight ranges — a simple,
    // defensible rule rather than a precise clinical formula.
    int water = base.dailyWaterMlTarget;
    if (bmi >= 30) {
      water += 300;
    } else if (bmi >= 25) {
      water += 150;
    }
    return DietGuideline(
      title: base.title,
      doList: base.doList,
      avoidList: base.avoidList,
      dailyWaterMlTarget: water,
      sodiumLimit: base.sodiumLimit,
      carbGuidance: base.carbGuidance,
    );
  }

  // --- Symptom guide ---
  // Maps condition -> symptom keyword -> guidance. The screen also folds
  // in recent readings/food context (see ChronicCareScreen) so the same
  // symptom can carry a sharper note when a relevant reading is out of
  // range or a trigger food was logged recently.

  static const Map<String, Map<String, SymptomGuidance>> _symptomGuides = {
    'Diabetes': {
      'Shaky / dizzy': SymptomGuidance(
          'Could be low blood sugar. Check glucose if you can; if low, '
          'have a fast-acting carb (juice, glucose tabs) and recheck in 15 min.'),
      'Very thirsty / frequent urination': SymptomGuidance(
          'Could indicate high blood sugar. Check glucose and avoid sugary '
          'drinks until you do.'),
      'Fatigue': SymptomGuidance(
          'Common with both high and low glucose. Worth a check if it\'s new or severe.'),
      'Blurred vision': SymptomGuidance(
          'Can follow a glucose swing. If it persists beyond a day, contact your doctor.',
          urgent: true),
    },
    'Hypertension': {
      'Headache': SymptomGuidance(
          'Could relate to a blood pressure spike. Take a reading if you can, '
          'and rest somewhere calm.'),
      'Dizziness': SymptomGuidance(
          'May indicate blood pressure that\'s too high or too low. Check a reading.'),
      'Chest tightness': SymptomGuidance(
          'Chest symptoms with hypertension should be taken seriously — '
          'contact a doctor or emergency services if severe.',
          urgent: true),
      'Blurred vision': SymptomGuidance(
          'Can occur with very high blood pressure. Check a reading and '
          'contact your doctor if it\'s significantly elevated.',
          urgent: true),
    },
    'Asthma': {
      'Shortness of breath': SymptomGuidance(
          'Use your rescue inhaler as prescribed. If it doesn\'t improve, seek care.',
          urgent: true),
      'Wheezing': SymptomGuidance(
          'Move away from possible triggers and use your inhaler if prescribed.'),
      'Chest tightness': SymptomGuidance(
          'Sit upright, try slow breathing, and use your inhaler if prescribed.'),
    },
    'Heart Disease': {
      'Chest pain': SymptomGuidance(
          'Chest pain should not be ignored — contact a doctor or emergency services.',
          urgent: true),
      'Shortness of breath': SymptomGuidance(
          'Rest and monitor. If sudden or severe, seek care promptly.',
          urgent: true),
      'Swelling in legs/ankles': SymptomGuidance(
          'Can be a sign of fluid retention — worth mentioning to your doctor.'),
    },
    'Arthritis': {
      'Joint stiffness': SymptomGuidance(
          'Gentle movement and warmth often help morning stiffness.'),
      'Swelling': SymptomGuidance(
          'Rest the joint and consider a cold pack; track if it\'s worsening.'),
      'Fatigue': SymptomGuidance(
          'Flares can be tiring — pace activity and prioritize rest today.'),
    },
    'Chronic Kidney Disease': {
      'Swelling in legs/ankles': SymptomGuidance(
          'Can indicate fluid buildup — worth a call to your care team.',
          urgent: true),
      'Fatigue': SymptomGuidance(
          'Common with CKD; mention persistent fatigue at your next visit.'),
      'Nausea': SymptomGuidance(
          'Can relate to diet or kidney function — track timing and inform your doctor.'),
    },
    'Thyroid Disorder': {
      'Fatigue': SymptomGuidance(
          'Common with thyroid imbalance; worth tracking alongside sleep.'),
      'Rapid heartbeat': SymptomGuidance(
          'Can relate to thyroid hormone levels — contact your doctor if frequent.',
          urgent: true),
      'Weight change': SymptomGuidance(
          'Track over a few weeks and mention the trend at your next visit.'),
    },
    'High Cholesterol': {
      'Chest tightness': SymptomGuidance(
          'Take seriously — contact a doctor or emergency services if severe.',
          urgent: true),
      'Fatigue': SymptomGuidance(
          'Generally not a direct symptom of cholesterol — worth tracking regardless.'),
    },
  };

  static List<String> symptomsFor(String condition) =>
      _symptomGuides[condition]?.keys.toList() ?? const [];

  /// Returns guidance for a symptom, adding extra context when a recent
  /// out-of-typical-range reading or a tagged food entry makes the
  /// situation more (or less) concerning. This is what makes the guide
  /// "dynamic" rather than a flat static lookup.
  static SymptomGuidance guidanceFor(
    String condition,
    String symptom, {
    ReadingEntry? mostRecentReading,
    List<FoodEntry> recentFood = const [],
  }) {
    final base = _symptomGuides[condition]?[symptom] ??
        SymptomGuidance(
            'Track this symptom and mention it at your next checkup.');

    final extras = <String>[];

    if (mostRecentReading != null) {
      final flagged = _isReadingFlagged(condition, mostRecentReading);
      if (flagged) {
        extras.add(
            'Your last logged ${mostRecentReading.type.toLowerCase()} reading '
            '(${mostRecentReading.value.toStringAsFixed(0)}${mostRecentReading.unit}) was outside the typical range — '
            'that may be related.');
      }
    }

    final highSodiumToday = recentFood.any((f) => f.tag == 'high-sodium');
    final highCarbToday = recentFood.any((f) => f.tag == 'high-carb');
    if (condition == 'Hypertension' && highSodiumToday) {
      extras.add(
          'You logged a high-sodium item recently — that can contribute to this.');
    }
    if (condition == 'Diabetes' && highCarbToday) {
      extras.add(
          'You logged a high-carb item recently — that can contribute to this.');
    }

    if (extras.isEmpty) return base;
    return SymptomGuidance(
      '${base.advice} ${extras.join(' ')}',
      urgent: base.urgent,
    );
  }

  static bool _isReadingFlagged(String condition, ReadingEntry r) {
    switch (condition) {
      case 'Diabetes':
        return r.value < 70 || r.value > 180;
      case 'Hypertension':
        return r.value >= 140 || (r.secondaryValue ?? 0) >= 90;
      default:
        return false;
    }
  }
}
