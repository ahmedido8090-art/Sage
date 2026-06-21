import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/health_data.dart';
import '../services/bluetooth_service.dart';
import '../services/user_service.dart';
import '../services/wellness_quote_service.dart';
import '../services/data_storage_service.dart';
import '../theme/bella_theme.dart';
import '../widgets/device_status_card.dart';
import '../widgets/health_card.dart';
import 'breathwork_screen.dart';
import 'insights_screen.dart';
import 'profile_screen.dart';
import 'sleep_sounds_screen.dart';
import 'walking_screen.dart';
import 'wellness_screen.dart';
import 'nutrition_log_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  HealthData healthData = HealthData(
    heartRate: 0,
    steps: 0,
    isConnected: false,
    calories: 0,
    sleepHours: 0,
  );

  late Quote currentQuote;
  final BluetoothService _bt = BluetoothService.instance;
  late final VoidCallback _connListener;
  StreamSubscription<HealthData>? _dataSubscription;

  @override
  void initState() {
    super.initState();
    currentQuote = WellnessQuoteService.getRandomQuote();

    _connListener = () {
      if (!mounted) return;
      setState(() {
        healthData = HealthData(
          heartRate: healthData.heartRate,
          steps: healthData.steps,
          isConnected: _bt.isConnected.value,
          calories: healthData.calories,
          sleepHours: healthData.sleepHours,
          spo2: healthData.spo2,
          temperature: healthData.temperature,
          batteryLevel: healthData.batteryLevel,
        );
      });
    };

    _bt.isConnected.addListener(_connListener);

    _dataSubscription = _bt.dataStream.listen((data) {
      if (!mounted) return;
      setState(() {
        healthData = HealthData(
          heartRate: data.heartRate,
          steps: data.steps,
          isConnected: data.isConnected,
          calories: data.calories,
          sleepHours: healthData.sleepHours,
          spo2: data.spo2,
          temperature: data.temperature,
          batteryLevel: data.batteryLevel,
        );
      });
    });
  }

  @override
  void dispose() {
    _bt.isConnected.removeListener(_connListener);
    _dataSubscription?.cancel();
    super.dispose();
  }

  String get _userDisplayName {
    final user = UserService().currentUserObject;
    if (user != null) return user.username;
    return UserService().currentUser ?? 'User';
  }

  void _handleConnectPress() async {
    if (_bt.isConnected.value) {
      await _bt.disconnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bella Band disconnected.')),
      );
    } else {
      _showDevicePicker();
    }
  }

  void _showDevicePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: BellaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _DevicePickerSheet(btService: _bt),
    );
  }

  void _refreshQuote() {
    setState(() {
      currentQuote = WellnessQuoteService.getRandomQuote();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.nightlight_round, color: BellaColors.primary, size: 28),
            SizedBox(width: 10),
            Text(
              'Bella',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: BellaColors.textPrimary,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
      body: _buildCurrentScreen(),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return const WellnessScreen();
      case 2:
        return const InsightsScreen();
      case 3:
        return const ProfileScreen();
      default:
        return _buildDashboardTab();
    }
  }

  Widget _buildDashboardTab() {
    final safeHeart = healthData.heartRate;
    final safeSteps = healthData.steps;

    return Container(
      decoration: const BoxDecoration(gradient: BellaColors.appGradient),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back, $_userDisplayName',
              style: const TextStyle(
                color: BellaColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your wellness dashboard',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: BellaColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            DeviceStatusCard(
              isConnected: healthData.isConnected,
              batteryLevel: healthData.batteryLevel,
              heartRate: safeHeart.toDouble(),
              onConnectPressed: _handleConnectPress,
            ),
            const SizedBox(height: 18),
            FutureBuilder<Map<String, int>>(
              future: DataStorageService().getTodayNutrition(
                userId: UserService().currentUser ?? '',
              ),
              builder: (ctx, snapshot) {
                // We don't need the water value anymore – we just show the card as a launcher
                return GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.88,
                  ),
                  children: [
                    HealthCard(
                      icon: Icons.favorite,
                      title: 'Heart Rate',
                      value: '$safeHeart',
                      unit: 'bpm',
                      color: BellaColors.danger,
                      iconColor: BellaColors.danger,
                    ),
                    HealthCard(
                      icon: Icons.directions_walk,
                      title: 'Steps',
                      value: '$safeSteps',
                      unit: '',
                      color: BellaColors.success,
                      iconColor: BellaColors.success,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WalkingScreen(
                              initialHeartRate: safeHeart,
                              initialSteps: safeSteps,
                            ),
                          ),
                        );
                      },
                      showActionButton: true,
                      actionIcon: Icons.open_in_new,
                    ),
                    HealthCard(
                      icon: Icons.local_fire_department,
                      title: 'Calories',
                      value: '${healthData.calories.toInt()}',
                      unit: 'kcal',
                      color: BellaColors.warning,
                      iconColor: BellaColors.warning,
                    ),
                    // Custom card for Nutriva – bigger icon and text, no number
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NutritionLogScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: BellaColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: BellaColors.divider),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 16,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: BellaColors.secondary.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.restaurant,
                                color: BellaColors.secondary,
                                size: 34,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Nutriva',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: BellaColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Track nutrition',
                              style: TextStyle(
                                fontSize: 13,
                                color: BellaColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return NavigationBar(
      selectedIndex: _currentIndex,
      onDestinationSelected: (index) {
        setState(() => _currentIndex = index);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.spa_outlined),
          selectedIcon: Icon(Icons.spa),
          label: 'Wellness',
        ),
        NavigationDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights),
          label: 'Insights',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}

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
    return SizedBox(
      height: 420,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Select your band',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: BellaColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            if (Platform.isAndroid)
              const Text(
                "If you don't see your device, pair it in Android Bluetooth Settings first.",
                style: TextStyle(
                  color: BellaColors.textSecondary,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 10),
            const Divider(color: BellaColors.divider),
            Expanded(
              child: StreamBuilder<List<SageDevice>>(
                stream: widget.btService.scanResults,
                initialData: const [],
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: BellaColors.danger),
                      ),
                    );
                  }

                  final devices = snapshot.data ?? [];
                  if (devices.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Scanning for devices...',
                            style: TextStyle(color: BellaColors.textSecondary),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (_, i) {
                      final dev = devices[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: BellaColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: BellaColors.divider),
                        ),
                        child: ListTile(
                          leading: Icon(
                            dev.isBle
                                ? Icons.bluetooth
                                : Icons.bluetooth_searching,
                            color: BellaColors.secondary,
                          ),
                          title: Text(
                            dev.name.isEmpty ? 'Unknown Device' : dev.name,
                            style: const TextStyle(
                              color: BellaColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            dev.id,
                            style: const TextStyle(
                              color: BellaColors.textMuted,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: BellaColors.textSecondary,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _connectTo(dev);
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _connectTo(SageDevice device) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Connecting to ${device.name}...')),
    );

    try {
      await widget.btService.connect(device);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: $e'),
          backgroundColor: BellaColors.danger,
        ),
      );
    }
  }
}
