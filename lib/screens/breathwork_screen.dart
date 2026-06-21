import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/data_storage_service.dart';
import '../theme/bella_theme.dart';

class BreathingTechnique {
  final String id;
  final String name;
  final String description;
  final String useCase;
  final List<Map<String, dynamic>> steps;
  final int totalCycles;
  final Color primaryColor;
  final Color secondaryColor;
  final String benefits;
  final String icon;

  BreathingTechnique({
    required this.id,
    required this.name,
    required this.description,
    required this.useCase,
    required this.steps,
    required this.totalCycles,
    required this.primaryColor,
    required this.secondaryColor,
    required this.benefits,
    required this.icon,
  });
}

class BreathworkScreen extends StatefulWidget {
  final int initialHeartRate;

  const BreathworkScreen({
    super.key,
    required this.initialHeartRate,
  });

  @override
  State<BreathworkScreen> createState() => _BreathworkScreenState();
}

class _BreathworkScreenState extends State<BreathworkScreen> {
  final BluetoothService _bt = BluetoothService.instance;
  final DataStorageService _dataStorage = DataStorageService();

  Timer? _timer;
  StreamSubscription? _hrSubscription;

  int _seconds = 0;
  int _currentHeartRate = 0;
  int _initialHeartRate = 0;
  String _currentPhase = 'Prepare';
  String _currentInstruction = 'Select a technique to begin...';
  int _phaseSeconds = 0;
  bool _isActive = false;
  bool _isCompleted = false;
  bool _showTechniqueSelection = true;
  BreathingTechnique? _selectedTechnique;
  int _currentStepIndex = 0;
  int _cycleCount = 0;

