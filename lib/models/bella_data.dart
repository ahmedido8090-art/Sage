// models/bella_data.dart
//
// Plain data classes for Bella (Sage's proactive care layer): sleep,
// chronic-care readings, diet/water, daily check-ins, and wellness sessions.
// Stored as Map<String, dynamic> via BellaService (Hive).

/// One sleep session (night sleep OR nap — multiple allowed per day).
class SleepEntry {
  /// Unique id — used to update/delete a specific entry without affecting
  /// others on the same calendar date.
  final String id;

  /// Calendar date this session belongs to (date-only, no time component).
  final DateTime date;

  final DateTime? bedtime;
  final DateTime? wakeTime;
  final int quality; // 1-5
  final List<String> windDownDone;

  /// True when the user explicitly marked this as a nap (short daytime sleep).
  /// Derived automatically if false: a session whose bedtime is between
  /// 06:00–20:00 and duration < 3 h is treated as a nap for commentary,
  /// but the stored flag is authoritative when set.
  final bool isNap;

  SleepEntry({
    required this.id,
    required this.date,
    this.bedtime,
    this.wakeTime,
    required this.quality,
    this.windDownDone = const [],
    this.isNap = false,
  });

  Duration? get duration {
    if (bedtime == null || wakeTime == null) return null;
    var d = wakeTime!.difference(bedtime!);
    if (d.isNegative) d += const Duration(hours: 24);
    return d;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'bedtime': bedtime?.toIso8601String(),
        'wakeTime': wakeTime?.toIso8601String(),
        'quality': quality,
        'windDownDone': windDownDone,
        'isNap': isNap,
      };

