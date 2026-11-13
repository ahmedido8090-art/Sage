// notifications/notification_service.dart
//
// Orchestrates Sage's nudges: reads the signed-in user's choices and today's
// progress, asks the planner what to send, and hands that to the gateway.
//
// The schedule is rebuilt (cancel everything, plan a week, schedule) whenever
// something it depends on changes: settings, sign-in, app resume, and after
// the user logs something. A rebuild is cheap and keeps "already did it
// today" skips accurate without any background work.
import 'package:flutter/foundation.dart';
import '../services/bella_service.dart';
import '../services/user_service.dart';
import '../utils/health_metrics.dart';
import 'message_bank.dart';
import 'notification_category.dart';
import 'notification_gateway.dart';
import 'notification_prefs.dart';
import 'schedule_planner.dart';

class NotificationService {
  NotificationService({NotificationGateway? gateway, BellaService? bella})
      : _gateway = gateway ?? LocalNotificationsGateway(),
        _bella = bella ?? BellaService();

  static final NotificationService instance = NotificationService();

  final NotificationGateway _gateway;
  final BellaService _bella;

  /// Set when the user taps a notification; the Home screen routes on it and
  /// then clears it.
  final ValueNotifier<NotificationCategory?> tapped = ValueNotifier(null);

  /// Latest known OS permission, for the settings screen.
  final ValueNotifier<NotificationPermission> permission =
      ValueNotifier(NotificationPermission.notGranted);

  bool _initialized = false;
  Future<void> _queue = Future.value();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _gateway.init(onTap: _onTap);
      permission.value = await _gateway.permission();
      final launch =
          NotificationCategory.fromId(await _gateway.launchPayload());
      if (launch != null) tapped.value = launch;
    } catch (e, st) {
      // Notifications are a nicety: never stop the app from starting.
      debugPrint('NotificationService.init failed: $e\n$st');
    }
  }

  void _onTap(String? payload) {
    final category = NotificationCategory.fromId(payload);
    if (category != null) tapped.value = category;
  }

  // ── Preferences ─────────────────────────────────────────────────────────

  NotificationPrefs get prefs =>
      NotificationPrefs.fromMap(_bella.getNotificationPrefsMap());

  Future<void> savePrefs(NotificationPrefs next) async {
    await _bella.saveNotificationPrefsMap(next.toMap());
    await refresh();
  }

  /// Asks for permission, and if granted turns Sage's nudges on. Returns
  /// whether they are now on.
  Future<bool> enable() async {
    final result = await _gateway.requestPermission();
    permission.value = result;
    if (result != NotificationPermission.granted) return false;
    await savePrefs(prefs.copyWith(enabled: true, promptDismissed: true));
    return true;
  }

  Future<void> disable() => savePrefs(prefs.copyWith(enabled: false));

  Future<void> dismissPrompt() async {
    await _bella.saveNotificationPrefsMap(
        prefs.copyWith(promptDismissed: true).toMap());
  }

  Future<void> refreshPermission() async {
    try {
      permission.value = await _gateway.permission();
    } catch (_) {}
  }

  // ── Scheduling ──────────────────────────────────────────────────────────

  /// Rebuilds the schedule. Calls are serialised so two quick refreshes
  /// cannot interleave their cancel and schedule steps.
  Future<void> refresh({DateTime? now}) {
    final next = _queue.then((_) => _rebuild(now ?? DateTime.now()));
    _queue = next.catchError((_) {});
    return next;
  }

  Future<void> _rebuild(DateTime now) async {
    if (!_initialized) return;
    try {
      await _gateway.cancelAll();
      if (UserService().currentUser == null) return;

      final current = prefs;
      if (!current.enabled) return;

      permission.value = await _gateway.permission();
      if (permission.value != NotificationPermission.granted) return;

      final result = SchedulePlanner.plan(
        prefs: current,
        now: now,
        today: todayState(now),
      );
      for (final n in result.notifications) {
        await _gateway.schedule(n);
      }
      // Keep the rotation moving across restarts.
      await _bella.saveNotificationPrefsMap(
          current.copyWith(messageCursors: result.cursors).toMap());
    } catch (e, st) {
      debugPrint('NotificationService.refresh failed: $e\n$st');
    }
  }

  /// What is coming up, for the settings screen. Does not schedule anything
  /// or advance the message rotation.
  List<PlannedNotification> upcoming({int limit = 3, DateTime? now}) {
    final at = now ?? DateTime.now();
    return SchedulePlanner.plan(
      prefs: prefs,
      now: at,
      today: todayState(at),
      days: 3,
    ).notifications.take(limit).toList();
  }

  Future<void> cancelAll() {
    final next = _queue.then((_) async {
      if (_initialized) await _gateway.cancelAll();
    });
    _queue = next.catchError((_) {});
    return next;
  }

  /// Shows one now so the user can see how Sage will sound and look.
  Future<void> sendTest() async {
    final today = todayState(DateTime.now());
    final category = NotificationCategory.values[
        DateTime.now().millisecond % NotificationCategory.values.length];
    final pool = MessageBank.messages[category]!;
    final message = MessageBank.fill(
      pool[DateTime.now().microsecond % pool.length],
      name: today.name,
      streak: today.streakDays,
    );
    await _gateway.showNow(category, message);
  }

  // ── Reading today's state ───────────────────────────────────────────────

  @visibleForTesting
  TodayState todayState(DateTime now) {
    final sessions = _bella.getSessions();
    bool sameDay(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    final waterTarget = _bella.getTarget<int>('waterMl') ?? 2000;
    return TodayState(
      waterGoalMet: _bella.todayWaterMl() >= waterTarget,
      movedToday: sessions.any((s) => s.type == 'walking' && sameDay(s.date)),
      activeToday: sessions.any((s) => sameDay(s.date)),
      checkedInToday: _bella.hasCheckedInToday(),
      streakDays: streakEndingToday(sessions.map((s) => dayKey(s.date)).toSet(),
          now: now),
      name: _friendlyName(UserService().currentUser),
    );
  }

  static String _friendlyName(String? username) {
    if (username == null || username.isEmpty) return 'friend';
    // Usernames like "ana_92" are not names; only use clean ones.
    if (!RegExp(r'^[A-Za-z]{2,20}$').hasMatch(username)) return 'friend';
    return username[0].toUpperCase() + username.substring(1).toLowerCase();
  }
}
