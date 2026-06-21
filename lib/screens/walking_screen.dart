import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/data_storage_service.dart';
import '../services/user_service.dart';
import '../theme/bella_theme.dart';

class WalkingScreen extends StatefulWidget {
  final int initialHeartRate;
  final int initialSteps;

  const WalkingScreen(
      {super.key, required this.initialHeartRate, required this.initialSteps});

  @override
  State<WalkingScreen> createState() => _WalkingScreenState();
}

class _WalkingScreenState extends State<WalkingScreen> {
  final BluetoothService _bt = BluetoothService.instance;
  final DataStorageService _dataStorage = DataStorageService();
  final UserService _userService = UserService();

  Timer? _timer;
  StreamSubscription? _dataSubscription;

  int _seconds = 0;
  int _heartRate = 0;
  int _steps = 0;
  int _initialSteps = 0;
  bool _isActive = false;
  String _activityType = 'Walking';
  double _calories = 0;
  double _distance = 0;
  double _bmi = 22.5;
  int _targetSteps = 10000;
  String _bmiCategory = 'Normal';
  List<String> _chronicDiseases = [];

  int _lastSteps = 0;
  DateTime? _lastUpdate;
  final List<int> _recentHeartRates = [];

  // Map of disease to walking advice
  final Map<String, String> _diseaseWalkingAdvice = {
    'Hypertension':
        '❤️ Monitor your BP; walk at a moderate pace and stay hydrated.',
    'Diabetes (Type 2)':
        '🩸 Check blood sugar before/after; carry a snack for lows.',
    'Asthma': '🌬️ Keep inhaler nearby; warm up slowly, avoid cold air.',
    'Anemia': '🩸 Start with short walks, rest when fatigued, iron-rich diet.',
    'High Cholesterol': '🫀 Regular walking helps improve lipid profile.',
    'Arthritis':
        '🦴 Start with short walks, wear supportive shoes, use softer surfaces.',
    'Osteoporosis':
        '🦴 Weight-bearing walks improve bone density, avoid falls.',
    'Chronic Kidney Disease':
        '🥤 Stay hydrated but follow fluid limits; consult doctor.',
    'Depression': '😊 Walking boosts mood; try to walk outdoors for sunlight.',
    'Anxiety Disorder': '🧘 Walk in quiet areas, focus on breathing rhythm.',
    'Migraine':
        '🤕 Avoid bright sunlight, stay hydrated, walk at a steady pace.',
    'Thyroid Disorder (Hypothyroidism)':
        '🦋 Regular walking helps manage weight and energy.',
    'Gout': '🦶 Stay well hydrated, avoid overexertion to reduce flare risk.',
    'IBS': '🥑 Walk after meals to aid digestion, avoid intense sprints.',
    'GERD (Acid Reflux)':
        '🔥 Don’t walk immediately after large meals; keep upright.',
    'COPD': '🫁 Walk at your own pace, use pursed-lip breathing if needed.',
    'Psoriasis':
        '🌿 Walking reduces stress and inflammation; wear breathable clothes.',
    'Eczema': '💧 Avoid overheating; shower after walk and moisturize.',
    'Fibromyalgia': '😴 Gentle walking, start slow, increase gradually.',
    'Sleep Apnea':
        '😴 Walking improves sleep quality; avoid evening walks too late.',
  };

  @override
  void initState() {
    super.initState();
    _heartRate = widget.initialHeartRate;
    _initialSteps = widget.initialSteps;
    _steps = 0;

    _calculateBMIAndSetTarget();
    _loadChronicDiseases();

    _dataSubscription = _bt.dataStream.listen((data) {
      if (!mounted) return;
      final newSteps = data.steps - _initialSteps;
      setState(() {
        _heartRate = data.heartRate;
        _steps = newSteps > 0 ? newSteps : 0;
        _recentHeartRates.add(data.heartRate);
        if (_recentHeartRates.length > 10) _recentHeartRates.removeAt(0);
        _detectActivityType();
        _calculateMetrics();
      });
    });
  }

