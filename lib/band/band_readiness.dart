// band/band_readiness.dart
//
// Whether this phone's Bluetooth is ready for scanning, as the picker needs
// to know it. On iOS the first look at the adapter is also what makes the
// system ask for Bluetooth permission, so the picker asks first and scans only
// once the answer is in, instead of scanning into a prompt and finding nothing.
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

enum BandReadiness {
  /// Waiting on the system (permission prompt, adapter starting up).
  checking,
  ready,

  /// Android: "Nearby devices" has not been granted yet; we can still ask.
  permissionNeeded,
  off,

  /// The user said no to Bluetooth access; only Settings can change that.
  unauthorized,

  /// This device has no usable Bluetooth LE.
  unsupported,
}

BandReadiness readinessFromAdapter(fbp.BluetoothAdapterState state) {
  switch (state) {
    case fbp.BluetoothAdapterState.on:
      return BandReadiness.ready;
    case fbp.BluetoothAdapterState.off:
    case fbp.BluetoothAdapterState.turningOff:
      return BandReadiness.off;
    case fbp.BluetoothAdapterState.unauthorized:
      return BandReadiness.unauthorized;
    case fbp.BluetoothAdapterState.unavailable:
      return BandReadiness.unsupported;
    case fbp.BluetoothAdapterState.unknown:
    case fbp.BluetoothAdapterState.turningOn:
      return BandReadiness.checking;
  }
}
