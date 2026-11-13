import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sage/band/band_monitor.dart';
import 'package:sage/band/step_tally.dart';
import 'package:sage/models/health_data.dart';

class FakeSource implements BandSource {
  @override
  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  final StreamController<HealthData> controller = StreamController.broadcast();
  @override
  Stream<HealthData> get dataStream => controller.stream;

  void emit({int hr = 0, int steps = 0}) => controller.add(HealthData(
      heartRate: hr,
      steps: steps,
      isConnected: isConnected.value,
      calories: 0,
      sleepHours: 0));
}

void main() {
  late FakeSource source;
  late DateTime now;
  late BandMonitor monitor;

  setUp(() async {
    source = FakeSource();
    now = DateTime(2026, 3, 10, 9);
    monitor = BandMonitor(
      source: source,
      clock: () => now,
      freshFor: const Duration(seconds: 30),
      checkEvery: const Duration(hours: 1), // checked manually below
      loadHistory: () async => [StepReading(1000, DateTime(2026, 3, 10, 8))],
    );
    await monitor.start();
  });

  tearDown(() => monitor.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('nothing is invented before the band says anything', () {
    final s =
        BandMonitor(source: FakeSource(), loadHistory: () async => const [])
            .current;
    expect(s.connected, isFalse);
    expect(s.heartRate, isNull);
    expect(s.stepsToday, isNull);
    expect(s.liveHeartRate, isNull);
    expect(s.heartRateOrZero, 0);
    expect(s.lastReadingAt, isNull);
  });

  test('stored readings restore steps today after a restart', () {
    expect(monitor.current.stepsToday, 0);
    expect(monitor.current.deviceSteps, 1000);
    expect(monitor.current.everSeen, isTrue);
  });

  test('live readings flow through to the snapshot', () async {
    source.isConnected.value = true;
    source.emit(hr: 72, steps: 1250);
    await settle();
    final s = monitor.current;
    expect(s.isLive, isTrue);
    expect(s.liveHeartRate, 72);
    expect(s.stepsToday, 250);
    expect(s.caloriesEstimate, 10);
    expect(s.lastReadingAt, now);
  });

  test('a heart rate of 0 means "no reading", never a value', () async {
    source.isConnected.value = true;
    source.emit(hr: 70, steps: 1100);
    await settle();
    source.emit(hr: 0, steps: 1110);
    await settle();
    expect(monitor.current.heartRate, 70); // last real one is kept
    expect(monitor.current.stepsToday, 110);
  });

  test('readings go stale when the band falls silent', () async {
    source.isConnected.value = true;
    source.emit(hr: 70, steps: 1100);
    await settle();
    expect(monitor.current.liveHeartRate, 70);

    now = now.add(const Duration(seconds: 45));
    monitor.checkFreshnessNow();
    expect(monitor.current.isLive, isFalse);
    expect(monitor.current.liveHeartRate, isNull); // never shown as current
    expect(monitor.current.heartRate, 70); // still known as the last value
    expect(monitor.current.connected, isTrue);
  });

  test('disconnect ends live; values and time are kept as last known',
      () async {
    source.isConnected.value = true;
    source.emit(hr: 66, steps: 1500);
    await settle();
    final at = monitor.current.lastReadingAt;

    source.isConnected.value = false;
    final s = monitor.current;
    expect(s.connected, isFalse);
    expect(s.isLive, isFalse);
    expect(s.liveHeartRate, isNull);
    expect(s.heartRateOrZero, 0);
    expect(s.stepsToday, 500);
    expect(s.lastReadingAt, at);
  });

  test('reconnecting is not live until a reading arrives', () async {
    source.isConnected.value = true;
    source.emit(hr: 66, steps: 1500);
    await settle();
    source.isConnected.value = false;

    source.isConnected.value = true;
    expect(monitor.current.connected, isTrue);
    expect(monitor.current.isLive, isFalse);

    source.emit(hr: 74, steps: 1520);
    await settle();
    expect(monitor.current.isLive, isTrue);
    expect(monitor.current.liveHeartRate, 74);
    expect(monitor.current.stepsToday, 520);
  });

  test('a band reset in the middle of the day keeps the count honest',
      () async {
    source.isConnected.value = true;
    source.emit(hr: 70, steps: 2000);
    await settle();
    source.emit(hr: 70, steps: 80); // counter reset
    await settle();
    source.emit(hr: 70, steps: 180);
    await settle();
    expect(monitor.current.stepsToday, 1000 + 80 + 100);
  });

  test('switching users forgets the previous user\'s steps', () async {
    source.isConnected.value = true;
    source.emit(hr: 70, steps: 1300);
    await settle();
    expect(monitor.current.stepsToday, 300);

    final fresh = BandMonitor(
        source: source, clock: () => now, loadHistory: () async => const []);
    await fresh.start();
    await fresh.onUserChanged();
    expect(fresh.current.stepsToday, isNull);
    await fresh.dispose();
  });

  group('describeSynced', () {
    final base = DateTime(2026, 3, 10, 12);
    test('reads naturally', () {
      expect(describeSynced(null, now: base), 'Not synced yet');
      expect(
          describeSynced(base.subtract(const Duration(seconds: 10)), now: base),
          'Last synced just now');
      expect(
          describeSynced(base.subtract(const Duration(minutes: 5)), now: base),
          'Last synced 5 min ago');
      expect(describeSynced(base.subtract(const Duration(hours: 3)), now: base),
          'Last synced 3 h ago');
      expect(
          describeSynced(base.subtract(const Duration(hours: 30)), now: base),
          'Last synced yesterday');
      expect(describeSynced(base.subtract(const Duration(days: 4)), now: base),
          'Last synced 4 days ago');
    });
  });
}