  final List<BreathingTechnique> _techniques = [
    BreathingTechnique(
      id: '478',
      name: '4-7-8 Breathing',
      description: 'Calms the nervous system and reduces anxiety',
      useCase: 'Anxiety Relief & Sleep',
      steps: [
        {
          'name': 'INHALE',
          'duration': 4,
          'instruction': 'Breathe in slowly through your nose',
        },
        {
          'name': 'HOLD',
          'duration': 7,
          'instruction': 'Hold your breath gently',
        },
        {
          'name': 'EXHALE',
          'duration': 8,
          'instruction': 'Exhale completely through your mouth',
        },
        {
          'name': 'REST',
          'duration': 4,
          'instruction': 'Rest before next cycle',
        },
      ],
      totalCycles: 4,
      primaryColor: BellaColors.secondary,
      secondaryColor: BellaColors.secondary.withOpacity(0.12),
      benefits:
          '• Reduces anxiety\n• Improves sleep\n• Calms nervous system\n• Lowers stress hormones',
      icon: '😴',
    ),
    BreathingTechnique(
      id: 'box',
      name: 'Box Breathing',
      description: 'Enhances focus and regulates the autonomic nervous system',
      useCase: 'Focus & Stress Control',
      steps: [
        {
          'name': 'INHALE',
          'duration': 4,
          'instruction': 'Breathe in deeply through your nose',
        },
        {
          'name': 'HOLD',
          'duration': 4,
          'instruction': 'Hold your breath',
        },
        {
          'name': 'EXHALE',
          'duration': 4,
          'instruction': 'Exhale slowly through your mouth',
        },
        {
          'name': 'HOLD',
          'duration': 4,
          'instruction': 'Hold with empty lungs',
        },
      ],
      totalCycles: 5,
      primaryColor: BellaColors.success,
      secondaryColor: BellaColors.success.withOpacity(0.12),
      benefits:
          '• Improves focus\n• Reduces stress\n• Enhances emotional regulation\n• Used by Navy SEALs',
      icon: '🧘',
    ),
    BreathingTechnique(
      id: 'coherent',
      name: 'Coherent Breathing',
      description: 'Balances heart rate variability and promotes relaxation',
      useCase: 'Heart Coherence & Relaxation',
      steps: [
        {
          'name': 'INHALE',
          'duration': 5,
          'instruction': 'Breathe in gently through your nose',
        },
        {
          'name': 'EXHALE',
          'duration': 5,
          'instruction': 'Exhale smoothly through your nose',
        },
      ],
      totalCycles: 6,
      primaryColor: BellaColors.primary,
      secondaryColor: BellaColors.primary.withOpacity(0.12),
      benefits:
          '• Balances nervous system\n• Improves heart rate variability\n• Promotes deep relaxation\n• Reduces cortisol',
      icon: '💓',
    ),
    BreathingTechnique(
      id: 'energizing',
      name: 'Energizing Breath',
      description: 'Increases energy and mental alertness',
      useCase: 'Energy & Alertness',
      steps: [
        {
          'name': 'INHALE',
          'duration': 2,
          'instruction': 'Quick inhale through your nose',
        },
        {
          'name': 'EXHALE',
          'duration': 2,
          'instruction': 'Quick exhale through your nose',
        },
      ],
      totalCycles: 30,
      primaryColor: BellaColors.warning,
      secondaryColor: BellaColors.warning.withOpacity(0.12),
      benefits:
          '• Increases energy\n• Boosts mental alertness\n• Enhances oxygenation\n• Reduces fatigue',
      icon: '⚡',
    ),
    BreathingTechnique(
      id: 'relaxing',
      name: 'Relaxing Breath',
      description: 'Deep relaxation and tension release',
      useCase: 'Deep Relaxation',
      steps: [
        {
          'name': 'INHALE',
          'duration': 6,
          'instruction': 'Breathe in deeply through your nose',
        },
        {
          'name': 'HOLD',
          'duration': 2,
          'instruction': 'Brief pause',
        },
        {
          'name': 'EXHALE',
          'duration': 8,
          'instruction': 'Exhale slowly through your mouth',
        },
      ],
      totalCycles: 5,
      primaryColor: BellaColors.accent,
      secondaryColor: BellaColors.accent.withOpacity(0.12),
      benefits:
          '• Releases muscle tension\n• Lowers blood pressure\n• Promotes deep relaxation\n• Calms the mind',
      icon: '🌊',
    ),
    BreathingTechnique(
      id: 'alternate',
      name: 'Alternate Nostril',
      description: 'Balances left and right brain hemispheres',
      useCase: 'Balance & Clarity',
      steps: [
        {
          'name': 'RIGHT INHALE',
          'duration': 4,
          'instruction': 'Close left nostril, inhale through right',
        },
        {
          'name': 'HOLD',
          'duration': 4,
          'instruction': 'Hold breath',
        },
        {
          'name': 'LEFT EXHALE',
          'duration': 4,
          'instruction': 'Close right, exhale through left',
        },
        {
          'name': 'LEFT INHALE',
          'duration': 4,
          'instruction': 'Inhale through left nostril',
        },
        {
          'name': 'HOLD',
          'duration': 4,
          'instruction': 'Hold breath',
        },
        {
          'name': 'RIGHT EXHALE',
          'duration': 4,
          'instruction': 'Close left, exhale through right',
        },
      ],
      totalCycles: 4,
      primaryColor: BellaColors.secondary,
      secondaryColor: BellaColors.secondary.withOpacity(0.12),
      benefits:
          '• Balances brain hemispheres\n• Improves focus\n• Reduces mental chatter\n• Enhances clarity',
      icon: '🌀',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentHeartRate = widget.initialHeartRate;
    _initialHeartRate = widget.initialHeartRate;

    _hrSubscription = _bt.dataStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _currentHeartRate = data.heartRate;
      });
    });
  }

  void _selectTechnique(BreathingTechnique technique) {
    setState(() {
      _selectedTechnique = technique;
      _showTechniqueSelection = false;
      _currentPhase = 'Prepare';
      _currentInstruction = 'Get ready to begin ${technique.name}...';
      _currentStepIndex = 0;
      _cycleCount = 0;
      _isActive = false;
      _isCompleted = false;
      _seconds = 0;
      _phaseSeconds = 0;
    });
  }

  void _goBackToSelection() {
    _stopSession();
    setState(() {
      _selectedTechnique = null;
      _showTechniqueSelection = true;
      _isActive = false;
      _isCompleted = false;
      _currentInstruction = 'Select a technique to begin...';
    });
  }

  void _startSession() {
    if (_selectedTechnique == null) return;

    if (_isActive) {
      _stopSession();
      return;
    }

    setState(() {
      _isActive = true;
      _isCompleted = false;
      _seconds = 0;
      _cycleCount = 0;
      _currentStepIndex = 0;
      _currentPhase = _selectedTechnique!.steps[0]['name'];
      _currentInstruction = _selectedTechnique!.steps[0]['instruction'];
      _phaseSeconds = 0;
      _initialHeartRate = _currentHeartRate;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _selectedTechnique == null) return;

      setState(() {
        _seconds++;
        _phaseSeconds++;

        final currentStep = _selectedTechnique!.steps[_currentStepIndex];
        final stepDuration = currentStep['duration'] as int;

        if (_phaseSeconds >= stepDuration) {
          _phaseSeconds = 0;
          _currentStepIndex++;

          if (_currentStepIndex >= _selectedTechnique!.steps.length) {
            _currentStepIndex = 0;
            _cycleCount++;

            if (_cycleCount >= _selectedTechnique!.totalCycles) {
              _completeSession();
              timer.cancel();
              return;
            }
          }

          final nextStep = _selectedTechnique!.steps[_currentStepIndex];
          _currentPhase = nextStep['name'];
          _currentInstruction = nextStep['instruction'];
        }
      });
    });
  }

  void _stopSession() {
    _timer?.cancel();
    setState(() {
      _isActive = false;
    });
  }

  void _completeSession() {
    _timer?.cancel();
    setState(() {
      _isActive = false;
      _isCompleted = true;
    });

    if (_selectedTechnique != null) {
      _dataStorage.saveBreathworkSession(
        technique: _selectedTechnique!.name,
        durationSeconds: _seconds,
        startHeartRate: _initialHeartRate,
        endHeartRate: _currentHeartRate,
        cyclesCompleted: _cycleCount,
        timestamp: DateTime.now(),
        benefits: _selectedTechnique!.benefits,
      );

      _dataStorage.updateDailyGoal(
        goalType: 'breathwork',
        progress: _seconds / 60.0,
        target: 5,
        date: DateTime.now(),
      );
    }
  }

  String _getProgressText() {
    if (_selectedTechnique == null) return '--';
    final currentStep = _selectedTechnique!.steps[_currentStepIndex];
    final stepDuration = currentStep['duration'] as int;
    final remaining = stepDuration - _phaseSeconds;
    return '$remaining';
  }

  String _getCalmAssessment() {
    final change = _initialHeartRate - _currentHeartRate;
    if (change > 10) return 'Excellent. Your heart rate dropped significantly.';
    if (change > 5) return 'Good progress. Your system is settling.';
    if (change > 0) return 'Small improvement. Stay with the rhythm.';
    if (change == 0) return 'Heart rate is steady. Keep your breath smooth.';
    return 'Heart rate rose slightly. Relax your jaw and shoulders.';
  }

  Color _getHeartRateColor() {
    final change = _initialHeartRate - _currentHeartRate;
    if (change > 10) return BellaColors.success;
    if (change > 5) return BellaColors.accent;
    if (change > 0) return BellaColors.warning;
    return BellaColors.danger;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hrSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showTechniqueSelection) {
      return _buildTechniqueSelection();
    }
    return _buildBreathworkSession();
  }

  Widget _buildTechniqueSelection() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Breathwork'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: BellaColors.appGradient,
        ),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Choose a technique based on how you want to feel.',
                style: TextStyle(
                  fontSize: 15,
                  color: BellaColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _techniques.length,
                itemBuilder: (context, index) {
                  final technique = _techniques[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: BellaColors.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: BellaColors.divider),
                    ),
                    child: InkWell(
                      onTap: () => _selectTechnique(technique),
                      borderRadius: BorderRadius.circular(22),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: technique.secondaryColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Text(
                                  technique.icon,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    technique.name,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: technique.primaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    technique.description,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: BellaColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: technique.primaryColor
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      technique.useCase,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: technique.primaryColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: BellaColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: BellaColors.surface,
                border: Border(top: BorderSide(color: BellaColors.divider)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    color: BellaColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Tip: track how your heart rate changes before and after each session.',
                      style: TextStyle(
                        color: BellaColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('How to Choose'),
                          content: const SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('• 4-7-8: for anxiety and sleep'),
                                Text('• Box Breathing: for focus and stress'),
                                Text('• Coherent: for heart coherence'),
                                Text('• Energizing: for alertness'),
                                Text('• Relaxing: for deep relaxation'),
                                Text('• Alternate Nostril: for clarity'),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: Navigator.of(context).pop,
                              child: const Text('Got it'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Help'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreathworkSession() {
    if (_selectedTechnique == null) return const SizedBox.shrink();

    final phaseDuration =
        _selectedTechnique!.steps[_currentStepIndex]['duration'] as int;
    final progress = phaseDuration == 0 ? 0.0 : _phaseSeconds / phaseDuration;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedTechnique!.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBackToSelection,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: BellaColors.appGradient,
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: BellaColors.surface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: BellaColors.divider),
                      ),
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 220,
                                height: 220,
                                child: CircularProgressIndicator(
                                  value: progress.clamp(0.0, 1.0),
                                  strokeWidth: 12,
                                  color: _selectedTechnique!.primaryColor,
                                  backgroundColor: _selectedTechnique!
                                      .primaryColor
                                      .withOpacity(0.15),
                                ),
                              ),
                              Column(
                                children: [
                                  Text(
                                    _currentPhase,
                                    style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                      color: _selectedTechnique!.primaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _getProgressText(),
                                    style: TextStyle(
                                      fontSize: 50,
                                      fontWeight: FontWeight.w900,
                                      color: _selectedTechnique!.primaryColor,
                                    ),
                                  ),
                                  const Text(
                                    'seconds',
                                    style: TextStyle(
                                      color: BellaColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          Text(
                            _currentInstruction,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              color: BellaColors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Cycle ${_cycleCount + 1}/${_selectedTechnique!.totalCycles}',
                            style: const TextStyle(
                              color: BellaColors.textMuted,
                              fontSize: 14,
                            ),
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
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _metricBlock(
                                'Initial',
                                '$_initialHeartRate',
                                BellaColors.textSecondary,
                              ),
                              const Icon(
                                Icons.arrow_forward,
                                color: BellaColors.textMuted,
                              ),
                              _metricBlock(
                                'Current',
                                '$_currentHeartRate',
                                _getHeartRateColor(),
                              ),
                              _metricBlock(
                                _initialHeartRate > _currentHeartRate
                                    ? 'Dropped'
                                    : 'Change',
                                '${(_initialHeartRate - _currentHeartRate).abs()}',
                                _initialHeartRate > _currentHeartRate
                                    ? BellaColors.success
                                    : BellaColors.warning,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _getHeartRateColor().withOpacity(0.10),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _getCalmAssessment(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _getHeartRateColor(),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_isCompleted) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: BellaColors.success.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Column(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: BellaColors.success,
                                    size: 34,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Session Complete',
                                    style: TextStyle(
                                      color: BellaColors.success,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: BellaColors.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: BellaColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Technique benefits',
                            style: TextStyle(
                              color: _selectedTechnique!.primaryColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _selectedTechnique!.benefits,
                            style: const TextStyle(
                              color: BellaColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              decoration: const BoxDecoration(
                color: BellaColors.surface,
                border: Border(top: BorderSide(color: BellaColors.divider)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _startSession,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isActive
                            ? BellaColors.danger
                            : _selectedTechnique!.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_isActive ? Icons.stop : Icons.play_arrow),
                          const SizedBox(width: 10),
                          Text(
                            _isActive
                                ? 'STOP SESSION'
                                : 'START ${_selectedTechnique!.name.toUpperCase()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _goBackToSelection,
                    child: const Text('Back to techniques'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBlock(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: BellaColors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
