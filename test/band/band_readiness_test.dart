import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_test/flutter_test.dart';
import 'package:sage/band/band_readiness.dart';

void main() {
  test('every adapter state maps to something the picker can show', () {
    for (final s in fbp.BluetoothAdapterState.values) {
      expect(readinessFromAdapter(s), isA<BandReadiness>(), reason: '$s');
    }
  });

  test('only "on" is ready to scan', () {
    for (final s in fbp.BluetoothAdapterState.values) {
      expect(readinessFromAdapter(s) == BandReadiness.ready,
          s == fbp.BluetoothAdapterState.on,
          reason: '$s');
    }
  });

  test('the cases the user can act on are told apart', () {
    expect(
        readinessFromAdapter(fbp.BluetoothAdapterState.off), BandReadiness.off);
    expect(readinessFromAdapter(fbp.BluetoothAdapterState.turningOff),
        BandReadiness.off);
    expect(readinessFromAdapter(fbp.BluetoothAdapterState.unauthorized),
        BandReadiness.unauthorized);
    expect(readinessFromAdapter(fbp.BluetoothAdapterState.unavailable),
        BandReadiness.unsupported);
  });

  test('startup states wait instead of claiming nothing is nearby', () {
    expect(readinessFromAdapter(fbp.BluetoothAdapterState.unknown),
        BandReadiness.checking);
    expect(readinessFromAdapter(fbp.BluetoothAdapterState.turningOn),
        BandReadiness.checking);
  });
}
