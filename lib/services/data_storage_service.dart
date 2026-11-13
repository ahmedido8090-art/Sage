// services/data_storage_service.dart
//
// Band telemetry (heart rate + steps) in SharedPreferences, scoped per user.
//
// Everything else the app records (sessions, check-ins, sleep, water, food,
// targets) lives in BellaService. This store used to also keep walking /
// meditation / breathwork sessions, daily goals and user stats, but nothing
// ever read them back, so they were removed.
//
// Keys are suffixed with the signed-in username so two accounts on one device
// never see each other's readings. When nobody is signed in, writes are
// dropped and reads are empty: the band can keep streaming after logout, but
// those readings belong to no one.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_service.dart';

class DataStorageService {
  static final DataStorageService _instance = DataStorageService._internal();
  factory DataStorageService() => _instance;
  DataStorageService._internal();

  static const String _bandDataKey = 'sage_band_data';
  static const int _maxBandEntries = 10000;

  /// Serialises read-modify-write cycles so back-to-back band readings can't
  /// overwrite each other.
  Future<void> _pending = Future.value();

  String? get _user => UserService().currentUser;

  String _scopedKey(String user) => '$_bandDataKey::$user';

  /// Band data written before storage was per-user lived under one global
  /// key. The first signed-in user to touch the store adopts it, then the
  /// global key is removed, so existing history isn't lost.
  Future<void> _adoptLegacyBandData(
      SharedPreferences prefs, String user) async {
    final legacy = prefs.getStringList(_bandDataKey);
    if (legacy == null) return;
    final scoped = _scopedKey(user);
    if (prefs.getStringList(scoped) == null) {
      await prefs.setStringList(scoped, legacy);
    }
    await prefs.remove(_bandDataKey);
  }

  Future<void> saveBandData({
    required int heartRate,
    required int steps,
    required DateTime timestamp,
  }) {
    final user = _user;
    if (user == null) return Future.value();

    final next = _pending.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await _adoptLegacyBandData(prefs, user);

      final key = _scopedKey(user);
      final existing = prefs.getStringList(key) ?? [];
      existing.add(jsonEncode({
        'hr': heartRate.toString(),
        'steps': steps.toString(),
        'time': timestamp.millisecondsSinceEpoch.toString(),
      }));
      if (existing.length > _maxBandEntries) {
        existing.removeRange(0, existing.length - _maxBandEntries);
      }
      await prefs.setStringList(key, existing);
    });
    _pending = next.catchError((_) {});
    return next;
  }

  Future<List<Map<String, dynamic>>> getBandData({int daysBack = 1}) async {
    final user = _user;
    if (user == null) return [];

    await _pending;
    final prefs = await SharedPreferences.getInstance();
    await _adoptLegacyBandData(prefs, user);

    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    final out = <Map<String, dynamic>>[];
    for (final entry in prefs.getStringList(_scopedKey(user)) ?? const []) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        final time =
            DateTime.fromMillisecondsSinceEpoch(int.parse(map['time']));
        if (!time.isAfter(cutoff)) continue;
        out.add({
          'hr': int.parse(map['hr']),
          'steps': int.parse(map['steps']),
          'time': time,
        });
      } catch (_) {
        // Skip a corrupt entry instead of failing the whole read.
      }
    }
    return out;
  }

  /// Deletes the current user's band telemetry.
  Future<void> clearBandData() async {
    final user = _user;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scopedKey(user));
  }
}
