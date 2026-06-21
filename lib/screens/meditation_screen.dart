import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/data_storage_service.dart';
import '../theme/bella_theme.dart';

class MeditationScreen extends StatefulWidget {
  final int initialHeartRate;
  final double bmi;
  final String bmiCategory;

  const MeditationScreen({
    super.key,
    required this.initialHeartRate,
    required this.bmi,
    required this.bmiCategory,
  });

  @override
  State<MeditationScreen> createState() => _MeditationScreenState();
}

class _MeditationScreenState extends State<MeditationScreen> {
  final BluetoothService _bt = BluetoothService.instance;
  final DataStorageService _dataStorage = DataStorageService();

  Timer? _timer;
  StreamSubscription? _hrSubscription;

  int _seconds = 0;
  int _currentHeartRate = 0;
  bool _isActive = false;
  int _selectedPoseIndex = 0;
  List<int> _heartRateHistory = [];

  final List<Map<String, dynamic>> _meditationPoses = [
    {
      'name': 'Lotus Pose (Padmasana)',
      'duration': 300,
      'icon': Icons.self_improvement,
      'color': BellaColors.primary,
      'benefits': [
        'Improves focus and concentration',
        'Reduces stress and anxiety levels',
        'Enhances posture and spinal alignment',
        'Stimulates digestion and pelvic organs',
        'Calms the mind and nervous system'
      ],
      'stepByStep': [
        'Sit on the floor with legs extended',
        'Bend right knee, place right foot on left thigh',
        'Bend left knee, place left foot on right thigh',
        'Keep spine straight and shoulders relaxed',
        'Place hands on knees in Gyan Mudra',
        'Close eyes and focus on your breath'
      ],
      'precautions': [
        'Avoid if you have knee or ankle injuries',
        'Use cushion under hips if needed',
        'Do not force the position'
      ],
      'suitableForBMI': ['Underweight', 'Normal', 'Overweight'],
      'breathingPattern':
          'Deep abdominal breathing: inhale 4s, hold 7s, exhale 8s',
      'difficulty': 'Intermediate',
      'energyLevel': 'Calming',
    },
    {
      'name': 'Easy Pose (Sukhasana)',
      'duration': 300,
      'icon': Icons.accessible,
      'color': BellaColors.secondary,
      'benefits': [
        'Grounding and calming effect',
        'Improves hip flexibility gradually',
        'Reduces mental fatigue',
        'Promotes emotional stability',
        'Good for daily meditation practice'
      ],
      'stepByStep': [
        'Sit on floor or cushion with legs crossed',
        'Allow knees to drop toward floor naturally',
        'Rest hands on knees with palms facing up',
        'Align head, neck, and spine vertically',
        'Relax facial muscles and jaw',
        'Focus on natural breath rhythm'
      ],
      'precautions': [
        'Use cushion if hips are tight',
        'Alternate cross of legs periodically',
        'Keep back supported if needed'
      ],
      'suitableForBMI': ['Underweight', 'Normal', 'Overweight', 'Obese'],
      'breathingPattern': 'Equal breathing: inhale 5s, exhale 5s',
      'difficulty': 'Beginner',
      'energyLevel': 'Balancing',
    },
    {
      'name': 'Chair Meditation',
      'duration': 300,
      'icon': Icons.chair,
      'color': BellaColors.success,
      'benefits': [
        'Perfect for beginners and office workers',
        'Easier on joints and back',
        'Can be done anywhere with a chair',
        'Improves focus in busy environments',
        'Reduces work-related stress'
      ],
      'stepByStep': [
        'Sit on chair with feet flat on floor',
        'Keep knees at 90-degree angle',
        'Place hands on thighs with palms up or down',
        'Keep back straight, not leaning on backrest',
        'Shoulders relaxed, chin parallel to floor',
        'Close eyes or soften gaze downward'
      ],
      'precautions': [
        'Ensure feet reach floor comfortably',
        'Use chair without wheels for stability',
        'Place cushion on seat if needed'
      ],
      'suitableForBMI': ['Underweight', 'Normal', 'Overweight', 'Obese'],
      'breathingPattern': 'Box breathing: 4-4-4-4',
      'difficulty': 'Beginner',
      'energyLevel': 'Grounding',
      'highBMIFriendly': true,
      'recommendedFor': 'High BMI users, elderly, beginners',
    },
    {
      'name': 'Corpse Pose (Savasana)',
      'duration': 300,
      'icon': Icons.nightlight_round,
      'color': BellaColors.accent,
      'benefits': [
        'Deep relaxation and stress relief',
        'Reduces blood pressure and heart rate',
        'Alleviates back pain and tension',
        'Improves sleep quality',
        'Calms the entire nervous system'
      ],
      'stepByStep': [
        'Lie flat on back on comfortable surface',
        'Extend legs comfortably apart',
        'Place arms at sides, palms facing up',
        'Allow feet to fall outward naturally',
        'Close eyes and release all muscle tension',
        'Focus on natural breath without control'
      ],
      'precautions': [
        'Use pillow under knees if back hurts',
        'Cover with blanket if feeling cold',
        'Avoid falling asleep during meditation'
      ],
      'suitableForBMI': ['Underweight', 'Normal', 'Overweight', 'Obese'],
      'breathingPattern': 'Natural breathing - observe without changing',
      'difficulty': 'Beginner',
      'energyLevel': 'Deeply Relaxing',
      'jointFriendly': true,
      'recommendedFor': 'Stress relief, insomnia, chronic pain',
    },
    {
      'name': 'Mountain Pose (Tadasana)',
      'duration': 300,
      'icon': Icons.terrain,
      'color': BellaColors.warning,
      'benefits': [
        'Improves posture and balance',
        'Strengthens legs and core',
        'Increases body awareness',
        'Creates a grounding effect'
      ],
      'stepByStep': [
        'Stand with feet hip-width apart',
        'Distribute weight evenly on both feet',
        'Engage thighs gently',
        'Lengthen the spine upward',
        'Relax shoulders away from ears',
        'Keep your gaze soft and steady'
      ],
      'precautions': [
        'Avoid locking knees',
        'Keep slight bend in knees if needed',
        'Focus on steady balance'
      ],
      'suitableForBMI': ['Underweight', 'Normal', 'Overweight'],
      'breathingPattern': 'Slow ujjayi-style breathing',
      'difficulty': 'Beginner',
      'energyLevel': 'Grounding',
    },
  ];