  void _loadChronicDiseases() {
    final user = _userService.currentUserObject;
    if (user != null) {
      _chronicDiseases = user.chronicDiseases;
    }
  }

  void _calculateBMIAndSetTarget() {
    final user = _userService.currentUserObject;
    if (user != null && user.height > 0 && user.weight > 0) {
      final heightInMeters = user.height / 100;
      _bmi = user.weight / (heightInMeters * heightInMeters);
      if (_bmi < 18.5) {
        _bmiCategory = 'Underweight';
        _targetSteps = 8000;
      } else if (_bmi >= 18.5 && _bmi <= 24.9) {
        _bmiCategory = 'Normal';
        _targetSteps = 10000;
      } else if (_bmi >= 25 && _bmi <= 29.9) {
        _bmiCategory = 'Overweight';
        _targetSteps = 7500;
      } else {
        _bmiCategory = 'Obese';
        _targetSteps = 5000;
      }
    } else {
      _bmiCategory = 'Normal';
      _targetSteps = 10000;
    }
  }

  void _detectActivityType() {
    if (_recentHeartRates.length < 5) return;
    final avgHeartRate =
        _recentHeartRates.reduce((a, b) => a + b) / _recentHeartRates.length;
    if (avgHeartRate > 120)
      _activityType = 'Running';
    else if (avgHeartRate > 100)
      _activityType = 'Brisk Walking';
    else if (avgHeartRate > 80)
      _activityType = 'Walking';
    else
      _activityType = 'Slow Walking';

    if (_lastUpdate != null && _steps > _lastSteps) {
      final timeDiff = DateTime.now().difference(_lastUpdate!).inSeconds;
      if (timeDiff > 0) {
        final stepsPerSecond = (_steps - _lastSteps) / timeDiff;
        if (stepsPerSecond > 2.5) _activityType = 'Running';
        if (stepsPerSecond > 1.8) _activityType = 'Brisk Walking';
      }
    }
    _lastSteps = _steps;
    _lastUpdate = DateTime.now();
  }

  void _calculateMetrics() {
    final user = _userService.currentUserObject;
    if (user == null) return;
    _distance = (_steps * 0.762) / 1000;
    double metValue = 2.5;
    if (_activityType == 'Running') metValue = 8.0;
    if (_activityType == 'Brisk Walking') metValue = 4.0;
    double weightFactor = user.weight;
    if (_bmi > 30) weightFactor *= 1.2;
    if (_bmi < 18.5) weightFactor *= 0.9;
    _calories = (metValue * weightFactor * _seconds) / 3600;
  }

