// band/ble_characteristic_picker.dart
//
// Chooses which BLE characteristic carries the band's data. Pure and free of
// the Bluetooth plugin so the rules can be tested.
//
// This follows the order that worked on iPhone: the first characteristic that
// can notify (falling back to the first readable one), with one safeguard.
// iOS may list generic services such as Device Information, whose readable
// characteristics are never band data, so those and the battery level are
// skipped. A characteristic that notifies is preferred over one that can only
// be read, because only a notifying one can stream.
class BleCandidate {
  final String service;
  final String characteristic;
  final bool notify;
  final bool read;

  const BleCandidate({
    required this.service,
    required this.characteristic,
    required this.notify,
    required this.read,
  });
}

const _bluetoothBase = '-0000-1000-8000-00805f9b34fb';

/// Lower-case 128-bit form of a 16-bit, 32-bit or full UUID string.
String normalizeBleUuid(String uuid) {
  final u = uuid.toLowerCase().replaceAll('{', '').replaceAll('}', '');
  if (u.length == 4) return '0000$u$_bluetoothBase';
  if (u.length == 8) return '$u$_bluetoothBase';
  return u;
}

// Generic services that never carry band data: Generic Access, Generic
// Attribute, Device Information.
final _genericServices = {
  normalizeBleUuid('1800'),
  normalizeBleUuid('1801'),
  normalizeBleUuid('180a'),
};

// Standard notifying characteristics that are housekeeping, not data.
final _housekeeping = {
  normalizeBleUuid('2a05'), // Service Changed
  normalizeBleUuid('2a19'), // Battery Level
};

/// Index into [candidates] of the characteristic to listen to, or null if
/// none can carry data.
int? pickBleDataCharacteristic(List<BleCandidate> candidates) {
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i];
    if (c.notify &&
        !_housekeeping.contains(normalizeBleUuid(c.characteristic)) &&
        !_genericServices.contains(normalizeBleUuid(c.service))) {
      return i;
    }
  }
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i];
    if (c.read && !_genericServices.contains(normalizeBleUuid(c.service))) {
      return i;
    }
  }
  return null;
}
