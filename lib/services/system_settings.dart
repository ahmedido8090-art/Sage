// services/system_settings.dart
//
// The one place that opens the phone's own settings, so screens ask for "fix
// this permission" without knowing about the plugin behind it.
import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';

class SystemSettings {
  SystemSettings._();

  static Future<void> openNotifications() =>
      _open(AppSettingsType.notification);

  static Future<void> openBluetooth() => _open(AppSettingsType.bluetooth);

  static Future<void> openApp() => _open(AppSettingsType.settings);

  static Future<void> _open(AppSettingsType type) async {
    try {
      await AppSettings.openAppSettings(type: type);
    } catch (e) {
      debugPrint('Could not open system settings: $e');
    }
  }
}