  void _startWalking() {
    if (_isActive) {
      _stopWalking();
      return;
    }
    setState(() {
      _isActive = true;
      _seconds = 0;
      _steps = 0;
      _initialSteps = widget.initialSteps;
      _calories = 0;
      _distance = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  void _stopWalking() {
    _timer?.cancel();
    setState(() => _isActive = false);
    _dataStorage.saveWalkingSession(
      steps: _steps,
      distanceKm: _distance,
      calories: _calories,
      durationSeconds: _seconds,
      activityType: _activityType,
      timestamp: DateTime.now(),
      averageHeartRate: _heartRate,
    );
    _dataStorage.updateDailyGoal(
        goalType: 'steps',
        progress: _steps.toDouble(),
        target: _targetSteps.toDouble(),
        date: DateTime.now());
    _dataStorage.updateDailyGoal(
        goalType: 'activity',
        progress: _seconds / 60.0,
        target: 30.0,
        date: DateTime.now());
    _showSessionSummary();
  }

  void _showSessionSummary() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Icon(Icons.directions_walk,
            color: BellaColors.success, size: 46),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Session Complete',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: BellaColors.textPrimary)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _summaryStat('Steps', '$_steps'),
              _summaryStat('Calories', _calories.toStringAsFixed(1)),
              _summaryStat('Km', _distance.toStringAsFixed(2)),
            ]),
            const SizedBox(height: 20),
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _getActivityColor().withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14)),
                child: Text('Activity: $_activityType',
                    style: TextStyle(
                        color: _getActivityColor(),
                        fontWeight: FontWeight.bold))),
            const SizedBox(height: 12),
            Text(_getHealthMessage(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: BellaColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: Navigator.of(context).pop, child: const Text('Great'))
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value) => Column(children: [
        Text(value,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: BellaColors.textPrimary)),
        Text(label,
            style: const TextStyle(color: BellaColors.textMuted, fontSize: 12))
      ]);

  String _getTimeFormatted() {
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Color _getActivityColor() {
    switch (_activityType) {
      case 'Running':
        return BellaColors.danger;
      case 'Brisk Walking':
        return BellaColors.warning;
      case 'Walking':
        return BellaColors.success;
      default:
        return BellaColors.secondary;
    }
  }

  String _getHealthMessage() {
    if (_bmi > 30) return 'Great start. Every step counts.';
    if (_bmi > 25) return 'Excellent low‑impact work for weight management.';
    if (_bmi < 18.5) return 'Helps maintain healthy metabolism.';
    return 'Strong work for cardiovascular health.';
  }

  String _getTargetMessage() =>
      'Daily target: $_targetSteps steps (based on BMI ${_bmi.toStringAsFixed(1)})';

  Color _getBMIColor() {
    if (_bmi < 18.5) return BellaColors.secondary;
    if (_bmi >= 18.5 && _bmi <= 24.9) return BellaColors.success;
    if (_bmi >= 25 && _bmi <= 29.9) return BellaColors.warning;
    return BellaColors.danger;
  }

  String _getHealthTip() {
    final List<String> tips = [];
    for (final disease in _chronicDiseases) {
      if (_diseaseWalkingAdvice.containsKey(disease)) {
        tips.add(_diseaseWalkingAdvice[disease]!);
      }
    }
    if (tips.isEmpty) {
      if (_bmi > 30)
        tips.add(
            'Start with shorter walks. Consistency matters more than intensity.');
      else if (_bmi > 25)
        tips.add(
            'Regular walking supports sustainable weight management and recovery.');
      else if (_bmi < 18.5)
        tips.add(
            'Gentle walking supports appetite, circulation, and healthy energy.');
      else
        tips.add('Walking helps maintain endurance, mood, and heart health.');
    }
    return tips.join('  •  ');
  }

  String _getTargetExplanation() {
    if (_bmi < 18.5)
      return '8,000 steps helps build healthy movement without overexertion.';
    if (_bmi >= 18.5 && _bmi <= 24.9)
      return '10,000 steps is a strong maintenance target for daily wellness.';
    if (_bmi >= 25 && _bmi <= 29.9)
      return '7,500 steps offers a sustainable target for steady progress.';
    return '5,000 steps is a practical starting point for long-term improvement.';
  }

  Widget _buildStatCard(
      String title, String value, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: BellaColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BellaColors.divider)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 12),
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: BellaColors.textPrimary)),
        const SizedBox(height: 4),
        Text(title,
            style: const TextStyle(
                color: BellaColors.textSecondary, fontSize: 12)),
        Text(subtitle,
            style: const TextStyle(color: BellaColors.textMuted, fontSize: 10)),
      ]),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _targetSteps == 0 ? 0.0 : _steps / _targetSteps;
    return Scaffold(
      appBar: AppBar(title: const Text('Walking & Activity')),
      body: Container(
        decoration: const BoxDecoration(gradient: BellaColors.appGradient),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                  color: BellaColors.surface,
                  border:
                      Border(bottom: BorderSide(color: BellaColors.divider))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      _activityType == 'Running'
                          ? Icons.directions_run
                          : Icons.directions_walk,
                      color: _getActivityColor(),
                      size: 24),
                  const SizedBox(width: 10),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                          color: _getActivityColor().withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(_activityType,
                          style: TextStyle(
                              color: _getActivityColor(),
                              fontWeight: FontWeight.bold,
                              fontSize: 15))),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                            width: 210,
                            height: 210,
                            child: CircularProgressIndicator(
                                value: progress > 1 ? 1 : progress,
                                strokeWidth: 12,
                                color: _getBMIColor(),
                                backgroundColor:
                                    _getBMIColor().withOpacity(0.12))),
                        Column(
                          children: [
                            Text(_getTimeFormatted(),
                                style: const TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.bold,
                                    color: BellaColors.textPrimary)),
                            const Text('Duration',
                                style: TextStyle(color: BellaColors.textMuted)),
                            const SizedBox(height: 10),
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: _getBMIColor().withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.health_and_safety,
                                          color: _getBMIColor(), size: 14),
                                      const SizedBox(width: 4),
                                      Text('BMI: ${_bmi.toStringAsFixed(1)}',
                                          style: TextStyle(
                                              color: _getBMIColor(),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold))
                                    ])),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.02,
                      children: [
                        _buildStatCard(
                            'Steps',
                            '$_steps',
                            '$_targetSteps target',
                            Icons.directions_walk,
                            BellaColors.success),
                        _buildStatCard('Heart Rate', '$_heartRate', 'BPM',
                            Icons.favorite, BellaColors.danger),
                        _buildStatCard(
                            'Calories',
                            _calories.toStringAsFixed(1),
                            'kcal burned',
                            Icons.local_fire_department,
                            BellaColors.warning),
                        _buildStatCard('Distance', _distance.toStringAsFixed(2),
                            'kilometers', Icons.map, BellaColors.secondary),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: BellaColors.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: BellaColors.divider)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('Daily Goal Progress',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _getBMIColor())),
                            const Spacer(),
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: _getBMIColor().withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12)),
                                child: Text(_bmiCategory,
                                    style: TextStyle(
                                        color: _getBMIColor(),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)))
                          ]),
                          const SizedBox(height: 8),
                          Text(_getTargetMessage(),
                              style: const TextStyle(
                                  color: BellaColors.textSecondary,
                                  fontSize: 12)),
                          const SizedBox(height: 12),
                          ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                  value: progress > 1 ? 1 : progress,
                                  backgroundColor: BellaColors.surfaceSoft,
                                  color: _getBMIColor(),
                                  minHeight: 12)),
                          const SizedBox(height: 8),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$_steps / $_targetSteps steps',
                                    style: const TextStyle(
                                        color: BellaColors.textSecondary,
                                        fontSize: 12)),
                                Text('${(progress * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                        color: _getBMIColor(),
                                        fontWeight: FontWeight.bold))
                              ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: _getBMIColor().withOpacity(0.08),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: _getBMIColor().withOpacity(0.18))),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.auto_awesome,
                                  color: _getBMIColor(), size: 18),
                              const SizedBox(width: 8),
                              Text('Personalized Target',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _getBMIColor()))
                            ]),
                            const SizedBox(height: 8),
                            Text(_getTargetExplanation(),
                                style: const TextStyle(
                                    color: BellaColors.textSecondary,
                                    fontSize: 12))
                          ]),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                          color: _getHealthTipColor().withOpacity(0.92),
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(children: [
                        const Icon(Icons.health_and_safety,
                            color: Colors.white),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Text(_getHealthTip(),
                                style: const TextStyle(color: Colors.white)))
                      ]),
                    ),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                  color: BellaColors.surface,
                  border: Border(top: BorderSide(color: BellaColors.divider))),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _startWalking,
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isActive ? BellaColors.danger : _getBMIColor(),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18))),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_isActive ? Icons.stop : Icons.play_arrow),
                        const SizedBox(width: 10),
                        Text(_isActive ? 'STOP WALKING' : 'START WALKING',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800))
                      ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getHealthTipColor() {
    if (_chronicDiseases.isNotEmpty) return BellaColors.primary;
    if (_bmi > 30) return BellaColors.warning;
    if (_bmi > 25) return BellaColors.accent;
    return BellaColors.success;
  }
}
