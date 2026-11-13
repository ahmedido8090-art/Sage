// services/bella_service.dart
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:hive/hive.dart';
import 'user_service.dart';
import '../models/bella_data.dart';

/// Persistence for Bella (Sleep, Chronic Care, Diet & Water, Daily
/// Check-in, and Wellness Sessions). Plain singleton + Hive.
///
/// Hive box key scheme (all per-username):
///   '`<user>`::sleep'      -> List<Map>  SleepEntry  (multiple per day)
///   '`<user>`::water'      -> List<Map>  WaterEntry
///   '`<user>`::food'       -> List<Map>  FoodEntry
///   '`<user>`::readings'   -> List<Map>  ReadingEntry
///   '`<user>`::checkins'   -> List<Map>  CheckinEntry
///   '`<user>`::targets'    -> Map        wellness targets set from Fitly
///   '`<user>`::sessions'   -> List<Map>  WellnessSession (completed activities)
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

  /// The signed-in username, or null when nobody is. With no user, reads are
  /// empty and writes are dropped: data never lands in a shared bucket.
  String? get _user => UserService().currentUser;

  String _key(String user, String suffix) => '$user::$suffix';

  /// Chains every read-modify-write so rapid taps (water, food, sessions)
  /// can't read the same snapshot and overwrite each other. Hive only exposes
  /// a write after its `put` future completes.
  Future<void> _queue = Future.value();

  Future<void> _serialized(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((_) {});
    return next;
  }

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

  /// Parsed-model cache. A read re-parsed the whole stored list every time
  /// (Insights alone makes ~22 `getSessions()` calls per load). The cache is
  /// keyed by the identity of the raw list Hive hands back: every write puts
  /// a new list object, so a changed list can never be served stale.
  final Map<String, _Parsed> _parsedCache = {};

  /// Parsed entries for [suffix], shared across callers. Entries are
  /// immutable value objects, so callers get a fresh list they may sort or
  /// filter freely.
  List<T> _models<T>(String suffix, T Function(Map<String, dynamic>) parse) {
    final user = _user;
    if (user == null) return [];
    final raw = _box.get(_key(user, suffix));
    if (raw is! List) return [];
    final cacheKey = _key(user, suffix);
    final cached = _parsedCache[cacheKey];
    if (cached != null && identical(cached.raw, raw)) {
      return List<T>.of(cached.items.cast<T>());
    }
    final items =
        raw.whereType<Map>().map((m) => parse(_deepConvert(m))).toList();
    _parsedCache[cacheKey] = _Parsed(raw, items);
    return List<T>.of(items);
  }

  List<Map<String, dynamic>> _readList(String suffix) {
    final user = _user;
    if (user == null) return [];
    final raw = _box.get(_key(user, suffix));
    if (raw is List) {
      return raw.whereType<Map>().map(_deepConvert).toList();
    }
    return [];
  }

  Future<void> _writeList(String suffix, List<Map<String, dynamic>> items) {
    final user = _user;
    if (user == null) return Future.value();
    return _box.put(_key(user, suffix), items);
  }

  Map<String, dynamic> _readMap(String suffix) {
    final user = _user;
    if (user == null) return {};
    final raw = _box.get(_key(user, suffix));
    if (raw is Map) return _deepConvert(raw);
    return {};
  }

  /// Names of the lists that hold what the user has logged.
  static const List<String> loggedDataKeys = [
    'sleep',
    'water',
    'food',
    'readings',
    'checkins',
    'sessions',
  ];

  /// Deletes [names] for the signed-in user, in order with other writes.
  Future<void> clearStoredKeys(List<String> names) {
    final user = _user;
    if (user == null) return Future.value();
    return _serialized(() async {
      for (final name in names) {
        await _box.delete(_key(user, name));
        _parsedCache.remove(_key(user, name));
      }
    });
  }

  /// Per-user key/value blob for features that keep their own settings.
  Map<String, dynamic> readStoredMap(String name) => _readMap(name);

  Future<void> writeStoredMap(String name, Map<String, dynamic> data) =>
      _serialized(() => _writeMap(name, data));

  Future<void> _writeMap(String suffix, Map<String, dynamic> data) {
    final user = _user;
    if (user == null) return Future.value();
    return _box.put(_key(user, suffix), data);
  }

  // ── Sleep ───────────────────────────────────────────────────────────────
  //
  // Multiple entries per day are supported (night sleep + naps).
  // Each entry has a unique [id] string; saveSleepEntry replaces by id.

  List<SleepEntry> getSleepEntries() => _models('sleep', SleepEntry.fromMap)
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
  Future<void> saveSleepEntry(SleepEntry entry) => _serialized(() async {
        final all = getSleepEntries();
        final idx = all.indexWhere((e) => e.id == entry.id);
        if (idx >= 0) {
          all[idx] = entry;
        } else {
          all.add(entry);
        }
        await _writeList('sleep', all.map((e) => e.toMap()).toList());
      });

  /// Delete a specific entry by its unique [id].
  Future<void> deleteSleepEntry(SleepEntry entry) => _serialized(() async {
        final all = getSleepEntries();
        all.removeWhere((e) => e.id == entry.id);
        await _writeList('sleep', all.map((e) => e.toMap()).toList());
      });

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
    final all = _models('water', WaterEntry.fromMap);
    if (onDate == null) return all;
    return all
        .where((w) =>
            w.time.year == onDate.year &&
            w.time.month == onDate.month &&
            w.time.day == onDate.day)
        .toList();
  }

  Future<void> addWater(int milliliters) => _serialized(() async {
        final all = _readList('water');
        all.add(
            WaterEntry(time: DateTime.now(), milliliters: milliliters).toMap());
        await _writeList('water', all);
      });

  Future<void> removeWater(int milliliters) => _serialized(() async {
        final todayTotal = todayWaterMl();
        final actual = milliliters > todayTotal ? todayTotal : milliliters;
        if (actual <= 0) return;
        final all = _readList('water');
        all.add(WaterEntry(time: DateTime.now(), milliliters: -actual).toMap());
        await _writeList('water', all);
      });

  int todayWaterMl() {
    final total = getWaterEntries(onDate: DateTime.now())
        .fold(0, (sum, w) => sum + w.milliliters);
    return total < 0 ? 0 : total;
  }

  // ── Food ────────────────────────────────────────────────────────────────

  List<FoodEntry> getFoodEntries({DateTime? onDate}) {
    final all = _models('food', FoodEntry.fromMap)
      ..sort((a, b) => b.time.compareTo(a.time));
    if (onDate == null) return all;
    return all
        .where((f) =>
            f.time.year == onDate.year &&
            f.time.month == onDate.month &&
            f.time.day == onDate.day)
        .toList();
  }

  Future<void> addFood(FoodEntry entry) => _serialized(() async {
        final all = _readList('food');
        all.add(entry.toMap());
        await _writeList('food', all);
      });

  Future<void> removeFood(FoodEntry entry) => _serialized(() async {
        final all = _readList('food').map((m) => FoodEntry.fromMap(m)).toList();
        all.removeWhere(
            (f) => f.time == entry.time && f.description == entry.description);
        await _writeList('food', all.map((f) => f.toMap()).toList());
      });

  Future<void> editFood(FoodEntry oldEntry, FoodEntry newEntry) =>
      _serialized(() async {
        final all = _readList('food').map((m) => FoodEntry.fromMap(m)).toList();
        final idx = all.indexWhere((f) =>
            f.time == oldEntry.time && f.description == oldEntry.description);
        if (idx < 0) return;
        all[idx] = newEntry;
        await _writeList('food', all.map((f) => f.toMap()).toList());
      });

  // ── Chronic care readings ────────────────────────────────────────────────

  List<ReadingEntry> getReadings({String? condition}) {
    final all = _models('readings', ReadingEntry.fromMap)
      ..sort((a, b) => b.time.compareTo(a.time));
    if (condition == null) return all;
    return all.where((r) => r.condition == condition).toList();
  }

  Future<void> addReading(ReadingEntry entry) => _serialized(() async {
        final all = _readList('readings');
        all.add(entry.toMap());
        await _writeList('readings', all);
      });

  /// Delete a specific reading by its unique [id].
  Future<void> deleteReading(ReadingEntry entry) => _serialized(() async {
        final all =
            _readList('readings').map((m) => ReadingEntry.fromMap(m)).toList();
        all.removeWhere((r) => r.id == entry.id);
        await _writeList('readings', all.map((r) => r.toMap()).toList());
      });

  /// Replace a reading (matched by [id]) with [updated].
  Future<void> editReading(ReadingEntry updated) => _serialized(() async {
        final all =
            _readList('readings').map((m) => ReadingEntry.fromMap(m)).toList();
        final idx = all.indexWhere((r) => r.id == updated.id);
        if (idx < 0) return;
        all[idx] = updated;
        await _writeList('readings', all.map((r) => r.toMap()).toList());
      });

  List<ReadingEntry> readingTrend(String condition, String type, {int n = 14}) {
    final filtered =
        getReadings(condition: condition).where((r) => r.type == type).toList();
    return filtered.take(n).toList().reversed.toList();
  }

  // ── Daily check-ins ──────────────────────────────────────────────────────

  List<CheckinEntry> getCheckins() => _models('checkins', CheckinEntry.fromMap)
    ..sort((a, b) => b.time.compareTo(a.time));

  Future<void> addCheckin(CheckinEntry entry) => _serialized(() async {
        final all = _readList('checkins');
        all.add(entry.toMap());
        await _writeList('checkins', all);
      });

  /// Deletes a specific CheckinEntry by its unique [id].
  Future<void> deleteCheckin(CheckinEntry entry) => _serialized(() async {
        final all = _models('checkins', CheckinEntry.fromMap);
        all.removeWhere((c) => c.id == entry.id);
        await _writeList('checkins', all.map((c) => c.toMap()).toList());
      });

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
  // Stored as a flat Map<String, dynamic> under '`<user>`::targets'.
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
  Future<void> setTarget(String key, dynamic value) => _serialized(() async {
        final map = getTargets();
        map[key] = value;
        await _writeMap('targets', map);
      });

  /// Replace all targets at once (e.g. when approving a full Sage plan).
  Future<void> saveTargets(Map<String, dynamic> targets) =>
      _serialized(() => _writeMap('targets', targets));

  /// Remove a specific target key.
  Future<void> clearTarget(String key) => _serialized(() async {
        final map = getTargets();
        map.remove(key);
        await _writeMap('targets', map);
      });

  // ── Wellness sessions (completed activities) ─────────────────────────────
  //
  // Logged by Walking, Meditation and Breathwork screens on completion.

  List<WellnessSession> getSessions({String? type}) {
    final all = _models('sessions', WellnessSession.fromMap)
      ..sort((a, b) => b.date.compareTo(a.date));
    if (type == null) return all;
    return all.where((s) => s.type == type).toList();
  }

  Future<void> logSession(String type, int durationMinutes, {String? detail}) =>
      _serialized(() async {
        final all = _readList('sessions');
        all.add(WellnessSession(
          type: type,
          date: DateTime.now(),
          durationMinutes: durationMinutes,
          detail: detail,
        ).toMap());
        await _writeList('sessions', all);
      });

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
  // under '`<user>`::achievementUnlocks'.

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
  Future<void> recordAchievementUnlock(String id, DateTime time) =>
      _serialized(() async {
        final map = _readMap('achievementUnlocks');
        if (map.containsKey(id)) return;
        map[id] = time.toIso8601String();
        await _writeMap('achievementUnlocks', map);
      });

  /// Records several unlocks in one write. Ids already recorded keep their
  /// original date.
  Future<void> recordAchievementUnlocks(Map<String, DateTime> unlocks) {
    if (unlocks.isEmpty) return Future.value();
    return _serialized(() async {
      final map = _readMap('achievementUnlocks');
      var changed = false;
      unlocks.forEach((id, time) {
        if (map.containsKey(id)) return;
        map[id] = time.toIso8601String();
        changed = true;
      });
      if (changed) await _writeMap('achievementUnlocks', map);
    });
  }

  /// Writes starting targets for [username] without requiring them to be
  /// signed in, used right after registration.
  Future<void> seedTargetsFor(String username, Map<String, dynamic> targets) =>
      _serialized(() => _box.put(_key(username, 'targets'), targets));
}

