// band/band_access.dart
//
// Runtime Bluetooth permission for finding and connecting to the band.
//
// Android 12 and newer will not list paired devices or connect unless the app
// has been granted "Nearby devices" (BLUETOOTH_SCAN and BLUETOOTH_CONNECT)
// at runtime, declaring them in the manifest is not enough. Without them the
// band simply never appears. iOS asks by itself the first time Bluetooth is
// used, so nothing is requested there.
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

enum BandAccess {
  granted,

  /// Not granted yet but the system will still show its prompt.
  askable,

  /// Denied for good: only Settings can change it.
  blocked,
}

/// Combines the two Android permissions into one answer.
BandAccess bandAccessFrom(PermissionStatus scan, PermissionStatus connect) {
  bool ok(PermissionStatus s) =>
      s == PermissionStatus.granted || s == PermissionStatus.limited;
  if (ok(scan) && ok(connect)) return BandAccess.granted;
  bool stuck(PermissionStatus s) =>
      s == PermissionStatus.permanentlyDenied ||
      s == PermissionStatus.restricted;
  if (stuck(scan) || stuck(connect)) return BandAccess.blocked;
  return BandAccess.askable;
}

/// Where the answer comes from, so tests can stand in for the system.
abstract class BandPermissionSource {
  Future<(PermissionStatus, PermissionStatus)> status();
  Future<(PermissionStatus, PermissionStatus)> request();
}

class SystemBandPermissions implements BandPermissionSource {
  @override
  Future<(PermissionStatus, PermissionStatus)> status() async => (
        await Permission.bluetoothScan.status,
        await Permission.bluetoothConnect.status,
      );

  @override
  Future<(PermissionStatus, PermissionStatus)> request() async {
    final result =
        await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    return (
      result[Permission.bluetoothScan] ?? PermissionStatus.denied,
      result[Permission.bluetoothConnect] ?? PermissionStatus.denied,
    );
  }
}

/// Current access, asking the user first when [ask] is true and the system
/// still allows a prompt. iOS is always "granted" here.
Future<BandAccess> bandAccess({
  bool ask = false,
  BandPermissionSource? source,
  bool? isAndroid,
}) async {
  if (!(isAndroid ?? Platform.isAndroid)) return BandAccess.granted;
  final s = source ?? SystemBandPermissions();
  var (scan, connect) = await s.status();
  var access = bandAccessFrom(scan, connect);
  if (access == BandAccess.askable && ask) {
    (scan, connect) = await s.request();
    access = bandAccessFrom(scan, connect);
  }
  return access;
}
