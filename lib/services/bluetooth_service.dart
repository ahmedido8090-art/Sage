// services/bluetooth_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../models/health_data.dart';
import 'data_storage_service.dart';

/// A unified wrapper for both Android (Classic) and iOS (BLE) devices
class SageDevice {
  final String name;
  final String id; // Mac address or UUID
  final bool isBle;
  final dynamic originalDevice; // BluetoothDevice or fbp.BluetoothDevice
  final int rssi;

  SageDevice({
    required this.name,
    required this.id,
    required this.isBle,
    required this.originalDevice,
    this.rssi = 0,
  });
}

class BluetoothService {
  BluetoothService._internal();
  static final BluetoothService instance = BluetoothService._internal();

  // --- Android (Classic) ---
  FlutterBluetoothSerial? _bluetooth;
  BluetoothConnection? _connection;
  StreamSubscription? _readSub;

  // --- iOS (BLE) ---
  fbp.BluetoothDevice? _bleDevice;
  fbp.BluetoothCharacteristic? _bleRxChar;
  StreamSubscription<fbp.BluetoothConnectionState>? _bleConnSub;
  StreamSubscription<List<int>>? _bleNotifSub;

  // --- Scanning & State ---
  final StreamController<List<SageDevice>> _scanController =
      StreamController.broadcast();
  Stream<List<SageDevice>> get scanResults => _scanController.stream;

  final StreamController<HealthData> _dataController =
      StreamController.broadcast();
  Stream<HealthData> get dataStream => _dataController.stream;

  final ValueNotifier<bool> isConnected = ValueNotifier(false);

  // Internal buffer & data
  String _buffer = '';
  int _heartRate = 0;
  int _steps = 0;

  // -----------------------------------------------------------------------
  // SCANNING LOGIC
  // -----------------------------------------------------------------------