extension BellaUserData on BellaService {
  /// Bumped whenever the signed-in user's logged data is wiped, so screens
  /// that cache what they loaded can reload.
  static final ValueNotifier<int> dataVersion = ValueNotifier(0);

  /// Everything logged by the signed-in user as plain data, for exporting.
  /// Targets and notification choices are included; the password never is.
  Map<String, dynamic> exportAll() => {
        'exportedAt': DateTime.now().toIso8601String(),
        for (final name in BellaService.loggedDataKeys) name: _readList(name),
        'targets': readStoredMap('targets'),
        'achievementUnlocks': readStoredMap('achievementUnlocks'),
      };

  /// Deletes the signed-in user's logged data (sleep, water, food, readings,
  /// check-ins, sessions, achievement dates). Goals, targets and notification
  /// choices stay.
  Future<void> clearLoggedData() async {
    await clearStoredKeys([
      ...BellaService.loggedDataKeys,
      'achievementUnlocks',
    ]);
    dataVersion.value++;
  }
}

extension BellaNotificationPrefs on BellaService {
  /// This user's notification choices as stored; empty if never set.
  Map<String, dynamic> getNotificationPrefsMap() =>
      readStoredMap('notificationPrefs');

  Future<void> saveNotificationPrefsMap(Map<String, dynamic> map) =>
      writeStoredMap('notificationPrefs', map);

  /// Whether this user has answered the one-time "meet your band" card.
  bool get bandIntroDismissed =>
      readStoredMap('bandIntro')['dismissed'] == true;

  Future<void> dismissBandIntro() =>
      writeStoredMap('bandIntro', {'dismissed': true});
}

class _Parsed {
  final Object raw;
  final List<Object?> items;
  const _Parsed(this.raw, this.items);
}
