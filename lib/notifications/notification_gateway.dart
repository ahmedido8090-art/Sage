// notifications/notification_gateway.dart
//
// The only file that talks to flutter_local_notifications. Everything else
// depends on this interface, so the plugin can be swapped or faked in tests.
import 'dart:io';
import 'dart:ui' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'message_bank.dart';
import 'notification_category.dart';
import 'schedule_planner.dart';

enum NotificationPermission { granted, notGranted }

abstract class NotificationGateway {
  /// Prepares channels and time zones. [onTap] receives a notification's
  /// payload (a category id) when the user taps it.
  Future<void> init({required void Function(String? payload) onTap});

  /// Payload of the notification that launched the app, if any.
  Future<String?> launchPayload();

  Future<NotificationPermission> permission();

  /// Shows the system permission prompt where the platform has one.
  Future<NotificationPermission> requestPermission();

  Future<void> schedule(PlannedNotification notification);

  Future<void> showNow(NotificationCategory category, NotificationMessage m);

  Future<void> cancelAll();

  Future<int> pendingCount();
}

class LocalNotificationsGateway implements NotificationGateway {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _androidIcon = 'ic_stat_sage';

  /// A mid-green that stays legible as the accent in both the light and dark
  /// system notification shades.
  static const Color _accent = Color(0xFF3BB77E);

  @override
  Future<void> init({required void Function(String? payload) onTap}) async {
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_androidIcon),
        // Permission is requested from the settings screen, never at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => onTap(r.payload),
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    for (final c in NotificationCategory.values) {
      await android?.createNotificationChannel(AndroidNotificationChannel(
        c.id,
        c.label,
        description: c.description,
        importance: Importance.defaultImportance,
      ));
    }
  }

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp == true
        ? details?.notificationResponse?.payload
        : null;
  }

  @override
  Future<NotificationPermission> permission() async {
    bool? enabled;
    if (Platform.isAndroid) {
      enabled = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
    } else if (Platform.isIOS) {
      enabled = (await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.checkPermissions())
          ?.isEnabled;
    }
    return enabled == true
        ? NotificationPermission.granted
        : NotificationPermission.notGranted;
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    bool? granted;
    if (Platform.isAndroid) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    return granted == true
        ? NotificationPermission.granted
        : await permission();
  }

  NotificationDetails _details(
      NotificationCategory category, NotificationMessage m) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        category.id,
        category.label,
        channelDescription: category.description,
        icon: _androidIcon,
        color: _accent,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(m.body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
    );
  }

  @override
  Future<void> schedule(PlannedNotification n) {
    return _plugin.zonedSchedule(
      id: n.id,
      scheduledDate: tz.TZDateTime.from(n.at, tz.local),
      notificationDetails: _details(n.category, n.message),
      // Inexact on purpose: a reminder a few minutes late is fine, and it
      // avoids the exact-alarm permission that Android 12+ gates.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: n.message.title,
      body: n.message.body,
      payload: n.category.id,
    );
  }

  @override
  Future<void> showNow(NotificationCategory category, NotificationMessage m) {
    return _plugin.show(
      id: 999999,
      title: m.title,
      body: m.body,
      notificationDetails: _details(category, m),
      payload: category.id,
    );
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<int> pendingCount() async =>
      (await _plugin.pendingNotificationRequests()).length;
}