  /// Starts scanning for devices compatible with the current platform
  Future<void> startScan() async {
    if (Platform.isAndroid) {
      // On Android, we primarily look for paired (bonded) HC-05 devices
      _bluetooth ??= FlutterBluetoothSerial.instance;

      // Check if enabled
      bool? enabled = await _bluetooth!.isEnabled;
      if (enabled != true) await _bluetooth?.requestEnable();

      try {
        final bonded = await _bluetooth!.getBondedDevices();
        final sageDevices = bonded.map((d) {
          return SageDevice(
            name: d.name ?? "Unknown Device",
            id: d.address,
            isBle: false,
            originalDevice: d,
          );
        }).toList();

        _scanController.add(sageDevices);
      } catch (e) {
        _scanController.add([]);
        if (kDebugMode) {
          print("Error getting bonded devices: $e");
        }
      }
    } else if (Platform.isIOS) {
      // On iOS, we scan for BLE peripherals.
      // FIX: Wait for Bluetooth to be 'ON' before scanning to avoid CBManagerStateUnknown.
      try {
        // Wait up to 3 seconds for the adapter to be ready
        await fbp.FlutterBluePlus.adapterState
            .where((state) => state == fbp.BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        if (kDebugMode) {
          print("Bluetooth adapter not ready or permission denied: $e");
        }
        _scanController.add([]);
        return;
      }

      // Clear previous results
      _scanController.add([]);

      // Start scan
      try {
        await fbp.FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 5),
        );
      } catch (e) {
        if (kDebugMode) {
          print("Start scan failed: $e");
        }
      }

      // Listen to BLE results and map them to SageDevices
      fbp.FlutterBluePlus.scanResults.listen((results) {
        // Filter out devices with no name to keep the list clean
        final validResults = results
            .where((r) => r.device.platformName.isNotEmpty)
            .toList();

        // Sort by signal strength (closest first)
        validResults.sort((a, b) => b.rssi.compareTo(a.rssi));

        final sageDevices = validResults.map((r) {
          return SageDevice(
            name: r.device.platformName,
            id: r.device.remoteId.str,
            isBle: true,
            originalDevice: r.device,
            rssi: r.rssi,
          );
        }).toList();

        _scanController.add(sageDevices);
      });
    }
  }

  Future<void> stopScan() async {
    if (Platform.isIOS) {
      try {
        await fbp.FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    // Android getBondedDevices is instantaneous, so no stop needed
  }

  // -----------------------------------------------------------------------
  // CONNECTION LOGIC
  // -----------------------------------------------------------------------

  Future<void> connect(SageDevice device) async {
    if (isConnected.value) return;

    if (device.isBle) {
      await _connectBle(device.originalDevice as fbp.BluetoothDevice);
    } else {
      await _connectClassic(device.originalDevice as BluetoothDevice);
    }
  }

  Future<void> _connectClassic(BluetoothDevice device) async {
    try {
      final connection = await BluetoothConnection.toAddress(device.address);
      _connection = connection;
      isConnected.value = true;

      _readSub = connection.input?.listen(
        _onData,
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
      );
    } catch (e) {
      _handleDisconnect();
      rethrow;
    }
  }

  Future<void> _connectBle(fbp.BluetoothDevice device) async {
    try {
      _bleDevice = device;
      await device.connect(timeout: const Duration(seconds: 10));

      _bleConnSub = device.connectionState.listen((state) {
        if (state == fbp.BluetoothConnectionState.connected) {
          isConnected.value = true;
        } else if (state == fbp.BluetoothConnectionState.disconnected) {
          _handleDisconnect();
        }
      });

      // Discover Services
      final services = await device.discoverServices();
      fbp.BluetoothCharacteristic? rx;

      // Find a read/notify characteristic (HM-10 / AT-09 generic)
      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.properties.notify || c.properties.read) {
            rx = c;
            break;
          }
        }
        if (rx != null) break;
      }

      if (rx == null) throw Exception("No suitable characteristic found");

      _bleRxChar = rx;

      if (rx.properties.notify) {
        await rx.setNotifyValue(true);
        _bleNotifSub = rx.lastValueStream.listen((value) {
          if (value.isNotEmpty) _onData(Uint8List.fromList(value));
        });
      } else {
        // Fallback for read-only
        final value = await rx.read();
        if (value.isNotEmpty) _onData(Uint8List.fromList(value));
      }
    } catch (e) {
      await _disconnectBleInternal();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await _readSub?.cancel();
      _readSub = null;
      await _connection?.close();
      _connection = null;
      await _disconnectBleInternal();
    } finally {
      isConnected.value = false;
    }
  }

  void _handleDisconnect() {
    isConnected.value = false;
    _connection = null;
    _disconnectBleInternal();
  }

  Future<void> _disconnectBleInternal() async {
    try {
      await _bleNotifSub?.cancel();
      _bleNotifSub = null;
      await _bleConnSub?.cancel();
      _bleConnSub = null;
      await _bleDevice?.disconnect();
    } catch (_) {
    } finally {
      _bleDevice = null;
      _bleRxChar = null;
    }
  }

  // -----------------------------------------------------------------------
  // DATA PARSING
  // -----------------------------------------------------------------------

  void _onData(Uint8List data) {
    _buffer += utf8.decode(data, allowMalformed: true);
    int index;
    while ((index = _buffer.indexOf('\n')) != -1) {
      final line = _buffer.substring(0, index).trim();
      _buffer = _buffer.substring(index + 1);
      if (line.isEmpty) continue;
      _parseLine(line);
    }
  }

  void _parseLine(String line) {
    // Expected: HR:XX,AX:XXXXX,AY:XXXXX,AZ:XXXXX,GX:XXXXX,GY:XXXXX,GZ:XXXXX,ST:XXXXX
    try {
      final parts = line.split(',');
      int? hr;
      int? st;

      for (final p in parts) {
        final kv = p.split(':');
        if (kv.length != 2) continue;
        final key = kv[0].trim();
        final value = kv[1].trim();

        if (key == 'HR') hr = int.tryParse(value);
        if (key == 'ST') st = int.tryParse(value);
      }

      if (hr != null) _heartRate = hr;
      if (st != null) _steps = st;

      // Store the data persistently
      if (hr != null) {
        DataStorageService().saveBandData(
          heartRate: hr,
          steps: _steps,
          timestamp: DateTime.now(),
        );
      }

      _dataController.add(
        HealthData(
          heartRate: _heartRate,
          steps: _steps,
          isConnected: isConnected.value,
          calories: _steps * 0.04,
          sleepHours: 0,
        ),
      );
    } catch (_) {}
  }

  void dispose() {
    _dataController.close();
    disconnect();
    _scanController.close();
  }
}