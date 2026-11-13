// band/band_monitor.dart
//
// The one place the app learns about the band. Screens read this instead of
// each subscribing to the Bluetooth stream and inventing defaults, so they all
// agree on what is live, what is stale and what is simply unknown.
//
// It only reads from the Bluetooth service (through [BandSource]); nothing
// here changes it.
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/health_data.dart';
import '../services/bluetooth_service.dart';
import '../services/data_storage_service.dart';
import 'step_tally.dart';

/// What the monitor needs from the band. The real one wraps
/// [BluetoothService]; tests supply a fake.
abstract class BandSource {
  ValueListenable<bool> get isConnected;
  Stream<HealthData> get dataStream;
}

class BluetoothBandSource implements BandSource {
  final BluetoothService _service;
  BluetoothBandSource(this._service);

  @override
  ValueListenable<bool> get isConnected => _service.isConnected;

  @override
  Stream<HealthData> get dataStream => _service.dataStream;
}

/// A moment-in-time view of the band. Immutable.
class BandSnapshot {
  /// The band is connected right now.
  final bool connected;

  /// The band has connected at some point since the app started, or has
  /// stored readings from before.
  final bool everSeen;

  /// A reading arrived recently enough to call live.
  final bool fresh;

  /// Last heart rate the band reported (bpm), if any.
  final int? heartRate;

  /// Raw lifetime step counter from the band, if any.
  final int? deviceSteps;

  /// Steps taken today, derived from the counter, or null if unknown.
  final int? stepsToday;

  /// When the band last reported anything.
  final DateTime? lastReadingAt;

  const BandSnapshot({
    this.connected = false,
    this.everSeen = false,
    this.fresh = false,
    this.heartRate,
    this.deviceSteps,
    this.stepsToday,
    this.lastReadingAt,
  });

  /// True when numbers on screen can honestly be called live.
  bool get isLive => connected && fresh;

  /// Heart rate only while it is live; null otherwise, so a stale value is
  /// never shown as current.
  int? get liveHeartRate => isLive ? heartRate : null;

  /// For session baselines: the live heart rate, or 0 meaning "not measured".
  int get heartRateOrZero => liveHeartRate ?? 0;

  /// Rough kcal from steps. An estimate, to be labelled as one.
  int? get caloriesEstimate =>
      stepsToday == null ? null : (stepsToday! * 0.04).round();

  BandSnapshot copyWith({
    bool? connected,
    bool? everSeen,
    bool? fresh,
    int? heartRate,
    int? deviceSteps,
    int? stepsToday,
    DateTime? lastReadingAt,
    bool clearSteps = false,
  }) =>
      BandSnapshot(
        connected: connected ?? this.connected,
        everSeen: everSeen ?? this.everSeen,
        fresh: fresh ?? this.fresh,
        heartRate: heartRate ?? this.heartRate,
        deviceSteps: clearSteps ? null : (deviceSteps ?? this.deviceSteps),
        stepsToday: clearSteps ? null : (stepsToday ?? this.stepsToday),
        lastReadingAt: lastReadingAt ?? this.lastReadingAt,
      );
}

class BandMonitor {
  BandMonitor({
    required BandSource source,
    Future<List<StepReading>> Function()? loadHistory,
    Duration freshFor = const Duration(seconds: 30),
    Duration checkEvery = const Duration(seconds: 5),
    DateTime Function()? clock,
  })  : _source = source,
        _loadHistory = loadHistory,
        _freshFor = freshFor,
        _checkEvery = checkEvery,
        _clock = clock ?? DateTime.now;

  /// The app-wide monitor, reading the real band.
  static final BandMonitor instance = BandMonitor(
    source: BluetoothBandSource(BluetoothService.instance),
    loadHistory: _storedReadings,
  );

  static Future<List<StepReading>> _storedReadings() async {
    final rows = await DataStorageService().getBandData(daysBack: 2);
    return [
      for (final r in rows)
        StepReading(r['steps'] as int, r['time'] as DateTime),
    ];
  }

  final BandSource _source;
  final Future<List<StepReading>> Function()? _loadHistory;
  final Duration _freshFor;
  final Duration _checkEvery;
  final DateTime Function() _clock;

  final ValueNotifier<BandSnapshot> snapshot =
      ValueNotifier(const BandSnapshot());

  StepTally _tally = StepTally();
  StreamSubscription<HealthData>? _sub;
  Timer? _timer;
  bool _started = false;

  BandSnapshot get current => snapshot.value;

  /// The live heart rate, or 0 meaning "not measured". For baselines.
  int get heartRateOrZero => current.heartRateOrZero;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _source.isConnected.addListener(_onConnection);
    _sub = _source.dataStream.listen(_onData);
    _timer = Timer.periodic(_checkEvery, (_) => _checkFreshness());
    _onConnection();
    await _reloadHistory();
  }

  /// Call after sign-in or sign-out: stored readings belong to a user.
  Future<void> onUserChanged() async {
    _tally = StepTally();
    snapshot.value = snapshot.value.copyWith(clearSteps: true);
    await _reloadHistory();
  }

  Future<void> _reloadHistory() async {
    final loader = _loadHistory;
    if (loader == null) return;
    try {
      final readings = await loader();
      _tally = StepTally.fromHistory(
        [for (final r in readings) r],
        now: _clock(),
      );
      snapshot.value = snapshot.value.copyWith(
        everSeen: snapshot.value.everSeen || readings.isNotEmpty,
        deviceSteps: _tally.deviceCounter,
        stepsToday: _tally.today,
        clearSteps: _tally.deviceCounter == null,
        lastReadingAt: snapshot.value.lastReadingAt ??
            (readings.isEmpty ? null : readings.last.at),
      );
    } catch (e) {
      debugPrint('BandMonitor: could not load stored readings: $e');
    }
  }

  void _onConnection() {
    final connected = _source.isConnected.value;
    snapshot.value = snapshot.value.copyWith(
      connected: connected,
      everSeen: snapshot.value.everSeen || connected,
      // A new connection has not delivered anything yet; a drop ends "live".
      fresh: connected ? snapshot.value.fresh : false,
    );
  }

  void _onData(HealthData data) {
    final now = _clock();
    if (data.steps > 0) _tally.add(data.steps, now);
    snapshot.value = snapshot.value.copyWith(
      connected: _source.isConnected.value,
      everSeen: true,
      fresh: true,
      heartRate: data.heartRate > 0 ? data.heartRate : null,
      deviceSteps: _tally.deviceCounter,
      stepsToday: _tally.today,
      lastReadingAt: now,
    );
  }

  void _checkFreshness() {
    final at = snapshot.value.lastReadingAt;
    final fresh = at != null && _clock().difference(at) <= _freshFor;
    if (fresh != snapshot.value.fresh) {
      snapshot.value = snapshot.value.copyWith(fresh: fresh);
    }
  }

  @visibleForTesting
  void checkFreshnessNow() => _checkFreshness();

  Future<void> dispose() async {
    _timer?.cancel();
    _source.isConnected.removeListener(_onConnection);
    await _sub?.cancel();
    _started = false;
  }
}

/// "Last synced" wording: plain and relative.
String describeSynced(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Not synced yet';
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inSeconds < 45) return 'Last synced just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    return 'Last synced $m min ago';
  }
  if (diff.inHours < 24) return 'Last synced ${diff.inHours} h ago';
  if (diff.inDays == 1) return 'Last synced yesterday';
  return 'Last synced ${diff.inDays} days ago';
}