  String get _bmiCategory {
    if (widget.bmi < 18.5) return 'Underweight';
    if (widget.bmi < 25) return 'Normal';
    if (widget.bmi < 30) return 'Overweight';
    return 'Obese';
  }

  @override
  void initState() {
    super.initState();
    _currentHeartRate = widget.initialHeartRate;
    _heartRateHistory = [widget.initialHeartRate];

    _hrSubscription = _bt.dataStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _currentHeartRate = data.heartRate;
        if (_isActive && _seconds % 30 == 0) {
          _heartRateHistory.add(data.heartRate);
        }
      });
    });

    _selectPoseForBMI();
  }

  bool _isPoseSuitableForUser(int index) {
    final pose = _meditationPoses[index];
    final suitableCategories = pose['suitableForBMI'] as List;
    return suitableCategories.contains(_bmiCategory);
  }

  String _getPoseSuitabilityMessage(int index) {
    if (_isPoseSuitableForUser(index)) {
      return 'Well suited to your BMI category ($_bmiCategory)';
    }
    return 'Possible, but another pose may be more comfortable for $_bmiCategory';
  }

  Color _getSuitabilityColor(int index) {
    return _isPoseSuitableForUser(index)
        ? BellaColors.success
        : BellaColors.warning;
  }

  void _selectPoseForBMI() {
    final suitablePoses = <int>[];

    for (int i = 0; i < _meditationPoses.length; i++) {
      if (_isPoseSuitableForUser(i)) {
        suitablePoses.add(i);
      }
    }

    if (suitablePoses.isNotEmpty) {
      if (widget.bmi >= 30) {
        for (final i in suitablePoses) {
          if (_meditationPoses[i]['highBMIFriendly'] == true) {
            setState(() {
              _selectedPoseIndex = i;
            });
            return;
          }
        }
      }

      setState(() {
        _selectedPoseIndex = suitablePoses.first;
      });
    }
  }

  void _startMeditation() {
    if (_isActive) {
      _stopMeditation();
      return;
    }

    setState(() {
      _isActive = true;
      _seconds = 0;
      _heartRateHistory = [_currentHeartRate];
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() {
        _seconds++;
        final poseDuration =
            _meditationPoses[_selectedPoseIndex]['duration'] as int;
        if (_seconds >= poseDuration) {
          _completeMeditation();
          timer.cancel();
        }
      });
    });
  }

  void _stopMeditation() {
    _timer?.cancel();
    setState(() {
      _isActive = false;
    });
  }

  void _completeMeditation() {
    _timer?.cancel();
    setState(() {
      _isActive = false;
    });

    final initialHR = widget.initialHeartRate;
    final finalHR = _currentHeartRate;
    final change = initialHR - finalHR;

    _dataStorage.saveMeditationSession(
      poseName: _meditationPoses[_selectedPoseIndex]['name'],
      durationSeconds: _seconds,
      startHeartRate: initialHR,
      endHeartRate: finalHR,
      timestamp: DateTime.now(),
      benefits:
          (_meditationPoses[_selectedPoseIndex]['benefits'] as List).join(', '),
      calmScore: _calculateCalmScore(initialHR, finalHR),
    );

    _dataStorage.updateDailyGoal(
      goalType: 'meditation',
      progress: _seconds / 60.0,
      target: 10,
      date: DateTime.now(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Icon(
          Icons.check_circle,
          color: BellaColors.success,
          size: 46,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Meditation Complete',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: BellaColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildMeditationResult(initialHR, finalHR, change),
            const SizedBox(height: 12),
            Text(
              change > 5
                  ? 'Excellent. Your heart rate decreased meaningfully.'
                  : change > 0
                      ? 'Good session. Your heart rate settled slightly.'
                      : 'Try another pose or a longer session next time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: change > 0 ? BellaColors.success : BellaColors.warning,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  double _calculateCalmScore(int startHR, int endHR) {
    final change = startHR - endHR;
    if (change > 15) return 1.0;
    if (change > 8) return 0.7;
    if (change > 0) return 0.4;
    return 0.1;
  }

  String _getTimeRemaining() {
    final poseDuration =
        _meditationPoses[_selectedPoseIndex]['duration'] as int;
    final remaining = poseDuration - _seconds;
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Color _getBMIColor(double bmi) {
    if (bmi < 18.5) return BellaColors.secondary;
    if (bmi < 25) return BellaColors.success;
    if (bmi < 30) return BellaColors.warning;
    return BellaColors.danger;
  }

  Color _getHeartRateColor(int hr) {
    if (hr < 60) return BellaColors.secondary;
    if (hr < 100) return BellaColors.success;
    if (hr < 120) return BellaColors.warning;
    return BellaColors.danger;
  }

  List<Widget> _getBMIGuidelines() {
    return [
      if (widget.bmi < 18.5)
        const Text('• Prioritize gentle, energizing poses'),
      if (widget.bmi >= 25 && widget.bmi < 30)
        const Text('• Chair-based meditation may feel more comfortable'),
      if (widget.bmi >= 30)
        const Text('• Best options: Chair Meditation and Corpse Pose'),
      const Text('• Avoid strain on knees, hips, and lower back'),
      const Text('• Comfort matters more than forcing posture'),
      const Text('• Shorter sessions can build consistency'),
    ];
  }

  Widget _buildMeditationResult(int initial, int finalHR, int change) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BellaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _resultColumn('Start', '$initial', BellaColors.textPrimary),
          const Icon(Icons.arrow_forward, color: BellaColors.textMuted),
          _resultColumn('End', '$finalHR', BellaColors.textPrimary),
          const Icon(Icons.arrow_forward, color: BellaColors.textMuted),
          _resultColumn(
            'Change',
            '${change > 0 ? '-' : '+'}${change.abs()}',
            change > 0 ? BellaColors.success : BellaColors.danger,
          ),
        ],
      ),
    );
  }

  Widget _resultColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: BellaColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const Text(
          'BPM',
          style: TextStyle(
            fontSize: 10,
            color: BellaColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 18, color: BellaColors.textSecondary),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: BellaColors.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: BellaColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildPoseDetails() {
    final currentPose = _meditationPoses[_selectedPoseIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _getSuitabilityColor(_selectedPoseIndex).withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _getSuitabilityColor(_selectedPoseIndex).withOpacity(0.24),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isPoseSuitableForUser(_selectedPoseIndex)
                    ? Icons.check_circle
                    : Icons.warning_amber,
                color: _getSuitabilityColor(_selectedPoseIndex),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getPoseSuitabilityMessage(_selectedPoseIndex),
                  style: TextStyle(
                    color: _getSuitabilityColor(_selectedPoseIndex),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Key Benefits',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: BellaColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ...(currentPose['benefits'] as List).map(
          (benefit) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check, size: 16, color: BellaColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    benefit,
                    style: const TextStyle(
                      fontSize: 13,
                      color: BellaColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Step-by-Step Guide',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: BellaColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ...(currentPose['stepByStep'] as List).asMap().entries.map((entry) {
          final index = entry.key + 1;
          final step = entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: currentPose['color'] as Color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step,
                    style: const TextStyle(
                      fontSize: 13,
                      color: BellaColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BellaColors.secondary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.air, color: BellaColors.secondary, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Recommended Breathing Pattern',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: BellaColors.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                currentPose['breathingPattern'] as String,
                style: const TextStyle(
                  fontSize: 13,
                  color: BellaColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Precautions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: BellaColors.danger,
          ),
        ),
        const SizedBox(height: 8),
        ...(currentPose['precautions'] as List).map(
          (precaution) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber,
                  size: 16,
                  color: BellaColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    precaution,
                    style: const TextStyle(
                      fontSize: 13,
                      color: BellaColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BellaColors.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoItem(
                'Difficulty',
                currentPose['difficulty'] as String,
                Icons.speed,
              ),
              _buildInfoItem(
                'Energy',
                currentPose['energyLevel'] as String,
                Icons.bolt,
              ),
              _buildInfoItem(
                'Duration',
                '${(currentPose['duration'] as int) ~/ 60} min',
                Icons.timer,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hrSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPose = _meditationPoses[_selectedPoseIndex];
    final poseDuration = currentPose['duration'] as int;
    final progress = poseDuration == 0 ? 0.0 : _seconds / poseDuration;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guided Meditation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('BMI Guidance'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your BMI: ${widget.bmi.toStringAsFixed(1)} ($_bmiCategory)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ..._getBMIGuidelines(),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: Navigator.of(context).pop,
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: BellaColors.appGradient),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: BellaColors.surface,
                border: Border(bottom: BorderSide(color: BellaColors.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Select Meditation Pose',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: BellaColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'BMI: ${widget.bmi.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _getBMIColor(widget.bmi),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: screenHeight * 0.12,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _meditationPoses.length,
                      itemBuilder: (context, index) {
                        final pose = _meditationPoses[index];
                        final isSelected = index == _selectedPoseIndex;
                        final isSuitable = _isPoseSuitableForUser(index);

                        return GestureDetector(
                          onTap: () {
                            if (!_isActive) {
                              setState(() {
                                _selectedPoseIndex = index;
                              });
                            }
                          },
                          child: Container(
                            width: 96,
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (pose['color'] as Color).withOpacity(0.16)
                                  : BellaColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? pose['color'] as Color
                                    : BellaColors.divider,
                                width: 1.4,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  pose['icon'] as IconData,
                                  color: pose['color'] as Color,
                                  size: 20,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  pose['name'].toString().split(' ').first,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: BellaColors.textPrimary,
                                  ),
                                ),
                                if (!isSuitable)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          BellaColors.warning.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'Check',
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: BellaColors.warning,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final progressSize =
                      (constraints.maxHeight * 0.25).clamp(150.0, 220.0);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: BellaColors.surface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: BellaColors.divider),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: progressSize,
                                height: progressSize,
                                child: CircularProgressIndicator(
                                  value: progress.clamp(0.0, 1.0),
                                  strokeWidth: 10,
                                  color: currentPose['color'] as Color,
                                  backgroundColor:
                                      (currentPose['color'] as Color)
                                          .withOpacity(0.14),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _getTimeRemaining(),
                                    style: TextStyle(
                                      fontSize: progressSize * 0.20,
                                      fontWeight: FontWeight.bold,
                                      color: BellaColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    _isActive ? 'Remaining' : 'Duration',
                                    style: const TextStyle(
                                      color: BellaColors.textMuted,
                                    ),
                                  ),
                                  if (_isActive && _seconds > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        '${(_seconds / 60).toStringAsFixed(1)} min elapsed',
                                        style: const TextStyle(
                                          color: BellaColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: BellaColors.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: BellaColors.divider),
                          ),
                          child: _buildPoseDetails(),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: BellaColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: BellaColors.divider),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _resultColumn(
                                'Current HR',
                                '$_currentHeartRate',
                                _getHeartRateColor(_currentHeartRate),
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: BellaColors.divider,
                              ),
                              _resultColumn(
                                'Goal',
                                '${poseDuration ~/ 60}',
                                BellaColors.primary,
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: BellaColors.divider,
                              ),
                              Column(
                                children: [
                                  const Text(
                                    'Status',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BellaColors.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _isActive
                                          ? BellaColors.success
                                              .withOpacity(0.12)
                                          : BellaColors.surfaceAlt,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _isActive ? 'Active' : 'Ready',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _isActive
                                            ? BellaColors.success
                                            : BellaColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 96),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: const BoxDecoration(
                color: BellaColors.surface,
                border: Border(top: BorderSide(color: BellaColors.divider)),
              ),
              child: ElevatedButton(
                onPressed: _startMeditation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isActive
                      ? BellaColors.danger
                      : (currentPose['color'] as Color),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  minimumSize: const Size(double.infinity, 56),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isActive ? Icons.stop : Icons.play_arrow, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _isActive
                            ? 'STOP MEDITATION'
                            : 'BEGIN ${currentPose['name'].toString().split(' ').first.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
