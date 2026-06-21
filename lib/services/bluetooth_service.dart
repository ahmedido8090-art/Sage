// services/bluetooth_service.dart (UPDATED FOR NEW ARDUINO FORMAT)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';
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
  StreamSubscription? _bleConnSub;
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
  int _calories = 0;
  double _irValue = 0;
  int _lastSimulatedSteps = 0;
  DateTime _lastStepTime = DateTime.now();

  // -----------------------------------------------------------------------
  // PERMISSIONS (Helper)
  // -----------------------------------------------------------------------
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    } else if (Platform.isIOS) {
      await Permission.locationWhenInUse.request();
    }
  }

  // -----------------------------------------------------------------------
  // SCANNING LOGIC
  // -----------------------------------------------------------------------
  Future<void> startScan() async {
    await requestPermissions();

    if (Platform.isAndroid) {
      _bluetooth ??= FlutterBluetoothSerial.instance;

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
        if (kDebugMode) {
          print("Error getting bonded devices: $e");
        }
        _scanController.add([]);
      }
    } else if (Platform.isIOS) {
      try {
        if (await fbp.FlutterBluePlus.adapterState.first !=
            fbp.BluetoothAdapterState.on) {
          await fbp.FlutterBluePlus.adapterState
              .where((state) => state == fbp.BluetoothAdapterState.on)
              .first
              .timeout(const Duration(seconds: 3));
        }
      } catch (e) {
        if (kDebugMode) {
          print("Bluetooth adapter not ready or permission denied: $e");
        }
        _scanController.add([]);
        return;
      }

      _scanController.add([]);

      try {
        await fbp.FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 5),
        );
      } catch (e) {
        if (kDebugMode) {
          print("Start scan failed: $e");
        }
      }

      fbp.FlutterBluePlus.scanResults.listen((results) {
        final validResults =
            results.where((r) => r.device.platformName.isNotEmpty).toList();
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

      final services = await device.discoverServices();
      fbp.BluetoothCharacteristic? rx;

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
  // DATA PARSING - UPDATED FOR NEW ARDUINO FORMAT
  // -----------------------------------------------------------------------
  void _onData(Uint8List data) {
    try {
      _buffer += utf8.decode(data, allowMalformed: true);
      if (kDebugMode) {
        print("📡 RAW DATA: ${String.fromCharCodes(data)}");
      }
    } catch (e) {
      print("Error decoding data: $e");
    }

    int index;
    while ((index = _buffer.indexOf('\n')) != -1) {
      final line = _buffer.substring(0, index).trim();
      _buffer = _buffer.substring(index + 1);

      if (line.isEmpty) continue;

      if (kDebugMode) {
        print("📋 LINE RECEIVED: $line");
      }
      _parseLine(line);
    }
  }

  void _simulateStepsFromAcceleration(int ax, int ay, int az) {
    // Simple step simulation from acceleration
    final magnitude = sqrt(ax * ax + ay * ay + az * az);
    final timeDiff = DateTime.now().difference(_lastStepTime).inSeconds;

    // If there's significant movement and enough time passed, add a step
    if (magnitude > 15000 && timeDiff > 1) {
      _steps++;
      _lastStepTime = DateTime.now();
      print("👣 Simulated step from acceleration. Total: $_steps");
    }

    _lastSimulatedSteps = _steps;
  }

  void _parseLine(String line) {
    // TRY BOTH FORMATS:
    // 1. New format: "STEPS:123,IR:50000,BPM:75"
    // 2. Old format: "AX:123,AY:456,AZ:789,IR:50000,BPM:75"

    try {
      final parts = line.split(',');
      int? bpm;
      int? ir;
      int? steps;
      int? ax, ay, az; // For old format

      for (final p in parts) {
        final kv = p.split(':');
        if (kv.length != 2) continue;

        final key = kv[0].trim().toUpperCase();
        final value = kv[1].trim();

        if (key == 'BPM' || key == 'HR') {
          bpm = int.tryParse(value);
        } else if (key == 'IR') {
          ir = int.tryParse(value);
          if (ir != null) _irValue = ir.toDouble();
        } else if (key == 'STEPS' || key == 'ST') {
          steps = int.tryParse(value);
        } else if (key == 'AX') {
          ax = int.tryParse(value);
        } else if (key == 'AY') {
          ay = int.tryParse(value);
        } else if (key == 'AZ') {
          az = int.tryParse(value);
        }
      }

      // Update steps (from STEPS if available, or simulate from acceleration)
      if (steps != null) {
        _steps = steps;
      } else if (ax != null && ay != null && az != null) {
        // Simulate step counting from acceleration (old format fallback)
        _simulateStepsFromAcceleration(ax!, ay!, az!);
      }

      // Update heart rate
      if (bpm != null && bpm > 0) {
        _heartRate = bpm;
      }

      // --- FIXED CALORIE CALCULATION HERE ---
      // Ensure we calculate using the LATEST _steps value
      _calories = (_steps * 0.04).toInt();
      // --------------------------------------

      // Store data if we have valid readings
      if (bpm != null) {
        DataStorageService().saveBandData(
          heartRate: _heartRate,
          steps: _steps,
          timestamp: DateTime.now(),
        );
      }

      // Broadcast new data to the app
      _dataController.add(
        HealthData(
          heartRate: _heartRate,
          steps: _steps,
          isConnected: isConnected.value,
          calories: _calories.toDouble(),
          sleepHours: 0,
          spo2: 98, // Default value
          temperature: 36.7, // Default value
          batteryLevel: 78, // Default value
        ),
      );

      if (kDebugMode) {
        print("✅ PARSED DATA: HR=$_heartRate, Steps=$_steps, Cal=$_calories");
      }
    } catch (e) {
      print("❌ Error parsing line '$line': $e");
    }
  }

  // -----------------------------------------------------------------------
  // UTILITY METHODS
  // -----------------------------------------------------------------------
  Future<void> sendCommand(String command) async {
    if (!isConnected.value) return;

    try {
      if (_connection != null && _connection!.isConnected) {
        _connection!.output.add(Uint8List.fromList(utf8.encode('$command\n')));
        await _connection!.output.allSent;
      } else if (_bleRxChar != null) {
        await _bleRxChar!.write(utf8.encode('$command\n'));
      }
    } catch (e) {
      print("Error sending command: $e");
    }
  }

  Future<void> resetStepCounter() async {
    await sendCommand("RESET_STEPS");
    _steps = 0;
    _calories = 0; // Reset calories too
  }

  Future<void> requestData() async {
    await sendCommand("GET_DATA");
  }

  void dispose() {
    _dataController.close();
    disconnect();
    _scanController.close();
    _readSub?.cancel();
    _bleConnSub?.cancel();
    _bleNotifSub?.cancel();
  }
}
