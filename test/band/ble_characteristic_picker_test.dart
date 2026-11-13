import 'package:flutter_test/flutter_test.dart';
import 'package:sage/band/ble_characteristic_picker.dart';

BleCandidate c(String service, String char,
        {bool notify = false, bool read = false}) =>
    BleCandidate(
        service: service, characteristic: char, notify: notify, read: read);

void main() {
  test('normalizes short and long UUIDs to one form', () {
    expect(normalizeBleUuid('FFE1'), '0000ffe1-0000-1000-8000-00805f9b34fb');
    expect(normalizeBleUuid('0000ffe1-0000-1000-8000-00805f9b34fb'),
        '0000ffe1-0000-1000-8000-00805f9b34fb');
    expect(normalizeBleUuid('{FFE1}'), '0000ffe1-0000-1000-8000-00805f9b34fb');
  });

  test('picks the HM-10 UART even when a readable info characteristic is first',
      () {
    final i = pickBleDataCharacteristic([
      c('180a', '2a29', read: true), // Device Information: manufacturer
      c('180a', '2a24', read: true),
      c('ffe0', 'ffe1', notify: true, read: true),
    ]);
    expect(i, 2);
  });

  test('picks the UART over an earlier unrelated notifying characteristic', () {
    final i = pickBleDataCharacteristic([
      c('180f', '2a19', notify: true, read: true), // battery
      c('fff0', 'fff4', notify: true),
      c('ffe0', 'FFE1', notify: true),
    ]);
    expect(i, 2);
  });

  test('recognises the Nordic UART TX characteristic', () {
    final i = pickBleDataCharacteristic([
      c('180a', '2a29', read: true),
      c('6e400001-b5a3-f393-e0a9-e50e24dcca9e',
          '6E400002-B5A3-F393-E0A9-E50E24DCCA9E'), // RX (write only)
      c('6e400001-b5a3-f393-e0a9-e50e24dcca9e',
          '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
          notify: true),
    ]);
    expect(i, 2);
  });

  test('falls back to any notifying characteristic that is not housekeeping',
      () {
    final i = pickBleDataCharacteristic([
      c('1801', '2a05', notify: true), // Service Changed
      c('180f', '2a19', notify: true), // Battery Level
      c('fff0', 'fff4', notify: true),
    ]);
    expect(i, 2);
  });

  test(
      'uses a readable characteristic only as a last resort, and not an info one',
      () {
    expect(
        pickBleDataCharacteristic([
          c('180a', '2a29', read: true),
          c('fff0', 'fff1', read: true),
        ]),
        1);
    expect(pickBleDataCharacteristic([c('180a', '2a29', read: true)]), isNull);
  });

  test('returns null when nothing can carry data', () {
    expect(pickBleDataCharacteristic(const []), isNull);
    expect(pickBleDataCharacteristic([c('fff0', 'fff2')]), isNull);
  });

  test('a notify-only UART still beats a readable one listed before it', () {
    final i = pickBleDataCharacteristic([
      c('fff0', 'fff1', read: true),
      c('ffe0', 'ffe1', notify: true),
    ]);
    expect(i, 1);
  });
}
