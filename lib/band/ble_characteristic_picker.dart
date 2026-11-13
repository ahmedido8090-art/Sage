// band/ble_characteristic_picker.dart
//
// Chooses which BLE characteristic carries the band's data. Pure and free of
// the Bluetooth plugin so the rules can be tested.
//
// The band streams text lines over a serial-over-BLE service. iOS lists a
// device's services in no promised order and exposes generic ones (such as
// Device Information) that have readable characteristics, so "the first
// readable thing" can be the wrong one and the band would then connect but
// never deliver a reading. Preference order:
//   1. a known UART notify characteristic (HM-10/AT-09 FFE1, Nordic UART TX)
//   2. any other characteristic that notifies
//   3. a readable characteristic, as a last resort, outside the generic
//      information services
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

final _knownUartNotify = {
  normalizeBleUuid('ffe1'), // HM-10 / AT-09 and clones
  '6e400003-b5a3-f393-e0a9-e50e24dcca9e', // Nordic UART TX (device -> app)
};

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
        _knownUartNotify.contains(normalizeBleUuid(c.characteristic))) {
      return i;
    }
  }
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