  factory SleepEntry.fromMap(Map map) {
    // Back-compat: old entries have no 'id' — synthesise one from date.
    final id = map['id'] as String? ??
        '${map['date']}_legacy_${map['bedtime'] ?? 'noid'}';
    return SleepEntry(
      id: id,
      date: DateTime.parse(map['date']),
      bedtime:
          map['bedtime'] != null ? DateTime.tryParse(map['bedtime']) : null,
      wakeTime:
          map['wakeTime'] != null ? DateTime.tryParse(map['wakeTime']) : null,
      quality: map['quality'] ?? 3,
      windDownDone: (map['windDownDone'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isNap: map['isNap'] as bool? ?? false,
    );
  }
}

/// A single water log entry (one "add water" tap).
class WaterEntry {
  final DateTime time;
  final int milliliters;

  WaterEntry({required this.time, required this.milliliters});

  Map<String, dynamic> toMap() => {
        'time': time.toIso8601String(),
        'milliliters': milliliters,
      };

  factory WaterEntry.fromMap(Map map) => WaterEntry(
        time: DateTime.parse(map['time']),
        milliliters: map['milliliters'] ?? 0,
      );
}

/// A logged food/meal entry.
/// [calories] is optional (null if the user didn't enter it).
/// [tag] drives cross-screen context tips in Sleep and Chronic Care.
class FoodEntry {
  final DateTime time;
  final String description;
  final String? tag; // 'high-sodium' | 'high-carb' | 'balanced'
  final int? calories; // kcal, optional

  FoodEntry({
    required this.time,
    required this.description,
    this.tag,
    this.calories,
  });

  Map<String, dynamic> toMap() => {
        'time': time.toIso8601String(),
        'description': description,
        'tag': tag,
        'calories': calories,
      };

  factory FoodEntry.fromMap(Map map) => FoodEntry(
        time: DateTime.parse(map['time']),
        description: map['description'] ?? '',
        tag: map['tag'],
        calories: map['calories'] as int?,
      );
}

/// A chronic-condition reading, e.g. blood glucose (mg/dL) or blood
/// pressure (store systolic in [value], diastolic in [secondaryValue]).
class ReadingEntry {
  final String id; // NEW: unique identifier
  final DateTime time;
  final String condition; // matches ChronicConditions.options
  final String type; // e.g. 'Blood Glucose', 'Blood Pressure', 'Peak Flow'
  final double value;
  final double? secondaryValue;
  final String unit;
  final String? note; // NEW: optional free-text annotation

  const ReadingEntry({
    required this.id,
    required this.time,
    required this.condition,
    required this.type,
    required this.value,
    this.secondaryValue,
    required this.unit,
    this.note,
  });

  factory ReadingEntry.fromMap(Map<String, dynamic> m) => ReadingEntry(
        // Backwards-compat: old entries without 'id' get a stable fallback
        id: (m['id'] as String?) ?? 'rdg_legacy_${m['time']}',
        time: DateTime.parse(m['time'] as String),
        condition: m['condition'] as String,
        type: m['type'] as String,
        value: (m['value'] as num).toDouble(),
        secondaryValue: m['secondaryValue'] != null
            ? (m['secondaryValue'] as num).toDouble()
            : null,
        unit: m['unit'] as String,
        note: m['note'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'time': time.toIso8601String(),
        'condition': condition,
        'type': type,
        'value': value,
        'secondaryValue': secondaryValue,
        'unit': unit,
        'note': note,
      };

  /// Returns a copy with selected fields replaced.
  ReadingEntry copyWith({
    String? id,
    DateTime? time,
    String? condition,
    String? type,
    double? value,
    double? secondaryValue,
    String? unit,
    String? note,
  }) =>
      ReadingEntry(
        id: id ?? this.id,
        time: time ?? this.time,
        condition: condition ?? this.condition,
        type: type ?? this.type,
        value: value ?? this.value,
        secondaryValue: secondaryValue ?? this.secondaryValue,
        unit: unit ?? this.unit,
        note: note ?? this.note,
      );
}

/// A daily mood/stress/energy check-in.
class CheckinEntry {
  /// Unique id — used by [BellaService.deleteCheckin] to target a specific
  /// entry without relying on timestamp + value matching.
  final String id;
  final DateTime time;
  final int mood; // 1-5
  final int stress; // 1-5 (5 = most stressed)
  final int energy; // 1-5
  final String? note;

  CheckinEntry({
    String? id,
    required this.time,
    required this.mood,
    required this.stress,
    required this.energy,
    this.note,
  }) : id = id ?? '${time.millisecondsSinceEpoch}';

  /// A composite score 0-10 used to decide whether to surface nudges.
  /// Low mood/energy and high stress pull it down.
  double get wellbeingScore {
    final moodPart = mood; // 1-5
    final energyPart = energy; // 1-5
    final stressPart = 6 - stress; // invert: low stress = good
    return ((moodPart + energyPart + stressPart) / 15) * 10;
  }

  bool get isLow => wellbeingScore <= 4.5;

  Map<String, dynamic> toMap() => {
        'id': id,
        'time': time.toIso8601String(),
        'mood': mood,
        'stress': stress,
        'energy': energy,
        'note': note,
      };

  factory CheckinEntry.fromMap(Map map) {
    final time = DateTime.parse(map['time']);
    // Back-compat: old entries have no 'id' — synthesise from timestamp.
    final id = map['id'] as String? ?? '${time.millisecondsSinceEpoch}';
    return CheckinEntry(
      id: id,
      time: time,
      mood: map['mood'] ?? 3,
      stress: map['stress'] ?? 3,
      energy: map['energy'] ?? 3,
      note: map['note'],
    );
  }
}

/// A completed wellness session (walking, meditation, breathwork).
/// Logged by each screen when the user finishes an activity.
class WellnessSession {
  /// One of: 'walking' | 'meditation' | 'breathwork'
  final String type;
  final DateTime date;
  final int durationMinutes;

  /// Optional, type-specific extra info that previously had nowhere
  /// reliable to live:
  ///   - walking: the step count as a plain integer string, e.g. '8421'
  ///   - breathwork: the technique name, e.g. 'Box Breathing'
  /// Null for older sessions logged before this field existed, and for
  /// types that don't have anything to attach (meditation, sleep_sounds).
  final String? detail;

  WellnessSession({
    required this.type,
    required this.date,
    required this.durationMinutes,
    this.detail,
  });

  Map<String, dynamic> toMap() => {
        'type': type,
        'date': date.toIso8601String(),
        'durationMinutes': durationMinutes,
        if (detail != null) 'detail': detail,
      };

  factory WellnessSession.fromMap(Map map) => WellnessSession(
        type: map['type'] ?? '',
        date: DateTime.parse(map['date']),
        durationMinutes: map['durationMinutes'] ?? 0,
        detail: map['detail'] as String?,
      );
}