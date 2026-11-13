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

  test('a typical HM-10 style module picks its only characteristic', () {
    expect(
        pickBleDataCharacteristic(
            [c('ffe0', 'ffe1', notify: true, read: true)]),
        0);
  });

  test('follows the order the device lists, as the original did', () {
    // Two notifying characteristics: the first listed wins, exactly like the
    // "first notify-or-read" rule that connected on iPhone.
    expect(
        pickBleDataCharacteristic([
          c('fff0', 'fff4', notify: true),
          c('ffe0', 'ffe1', notify: true),
        ]),
        0);
  });

  test('skips a readable Device Information characteristic listed first', () {
    expect(
        pickBleDataCharacteristic([
          c('180a', '2a29', read: true),
          c('180a', '2a24', read: true),
          c('ffe0', 'ffe1', notify: true, read: true),
        ]),
        2);
  });

  test('prefers a notifying characteristic over a readable one before it', () {
    expect(
        pickBleDataCharacteristic([
          c('fff0', 'fff1', read: true),
          c('ffe0', 'ffe1', notify: true),
        ]),
        1);
  });

  test('skips battery level and service changed notifications', () {
    expect(
        pickBleDataCharacteristic([
          c('1801', '2a05', notify: true),
          c('180f', '2a19', notify: true, read: true),
          c('fff0', 'fff4', notify: true),
        ]),
        2);
  });

  test('reads a custom readable characteristic only as a last resort', () {
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
}
