// services/bella_service.dart
import 'package:hive/hive.dart';
import 'user_service.dart';
import '../models/bella_data.dart';

/// Persistence for Bella (Sleep, Chronic Care, Diet & Water, Daily
/// Check-in, and Wellness Sessions). Plain singleton + Hive.
///
/// Hive box key scheme (all per-username):
///   '<user>::sleep'      -> List<Map>  SleepEntry  (multiple per day)
///   '<user>::water'      -> List<Map>  WaterEntry
///   '<user>::food'       -> List<Map>  FoodEntry
///   '<user>::readings'   -> List<Map>  ReadingEntry
///   '<user>::checkins'   -> List<Map>  CheckinEntry
///   '<user>::targets'    -> Map        wellness targets set from Fitly
///   '<user>::sessions'   -> List<Map>  WellnessSession (completed activities)
class BellaService {
  static final BellaService _instance = BellaService._internal();
  factory BellaService() => _instance;
  BellaService._internal();

  static const boxName = 'bellaData';

  static Future<void> openBox() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox(boxName);
    }
  }

  Box get _box => Hive.box(boxName);

  String get _user => UserService().currentUser ?? 'guest';

  String _key(String suffix) => '$_user::$suffix';

  // ── Internal helpers ────────────────────────────────────────────────────

  /// Deep-converts Hive's LinkedHashMap to Map<String, dynamic> recursively.
  static Map<String, dynamic> _deepConvert(Map raw) {
    return raw.map((k, v) {
      if (v is Map) return MapEntry(k.toString(), _deepConvert(v));
      if (v is List) {
        return MapEntry(k.toString(),
            v.map((e) => e is Map ? _deepConvert(e) : e).toList());
      }
      return MapEntry(k.toString(), v);
    });
  }

  List<Map<String, dynamic>> _readList(String suffix) {
    final raw = _box.get(_key(suffix));
    if (raw is List) {
      return raw.whereType<Map>().map(_deepConvert).toList();
    }
    return [];
  }

  Future<void> _writeList(String suffix, List<Map<String, dynamic>> items) =>
      _box.put(_key(suffix), items);

  Map<String, dynamic> _readMap(String suffix) {
    final raw = _box.get(_key(suffix));
    if (raw is Map) return _deepConvert(raw);
    return {};
  }

  Future<void> _writeMap(String suffix, Map<String, dynamic> data) =>
      _box.put(_key(suffix), data);

  // ── Sleep ───────────────────────────────────────────────────────────────
  //
  // Multiple entries per day are supported (night sleep + naps).
  // Each entry has a unique [id] string; saveSleepEntry replaces by id.

  List<SleepEntry> getSleepEntries() =>
      _readList('sleep').map((m) => SleepEntry.fromMap(m)).toList()
        ..sort((a, b) {
          final dateCmp = b.date.compareTo(a.date);
          if (dateCmp != 0) return dateCmp;
          // Within same date: sort by bedtime descending (latest first)
          final bt = b.bedtime ?? b.date;
          final at = a.bedtime ?? a.date;
          return bt.compareTo(at);
        });

  /// All entries for a specific calendar date, sorted earliest first.
  List<SleepEntry> getSleepEntriesForDate(DateTime date) {
    return getSleepEntries()
        .where((e) =>
            e.date.year == date.year &&
            e.date.month == date.month &&
            e.date.day == date.day)
        .toList()
      ..sort((a, b) {
        final at = a.bedtime ?? a.date;
        final bt = b.bedtime ?? b.date;
        return at.compareTo(bt);
      });
  }

  /// Save or update a sleep entry by its [id].
  /// If an entry with the same id already exists it is replaced;
  /// otherwise the new entry is appended (allows multiple per day).
  Future<void> saveSleepEntry(SleepEntry entry) async {
    final all = getSleepEntries();
    final idx = all.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      all[idx] = entry;
    } else {
      all.add(entry);
    }
    await _writeList('sleep', all.map((e) => e.toMap()).toList());
  }

  /// Delete a specific entry by its unique [id].
  Future<void> deleteSleepEntry(SleepEntry entry) async {
    final all = getSleepEntries();
    all.removeWhere((e) => e.id == entry.id);
    await _writeList('sleep', all.map((e) => e.toMap()).toList());
  }

  double? averageSleepQuality({int days = 7}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    // Only count non-nap entries for quality average
    final recent = getSleepEntries()
        .where((e) => e.date.isAfter(cutoff) && !e.isNap)
        .toList();
    if (recent.isEmpty) return null;
    return recent.map((e) => e.quality).reduce((a, b) => a + b) / recent.length;
  }

  /// The most recent night sleep entry (non-nap), or the most recent entry
  /// of any kind if no non-nap exists, or null if the user has no sleep data.
  SleepEntry? get lastNightSleep {
    final all = getSleepEntries();
    if (all.isEmpty) return null;
    // Try to find a non-nap entry first
    final nightEntries = all.where((e) => !e.isNap).toList();
    if (nightEntries.isNotEmpty) return nightEntries.first;
    // Fall back to the most recent entry of any kind
    return all.first;
  }

  // ── Water ───────────────────────────────────────────────────────────────

  List<WaterEntry> getWaterEntries({DateTime? onDate}) {
    final all = _readList('water').map((m) => WaterEntry.fromMap(m)).toList();
    if (onDate == null) return all;
    return all
        .where((w) =>
            w.time.year == onDate.year &&
            w.time.month == onDate.month &&
            w.time.day == onDate.day)
        .toList();
  }

  Future<void> addWater(int milliliters) async {
    final all = _readList('water');
    all.add(WaterEntry(time: DateTime.now(), milliliters: milliliters).toMap());
    await _writeList('water', all);
  }

  Future<void> removeWater(int milliliters) async {
    final todayTotal = todayWaterMl();
    final actual = milliliters > todayTotal ? todayTotal : milliliters;
    if (actual <= 0) return;
    final all = _readList('water');
    all.add(WaterEntry(time: DateTime.now(), milliliters: -actual).toMap());
    await _writeList('water', all);
  }

  int todayWaterMl() {
    final total = getWaterEntries(onDate: DateTime.now())
        .fold(0, (sum, w) => sum + w.milliliters);
    return total < 0 ? 0 : total;
  }

  // ── Food ────────────────────────────────────────────────────────────────

  List<FoodEntry> getFoodEntries({DateTime? onDate}) {
    final all = _readList('food').map((m) => FoodEntry.fromMap(m)).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    if (onDate == null) return all;
    return all
        .where((f) =>
            f.time.year == onDate.year &&
            f.time.month == onDate.month &&
            f.time.day == onDate.day)
        .toList();
  }

  Future<void> addFood(FoodEntry entry) async {
    final all = _readList('food');
    all.add(entry.toMap());
    await _writeList('food', all);
  }

  Future<void> removeFood(FoodEntry entry) async {
    final all = _readList('food').map((m) => FoodEntry.fromMap(m)).toList();
    all.removeWhere(
        (f) => f.time == entry.time && f.description == entry.description);
    await _writeList('food', all.map((f) => f.toMap()).toList());
  }

  Future<void> editFood(FoodEntry oldEntry, FoodEntry newEntry) async {
    final all = _readList('food').map((m) => FoodEntry.fromMap(m)).toList();
    final idx = all.indexWhere((f) =>
        f.time == oldEntry.time && f.description == oldEntry.description);
    if (idx < 0) return;
    all[idx] = newEntry;
    await _writeList('food', all.map((f) => f.toMap()).toList());
  }

  // ── Chronic care readings ────────────────────────────────────────────────

  List<ReadingEntry> getReadings({String? condition}) {
    final all = _readList('readings')
        .map((m) => ReadingEntry.fromMap(m))
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    if (condition == null) return all;
    return all.where((r) => r.condition == condition).toList();
  }

  Future<void> addReading(ReadingEntry entry) async {
    final all = _readList('readings');
    all.add(entry.toMap());
    await _writeList('readings', all);
  }

  /// Delete a specific reading by its unique [id].
  Future<void> deleteReading(ReadingEntry entry) async {
    final all =
        _readList('readings').map((m) => ReadingEntry.fromMap(m)).toList();
    all.removeWhere((r) => r.id == entry.id);
    await _writeList('readings', all.map((r) => r.toMap()).toList());
  }

  /// Replace a reading (matched by [id]) with [updated].
  Future<void> editReading(ReadingEntry updated) async {
    final all =
        _readList('readings').map((m) => ReadingEntry.fromMap(m)).toList();
    final idx = all.indexWhere((r) => r.id == updated.id);
    if (idx < 0) return;
    all[idx] = updated;
    await _writeList('readings', all.map((r) => r.toMap()).toList());
  }

  List<ReadingEntry> readingTrend(String condition, String type, {int n = 14}) {
    final filtered =
        getReadings(condition: condition).where((r) => r.type == type).toList();
    return filtered.take(n).toList().reversed.toList();
  }

  // ── Daily check-ins ──────────────────────────────────────────────────────

  List<CheckinEntry> getCheckins() =>
      _readList('checkins').map((m) => CheckinEntry.fromMap(m)).toList()
        ..sort((a, b) => b.time.compareTo(a.time));

  Future<void> addCheckin(CheckinEntry entry) async {
    final all = _readList('checkins');
    all.add(entry.toMap());
    await _writeList('checkins', all);
  }

  /// Deletes a specific CheckinEntry by its unique [id].
  Future<void> deleteCheckin(CheckinEntry entry) async {
    final all =
        _readList('checkins').map((m) => CheckinEntry.fromMap(m)).toList();
    all.removeWhere((c) => c.id == entry.id);
    await _writeList('checkins', all.map((c) => c.toMap()).toList());
  }

  bool hasCheckedInToday() {
    final today = DateTime.now();
    return getCheckins().any((c) =>
        c.time.year == today.year &&
        c.time.month == today.month &&
        c.time.day == today.day);
  }

  CheckinEntry? get lastCheckin {
    final all = getCheckins();
    return all.isEmpty ? null : all.first;
  }

  double? averageWellbeing({int days = 7}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final recent = getCheckins().where((c) => c.time.isAfter(cutoff)).toList();
    if (recent.isEmpty) return null;
    return recent.map((c) => c.wellbeingScore).reduce((a, b) => a + b) /
        recent.length;
  }

  // ── Wellness targets (set from Fitly) ────────────────────────────────────
  //
  // Stored as a flat Map<String, dynamic> under '<user>::targets'.
  // Known keys:
  //   'steps'               int    daily step goal
  //   'walkMinutes'         int    daily walking minutes
  //   'meditationMinutes'   int    daily meditation minutes
  //   'meditationType'      String preferred session type label
  //   'breathworkSessions'  int    sessions per day
  //   'waterMl'             int    daily water target ml

  Map<String, dynamic> getTargets() => _readMap('targets');

  /// Retrieve a single target value, typed, or null if not set.
  T? getTarget<T>(String key) {
    final map = getTargets();
    final v = map[key];
    if (v is T) return v;
    // Handle int/double mismatch from Hive round-trip
    if (T == int && v is num) return v.toInt() as T;
    if (T == double && v is num) return v.toDouble() as T;
    return null;
  }

  /// Set (or replace) a single target value.
  Future<void> setTarget(String key, dynamic value) async {
    final map = getTargets();
    map[key] = value;
    await _writeMap('targets', map);
  }

  /// Replace all targets at once (e.g. when approving a full Sage plan).
  Future<void> saveTargets(Map<String, dynamic> targets) =>
      _writeMap('targets', targets);

  /// Remove a specific target key.
  Future<void> clearTarget(String key) async {
    final map = getTargets();
    map.remove(key);
    await _writeMap('targets', map);
  }

  // ── Wellness sessions (completed activities) ─────────────────────────────
  //
  // Logged by Walking, Meditation and Breathwork screens on completion.

  List<WellnessSession> getSessions({String? type}) {
    final all = _readList('sessions')
        .map((m) => WellnessSession.fromMap(m))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (type == null) return all;
    return all.where((s) => s.type == type).toList();
  }

  Future<void> logSession(String type, int durationMinutes, {String? detail}) async {
    final all = _readList('sessions');
    all.add(WellnessSession(
      type: type,
      date: DateTime.now(),
      durationMinutes: durationMinutes,
      detail: detail,
    ).toMap());
    await _writeList('sessions', all);
  }

  /// Count of sessions of [type] completed today.
  int sessionsToday(String type) {
    final today = DateTime.now();
    return getSessions(type: type)
        .where((s) =>
            s.date.year == today.year &&
            s.date.month == today.month &&
            s.date.day == today.day)
        .length;
  }

  /// Total minutes of [type] sessions logged today.
  int sessionMinutesToday(String type) {
    final today = DateTime.now();
    return getSessions(type: type)
        .where((s) =>
            s.date.year == today.year &&
            s.date.month == today.month &&
            s.date.day == today.day)
        .fold(0, (sum, s) => sum + s.durationMinutes);
  }

  // ── Achievement unlock dates ──────────────────────────────────────────────
  //
  // AchievementsService computes unlock status live, every time, from
  // session/checkin/sleep data — there's no separate "achievements" table
  // to drift out of sync. But that meant `unlockedAt` had nowhere honest
  // to come from and was always just `DateTime.now()`. This is the one
  // small bit of real persistence: the first time an achievement is seen
  // unlocked, its id + timestamp gets written here, once, and never
  // overwritten — so "unlocked 3 days ago" can actually be true.
  //
  // Stored as a flat Map<String, String> (achievement id -> ISO timestamp)
  // under '<user>::achievementUnlocks'.

  Map<String, DateTime> getAchievementUnlocks() {
    final raw = _readMap('achievementUnlocks');
    final out = <String, DateTime>{};
    for (final entry in raw.entries) {
      final parsed = DateTime.tryParse(entry.value.toString());
      if (parsed != null) out[entry.key] = parsed;
    }
    return out;
  }

  /// Records [id] as unlocked at [time], but only the first time — later
  /// calls for an id that's already recorded are a no-op, so the original
  /// unlock date is never overwritten.
  Future<void> recordAchievementUnlock(String id, DateTime time) async {
    final map = _readMap('achievementUnlocks');
    if (map.containsKey(id)) return;
    map[id] = time.toIso8601String();
    await _writeMap('achievementUnlocks', map);
  }
}