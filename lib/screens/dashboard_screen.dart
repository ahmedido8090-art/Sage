// screens/dashboard_screen.dart
//
// FIX: Tab switch animation changed from sequential (await reverse → swap →
// forward) to a simultaneous crossfade driven by AnimatedSwitcher.
//
// The old flow:
//   1. await _tabFadeCtrl.reverse()   ← 220ms during which bottom nav is
//                                        unresponsive to further taps
//   2. setState(swap tab)
//   3. _tabFadeCtrl.forward()
//
// This felt sluggish and occasionally swallowed double-taps. The new
// approach wraps the tab body in an AnimatedSwitcher keyed on _currentIndex,
// so Flutter handles the crossfade automatically with no await and no
// blocking. The AnimationController is removed entirely.
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/health_data.dart';
import '../services/wellness_quote_service.dart';
import '../services/wellness_score_service.dart';
import '../services/user_service.dart';
import '../services/bluetooth_service.dart';
import '../services/bella_service.dart';
import '../theme/app_theme.dart';
import '../utils/page_transitions.dart';
import '../widgets/sage_hero_card.dart';
import '../widgets/metric_tile.dart';
import '../widgets/wellness_activity_tile.dart';
import '../widgets/quote_section.dart';
import '../widgets/sage_bottom_nav.dart';
import '../widgets/shimmer_loader.dart';
import 'profile_screen.dart';
import 'wellness_screen.dart';
import 'insights_screen.dart';
import 'pure_plate_screen.dart';
import 'zzzify_screen.dart';
import 'chronic_care_screen.dart';
import 'daily_checkin_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  final ValueNotifier<int> _wellnessReloadSignal = ValueNotifier(0);
  final ValueNotifier<int> _insightsReloadSignal = ValueNotifier(0);

  HealthData healthData = HealthData(
    heartRate: 0,
    steps: 0,
    isConnected: false,
    calories: 0,
    sleepHours: 0,
  );

  bool _initialLoading = true;

  late Quote currentQuote;
  final BluetoothService _bt = BluetoothService.instance;
  final BellaService _bella = BellaService();
  late final VoidCallback _connListener;

  @override
  void initState() {
    super.initState();

    currentQuote = WellnessQuoteService.getQuoteForState(
      lastCheckin: _bella.lastCheckin,
      lastSleep: _bella.lastNightSleep,
      avgSleepQuality: _bella.averageSleepQuality(),
      totalActivityMinutesToday: _bella.sessionMinutesToday('meditation') +
          _bella.sessionMinutesToday('walking') +
          _bella.sessionsToday('breathwork') * 5 +
          _bella.sessionMinutesToday('sleep_sounds'),
    );

    _connListener = () {
      if (!mounted) return;
      setState(() {
        healthData = HealthData(
          heartRate: healthData.heartRate,
          steps: healthData.steps,
          isConnected: _bt.isConnected.value,
          calories: healthData.calories,
          sleepHours: healthData.sleepHours,
        );
      });
    };
    _bt.isConnected.addListener(_connListener);

    _bt.dataStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        healthData = HealthData(
          heartRate: data.heartRate,
          steps: data.steps,
          isConnected: data.isConnected,
          calories: data.calories,
          sleepHours: healthData.sleepHours,
        );
      });
    });

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _initialLoading = false);
    });
  }

  @override
  void dispose() {
    _bt.isConnected.removeListener(_connListener);
    super.dispose();
  }

  String get _userDisplayName {
    final user = UserService().currentUserObject;
    return user?.username ?? UserService().currentUser ?? 'User';
  }

  double get _bmi {
    final user = UserService().currentUserObject;
    if (user != null && user.height > 0 && user.weight > 0) {
      final h = user.height / 100;
      return user.weight / (h * h);
    }
    return 22.5;
  }

  String get _bmiCategory {
    final bmi = _bmi;
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    return 'Obese';
  }

  void _refreshFromBella() {
    if (!mounted) return;
    setState(() {
      currentQuote = WellnessQuoteService.getQuoteForState(
        lastCheckin: _bella.lastCheckin,
        lastSleep: _bella.lastNightSleep,
        avgSleepQuality: _bella.averageSleepQuality(),
        totalActivityMinutesToday: _bella.sessionMinutesToday('meditation') +
            _bella.sessionMinutesToday('walking') +
            _bella.sessionsToday('breathwork') * 5 +
            _bella.sessionMinutesToday('sleep_sounds'),
      );
    });
  }

  String _timeOfDayGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  String _heartRateStatusLabel(int hr) {
    if (hr == 0) return 'No reading yet';
    if (hr > 100) return 'Elevated';
    if (hr < 60) return 'Resting · low';
    return 'Resting · steady';
  }

  void _handleConnectPress() async {
    if (_bt.isConnected.value) {
      await _bt.disconnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sage Band Disconnected'),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      _showDevicePicker();
    }
  }

  void _showDevicePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DevicePickerSheet(btService: _bt),
    );
  }

  List<String> _flaggedConditionsToday() {
    final conditions =
        UserService().currentUserObject?.chronicDiseases ?? [];
    final flagged = <String>[];
    for (final cond in conditions) {
      final readings = _bella.getReadings(condition: cond);
      if (readings.isEmpty) continue;
      if (WellnessScoreService.isReadingFlagged(cond, readings.first)) {
        flagged.add(cond);
      }
    }
    return flagged;
  }

  String _chronicCareSubtitle() {
    final conditions =
        UserService().currentUserObject?.chronicDiseases ?? [];
    if (conditions.isEmpty) return 'Log & manage';

    int stalestDays = 0;
    String? stalestCondition;
    for (final cond in conditions) {
      final readings = _bella.getReadings(condition: cond);
      if (readings.isEmpty) {
        stalestDays = 999;
        stalestCondition = cond;
      } else {
        final d = DateTime.now().difference(readings.first.time).inDays;
        if (d > stalestDays) {
          stalestDays = d;
          stalestCondition = cond;
        }
      }
    }

    final flagged = _flaggedConditionsToday();
    if (flagged.isNotEmpty) {
      if (flagged.length == 1) return '⚠ ${flagged.first} reading flagged';
      final label = flagged.length == 2
          ? '${flagged[0]} & ${flagged[1]}'
          : '${flagged.sublist(0, flagged.length - 1).join(', ')} & ${flagged.last}';
      return '⚠ $label flagged';
    }

    if (stalestDays == 999 && stalestCondition != null) {
      return 'No reading logged for $stalestCondition yet';
    }
    if (stalestDays >= 7 && stalestCondition != null) {
      return '$stalestCondition: ${stalestDays}d since last reading';
    }
    if (stalestDays >= 3 && stalestCondition != null) {
      return '$stalestCondition: log a reading soon';
    }

    final anyReading = conditions
        .any((cond) => _bella.getReadings(condition: cond).isNotEmpty);
    return anyReading ? 'Last reading in range' : 'Log & manage';
  }

  String _purePlateSubtitle() {
    final water = _bella.todayWaterMl();
    final foodCount = _bella.getFoodEntries(onDate: DateTime.now()).length;
    if (water == 0 && foodCount == 0) return 'Plan & hydrate';
    if (water > 0) return '${(water / 1000).toStringAsFixed(1)}L logged today';
    return '$foodCount meal${foodCount == 1 ? '' : 's'} logged';
  }

  String _zzzifySubtitle() {
    final last = _bella.lastNightSleep;
    if (last == null) return 'Track & wind down';
    final q = last.quality;
    if (q >= 4) return 'Last night: great sleep';
    if (q == 3) return 'Last night: decent sleep';
    return 'Last night: poor sleep';
  }

  String _checkinSubtitle() {
    if (_bella.hasCheckedInToday()) {
      final c = _bella.lastCheckin;
      if (c == null) return 'Checked in today';
      final score = c.wellbeingScore;
      if (score >= 7) return 'Feeling good today';
      if (score >= 4.5) return 'Feeling okay today';
      return 'Low wellbeing today';
    }
    return 'How are you?';
  }

  void _push(Widget screen) {
    Navigator.push(context, slideUpRoute(screen))
        .then((_) => _refreshFromBella());
  }

  void _switchTab(int i) {
    if (i == _currentIndex) return;
    setState(() => _currentIndex = i);
    if (i == 0) _refreshFromBella();
    if (i == 1) _wellnessReloadSignal.value++;
    if (i == 2) _insightsReloadSignal.value++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SageColors.linen,
      body: AnimatedSwitcher(
        // Crossfade between tabs with no blocking await.
        // The key on each child forces AnimatedSwitcher to treat index
        // changes as a new widget, triggering the fade.
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: _buildCurrentScreen(),
        ),
      ),
      bottomNavigationBar: SageBottomNav(
        currentIndex: _currentIndex,
        onTap: _switchTab,
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return WellnessScreen(reloadSignal: _wellnessReloadSignal);
      case 2:
        return InsightsScreen(reloadSignal: _insightsReloadSignal);
      case 3:
        return const ProfileScreen();
      default:
        return _buildDashboardTab();
    }
  }

  Widget _buildDashboardTab() {
    final int safeHeart = healthData.heartRate is double
        ? (healthData.heartRate as double).toInt()
        : healthData.heartRate;
    final int safeSteps = healthData.steps is double
        ? (healthData.steps as double).toInt()
        : healthData.steps;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('sage', style: SageText.wordmark()),
                GestureDetector(
                  onTap: () => _switchTab(3),
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: SageColors.moss,
                    child: Text(
                      _userDisplayName.isNotEmpty
                          ? _userDisplayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: SageColors.linen,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Good ${_timeOfDayGreeting()}, $_userDisplayName',
              style: TextStyle(color: SageColors.inkSoft, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text('Health Sync Hub', style: SageText.headline()),
            const SizedBox(height: 20),

            // ── Hero card or shimmer
            if (_initialLoading)
              const ShimmerHeroCard()
            else
              SageHeroCard(
                isConnected: healthData.isConnected,
                batteryLevel: healthData.batteryLevel,
                heartRate: safeHeart,
                subLabel: _heartRateStatusLabel(safeHeart),
                onConnectPressed: _handleConnectPress,
              ),

            const SizedBox(height: 20),

            // ── Metric tiles or shimmers
            if (_initialLoading)
              Row(
                children: const [
                  Expanded(child: ShimmerMetricTile()),
                  SizedBox(width: 10),
                  Expanded(child: ShimmerMetricTile()),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      icon: const Icon(Icons.directions_walk),
                      value: '$safeSteps',
                      label: 'Steps today',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricTile(
                      icon: const Icon(Icons.local_fire_department),
                      value: healthData.calories.toStringAsFixed(0),
                      label: 'Calories',
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 24),

            Text(
              'BELLA',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: SageColors.inkSoft,
              ),
            ),
            const SizedBox(height: 12),

            // ── Bella activity tiles
            if (_initialLoading)
              SizedBox(
                height: 126,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: const [
                    ShimmerActivityTile(),
                    SizedBox(width: 12),
                    ShimmerActivityTile(),
                    SizedBox(width: 12),
                    ShimmerActivityTile(),
                  ],
                ),
              )
            else
              SizedBox(
                height: 126,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    WellnessActivityTile(
                      icon: Icons.water_drop_outlined,
                      title: 'PurePlate',
                      subtitle: _purePlateSubtitle(),
                      accent: SageColors.clay,
                      onTap: () => _push(const PurePlateScreen()),
                    ),
                    const SizedBox(width: 12),
                    WellnessActivityTile(
                      icon: Icons.nights_stay_outlined,
                      title: 'ZZZify',
                      subtitle: _zzzifySubtitle(),
                      accent: SageColors.moss,
                      onTap: () => _push(const ZZZifyScreen()),
                    ),
                    if ((UserService().currentUserObject?.chronicDiseases ?? [])
                        .isNotEmpty) ...[
                      const SizedBox(width: 12),
                      WellnessActivityTile(
                        icon: Icons.favorite_border,
                        title: 'Chronic Care',
                        subtitle: _chronicCareSubtitle(),
                        accent: SageColors.sage,
                        onTap: () => _push(const ChronicCareScreen()),
                      ),
                    ],
                    const SizedBox(width: 12),
                    WellnessActivityTile(
                      icon: Icons.mood_outlined,
                      title: 'Daily Check-in',
                      subtitle: _checkinSubtitle(),
                      accent: SageColors.amber,
                      onTap: () => _push(const DailyCheckinScreen()),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),
            QuoteSection(
              text: currentQuote.text,
              author: currentQuote.author,
              onRefresh: () => setState(() {
                currentQuote = WellnessQuoteService.getQuoteForState(
                  lastCheckin: _bella.lastCheckin,
                  lastSleep: _bella.lastNightSleep,
                  avgSleepQuality: _bella.averageSleepQuality(),
                  totalActivityMinutesToday:
                      _bella.sessionMinutesToday('meditation') +
                          _bella.sessionMinutesToday('walking') +
                          _bella.sessionsToday('breathwork') * 5 +
                          _bella.sessionMinutesToday('sleep_sounds'),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Device picker bottom sheet ─────────────────────────────────────────────
class _DevicePickerSheet extends StatefulWidget {
  final BluetoothService btService;
  const _DevicePickerSheet({required this.btService});

  @override
  State<_DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends State<_DevicePickerSheet> {
  @override
  void initState() {
    super.initState();
    widget.btService.startScan();
  }

  @override
  void dispose() {
    widget.btService.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      height: 400,
      color: SageColors.linen,
      child: Column(
        children: [
          Text('Select Your Band', style: SageText.headline()),
          const SizedBox(height: 10),
          if (Platform.isAndroid)
            Text(
              "If you don't see your device, pair it in Android Bluetooth Settings first.",
              style: TextStyle(color: SageColors.inkSoft, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<SageDevice>>(
              stream: widget.btService.scanResults,
              initialData: const [],
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final devices = snapshot.data ?? [];
                if (devices.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: SageColors.moss),
                        const SizedBox(height: 16),
                        const Text('Scanning for devices...'),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (ctx, i) {
                    final dev = devices[i];
                    return ListTile(
                      leading: Icon(
                        dev.isBle
                            ? Icons.bluetooth
                            : Icons.bluetooth_searching,
                        color: SageColors.moss,
                      ),
                      title:
                          Text(dev.name.isEmpty ? 'Unknown Device' : dev.name),
                      subtitle: Text(dev.id),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context);
                        _connectTo(dev);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _connectTo(SageDevice device) async {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connecting to ${device.name}...')));
    try {
      await widget.btService.connect(device);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Connected successfully!'),
        backgroundColor: SageColors.moss,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Connection failed: $e'),
        backgroundColor: SageColors.clay,
      ));
    }
  }
}
