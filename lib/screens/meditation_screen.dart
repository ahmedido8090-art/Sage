// screens/meditation_screen.dart
//
// Redesigned Meditation screen.
//
// What's new vs the original:
//   • Live breathing guide — the orb now expands/contracts to the exact
//     inhale/hold/exhale timing of the selected pose, with a phase label
//     (INHALE · HOLD · EXHALE) and per-phase countdown inside the orb.
//     This makes the breathing pattern actually useful rather than a
//     static text string.
//   • Duration picker — 5 / 10 / 15 / 20 min chips above the Start button.
//     The session progress ring and timer respect the chosen duration.
//   • Pose picker cards are taller (100 px) and show the energy-level tag
//     so the user can choose by mood.
//   • Pre-session layout reordered: benefits shown inline (no sheet required
//     for the most important info), "Steps & Precautions" sheet tap kept.
//   • Active session is full-screen calm mode: no distracting UI chrome,
//     just the orb, phase label, progress ring, and a subtle "Stop" text
//     button at the bottom.
//   • Completion dialog unchanged — still shows HR delta + check-in CTA.
//
// All existing data (poses, Bella context, BT heart-rate, DataStorage
// logging) is preserved exactly — only presentation changes.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/bluetooth_service.dart';
import '../services/data_storage_service.dart';
import '../services/bella_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/pressable.dart';
import 'daily_checkin_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Breathing-phase model
// ─────────────────────────────────────────────────────────────────────────────

class _BreathPhase {
  final String label;
  final int durationSeconds;
  final double orbTarget; // 0.0 (small) → 1.0 (large)
  const _BreathPhase(this.label, this.durationSeconds, this.orbTarget);
}

// Returns the list of breath phases for a pose based on its breathingPace tag.
// We define four patterns; each maps to a pose's 'breathingPatternId'.
List<_BreathPhase> _phasesFor(String patternId) {
  switch (patternId) {
    case '478':
      return [
        _BreathPhase('Inhale', 4, 1.0),
        _BreathPhase('Hold', 7, 1.0),
        _BreathPhase('Exhale', 8, 0.0),
      ];
    case 'equal':
      return [
        _BreathPhase('Inhale', 5, 1.0),
        _BreathPhase('Exhale', 5, 0.0),
      ];
    case 'box':
      return [
        _BreathPhase('Inhale', 4, 1.0),
        _BreathPhase('Hold', 4, 1.0),
        _BreathPhase('Exhale', 4, 0.0),
        _BreathPhase('Hold', 4, 0.0),
      ];
    case 'natural':
    default:
      return [
        _BreathPhase('Breathe in', 4, 1.0),
        _BreathPhase('Breathe out', 4, 0.0),
      ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

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

class _MeditationScreenState extends State<MeditationScreen>
    with TickerProviderStateMixin {
  // ── Services ───────────────────────────────────────────────────────────────
  final BluetoothService _bt = BluetoothService.instance;
  final DataStorageService _dataStorage = DataStorageService();
  final BellaService _bella = BellaService();

  // ── Session state ──────────────────────────────────────────────────────────
  Timer? _sessionTimer;
  int _seconds = 0;
  int _currentHeartRate = 0;
  bool _isActive = false;
  int _selectedPoseIndex = 0;
  int _selectedDurationMinutes = 10;
  List<int> _heartRateHistory = [];

  // ── Breathing guide state ──────────────────────────────────────────────────
  int _phaseIndex = 0; // index into current pose's phase list
  int _phaseSeconds = 0; // seconds elapsed in current phase
  Timer? _breathTimer;

  // ── Bella context ──────────────────────────────────────────────────────────
  int _todayMinutes = 0;
  int _targetMinutes = 10;
  String? _selectionReason;
  String? _lastSessionLabel;
  int _weekStreak = 0;

  // ── Chronic reading context ────────────────────────────────────────────────
  // Non-null when the user has a recent reading that makes meditating
  // especially timely. Positive-framed where possible (Hypertension + high BP
  // → encourage the session) or a gentle caution (low glucose → snack first).
  String? _chronicReadingNote;
  Color? _chronicReadingColor;

  // ── Orb animation ─────────────────────────────────────────────────────────
  late AnimationController _orbController;
  late Animation<double> _orbScale; // 0.0→1.0 maps to small→large

  // Glow aura — pulses independently of the orb scale so the border and
  // shadow have their own breathing rhythm, giving the orb a living feel.
  late AnimationController _glowController;
  late Animation<double> _glowOpacity; // 0.15→0.9

  // Single bell player — fires once at session start and once at end.
  final AudioPlayer _bellPlayer = AudioPlayer();

  // ── Poses ──────────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _meditationPoses = [
    {
      'name': 'Lotus Pose (Padmasana)',
      'shortName': 'Lotus',
      'icon': Icons.self_improvement,
      'color': SageColors.clay,
      'breathingPatternId': '478',
      'breathingPattern': '4-7-8 · inhale 4s, hold 7s, exhale 8s',
      'difficulty': 'Intermediate',
      'energyLevel': 'Calming',
      'benefits': [
        'Improves focus and concentration',
        'Reduces stress and anxiety',
        'Calms the nervous system',
      ],
      'stepByStep': [
        'Sit on the floor with legs extended',
        'Bend right knee, place right foot on left thigh',
        'Bend left knee, place left foot on right thigh',
        'Keep spine straight and shoulders relaxed',
        'Place hands on knees in Gyan Mudra',
        'Close eyes and focus on your breath',
      ],
      'precautions': [
        'Avoid if you have knee or ankle injuries',
        'Use a cushion under hips if needed',
        'Do not force the position',
      ],
      'suitableForBMI': ['Underweight', 'Normal', 'Overweight'],
    },
    {
      'name': 'Easy Pose (Sukhasana)',
      'shortName': 'Easy',
      'icon': Icons.accessible,
      'color': SageColors.sage,
      'breathingPatternId': 'equal',
      'breathingPattern': 'Equal · inhale 5s, exhale 5s',
      'difficulty': 'Beginner',
      'energyLevel': 'Balancing',
      'benefits': [
        'Grounding and calming effect',
        'Reduces mental fatigue',
        'Good for daily practice',
      ],
      'stepByStep': [
        'Sit on floor or cushion with legs crossed',
        'Allow knees to drop toward floor naturally',
        'Rest hands on knees with palms facing up',
        'Align head, neck, and spine vertically',
        'Relax facial muscles and jaw',
        'Focus on natural breath rhythm',
      ],
      'precautions': [
        'Use a cushion if hips are tight',
        'Alternate cross of legs periodically',
        'Keep back supported if needed',
      ],
      'suitableForBMI': ['Underweight', 'Normal', 'Overweight', 'Obese'],
    },
    {
      'name': 'Chair Meditation',
      'shortName': 'Chair',
      'icon': Icons.chair,
      'color': SageColors.moss,
      'breathingPatternId': 'box',
      'breathingPattern': 'Box · inhale 4s, hold 4s, exhale 4s, hold 4s',
      'difficulty': 'Beginner',
      'energyLevel': 'Grounding',
      'highBMIFriendly': true,
      'benefits': [
        'Perfect for beginners and office workers',
        'Easier on joints and back',
        'Reduces work-related stress',
      ],
      'stepByStep': [
        'Sit on chair with feet flat on floor',
        'Keep knees at 90-degree angle',
        'Place hands on thighs with palms up or down',
        'Keep back straight, not leaning on backrest',
        'Shoulders relaxed, chin parallel to floor',
        'Close eyes or soften gaze downward',
      ],
      'precautions': [
        'Ensure feet reach floor comfortably',
        'Use a chair without wheels for stability',
        'Place a cushion on seat if needed',
      ],
      'suitableForBMI': ['Underweight', 'Normal', 'Overweight', 'Obese'],
    },
    {
      'name': 'Corpse Pose (Savasana)',
      'shortName': 'Savasana',
      'icon': Icons.nightlight_round,
      'color': SageColors.inkSoft,
      'breathingPatternId': 'natural',
      'breathingPattern': 'Natural · observe without changing',
      'difficulty': 'Beginner',
      'energyLevel': 'Deeply Relaxing',
      'highBMIFriendly': true,
      'jointFriendly': true,
      'benefits': [
        'Deep relaxation and stress relief',
        'Reduces blood pressure and heart rate',
        'Improves sleep quality',
      ],
      'stepByStep': [
        'Lie flat on back on a comfortable surface',
        'Extend legs comfortably apart',
        'Place arms at sides, palms facing up',
        'Allow feet to fall outward naturally',
        'Close eyes and release all muscle tension',
        'Focus on breath without controlling it',
      ],
      'precautions': [
        'Use a pillow under knees if back hurts',
        'Cover with a blanket if feeling cold',
        'Avoid falling asleep during meditation',
      ],
      'suitableForBMI': ['Underweight', 'Normal', 'Overweight', 'Obese'],
    },
    {
      'name': 'Mountain Pose (Tadasana)',
      'shortName': 'Mountain',
      'icon': Icons.terrain,
      'color': SageColors.amber,
      'breathingPatternId': 'equal',
      'breathingPattern': 'Ujjayi · ocean breath, slightly constricted throat',
      'difficulty': 'Beginner',
      'energyLevel': 'Grounding',
      'benefits': [
        'Improves posture and balance',
        'Increases body awareness',
        'Grounding and centering effect',
      ],
      'stepByStep': [
        'Stand with feet hip-width apart',
        'Distribute weight evenly on both feet',
        'Engage thigh muscles, lift kneecaps',
        'Lengthen spine, crown reaching up',
        'Relax shoulders away from ears',
        'Hands at sides or in prayer position',
      ],
      'precautions': [
        'Avoid locking knees',
        'Keep a slight bend in knees if needed',
        'Focus on steady balance',
      ],
      'suitableForBMI': ['Underweight', 'Normal', 'Overweight'],
    },
  ];

  // ── Available duration options ─────────────────────────────────────────────
  static const List<int> _durationOptions = [5, 10, 15, 20];

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _currentHeartRate = widget.initialHeartRate;
    _heartRateHistory = [widget.initialHeartRate];

    _targetMinutes = _bella.getTarget<int>('meditationMinutes') ?? 10;
    _todayMinutes = _bella.sessionMinutesToday('meditation');
    // Snap the default duration to the target if it's in our options.
    if (_durationOptions.contains(_targetMinutes)) {
      _selectedDurationMinutes = _targetMinutes;
    }

    _loadBellaContext();
    _loadChronicReadingContext();

    _bt.dataStream.listen((data) {
      if (mounted) {
        setState(() {
          _currentHeartRate = data.heartRate;
          if (_isActive && _seconds % 30 == 0) {
            _heartRateHistory.add(data.heartRate);
          }
        });
      }
    });

    _selectPoseForContext();

    // Orb controller — duration is overridden per-phase when a session starts.
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _orbScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _orbController, curve: Curves.easeInOut),
    );

    // Glow aura — slow independent pulse so border and shadow breathe
    // separately from the orb scale, giving a layered living feel.
    _glowController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800))
      ..repeat(reverse: true);
    _glowOpacity = Tween<double>(begin: 0.15, end: 0.9).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Bell — fires once at start, once at end. mixWithOthers so it doesn't
    // steal audio focus from sleep sounds.
    _bellPlayer.setAudioContext(AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
      android: const AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: false,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.assistanceSonification,
        audioFocus: AndroidAudioFocus.none,
      ),
    ));
  }

  void _loadBellaContext() {
    final sessions = _bella.getSessions(type: 'meditation');
    if (sessions.isNotEmpty) {
      final last = sessions.first;
      final diff = DateTime.now().difference(last.date);
      final when = diff.inDays == 0
          ? 'today'
          : diff.inDays == 1
              ? 'yesterday'
              : '${diff.inDays}d ago';
      _lastSessionLabel = '${last.durationMinutes} min · $when';
    }
    final now = DateTime.now();
    final days = sessions
        .where((s) => now.difference(s.date).inDays < 7)
        .map((s) => '${s.date.year}-${s.date.month}-${s.date.day}')
        .toSet();
    _weekStreak = days.length;
  }

  /// Checks the most recent reading for each chronic condition (last 7 days)
  /// and sets [_chronicReadingNote] to a condition-specific message.
  /// Flagged (out-of-range) readings are checked first — they carry the
  /// strongest positive cue to meditate. In-range readings produce a softer
  /// encouragement note. Only the single highest-priority signal is shown.
  void _loadChronicReadingContext() {
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];
    if (conditions.isEmpty) return;
    final now = DateTime.now();

    // First pass — flagged readings only (most actionable positive cue).
    // Collect every flagged condition's note (not just the first) so a user
    // with e.g. Diabetes + Hypertension both flagged sees both, not just
    // whichever condition happens to be first in their list.
    final flaggedNotes = <_ChronicNote>[];
    for (final cond in conditions) {
      final readings = _bella.getReadings(condition: cond);
      if (readings.isEmpty) continue;
      final r = readings.first;
      if (now.difference(r.time).inDays > 7) continue;
      final note = _noteForReading(cond, r.value, r.secondaryValue, r.unit,
          flaggedOnly: true);
      if (note != null) flaggedNotes.add(note);
    }
    if (flaggedNotes.isNotEmpty) {
      if (flaggedNotes.length == 1) {
        _chronicReadingNote = flaggedNotes.first.text;
      } else {
        // Concatenate up to two short notes so neither condition is hidden.
        _chronicReadingNote = flaggedNotes.take(2).map((n) => n.text).join(' ');
      }
      _chronicReadingColor = flaggedNotes.first.color;
      return;
    }

    // Second pass — in-range readings (softer encouragement).
    for (final cond in conditions) {
      final readings = _bella.getReadings(condition: cond);
      if (readings.isEmpty) continue;
      final r = readings.first;
      if (now.difference(r.time).inDays > 7) continue;
      final note = _noteForReading(cond, r.value, r.secondaryValue, r.unit,
          flaggedOnly: false);
      if (note != null) {
        _chronicReadingNote = note.text;
        _chronicReadingColor = note.color;
        return;
      }
    }
  }

  _ChronicNote? _noteForReading(
    String condition,
    double value,
    double? secondary,
    String unit, {
    required bool flaggedOnly,
  }) {
    final valStr = value.toStringAsFixed(0);
    final secStr = secondary != null ? '/${secondary.toStringAsFixed(0)}' : '';

    switch (condition) {
      case 'Hypertension':
        final high = value >= 140 || (secondary ?? 0) >= 90;
        if (high) {
          return _ChronicNote(
            'Blood pressure is elevated ($valStr$secStr $unit) — '
            'meditation reliably lowers systolic pressure. Good time to practice.',
            SageColors.moss,
          );
        }
        if (!flaggedOnly) {
          return _ChronicNote(
            'Your last BP reading is in a healthy range. '
            'Regular meditation helps keep it there.',
            SageColors.moss,
          );
        }

      case 'Diabetes':
        if (value > 180) {
          return _ChronicNote(
            'Glucose is elevated ($valStr $unit) — stress raises cortisol, '
            'which pushes glucose higher. A calming session now can help bring both down.',
            SageColors.moss,
          );
        }
        if (value < 70) {
          return _ChronicNote(
            'Glucose is low ($valStr $unit) — have a small snack before '
            'starting to avoid lightheadedness during meditation.',
            SageColors.amber,
          );
        }
        if (!flaggedOnly) {
          return _ChronicNote(
            'Glucose is in range. Consistent meditation helps stabilise '
            'stress-related glucose spikes over time.',
            SageColors.moss,
          );
        }

      case 'Heart Disease':
        final high = value >= 140 || (secondary ?? 0) >= 90;
        if (high) {
          return _ChronicNote(
            'A recent heart-related reading was elevated — a short, '
            'gentle session (Savasana or Easy pose) supports cardiovascular calm. '
            'Stop if you feel any chest discomfort.',
            SageColors.amber,
          );
        }
        if (!flaggedOnly) {
          return _ChronicNote(
            'Consistent meditation reduces resting heart rate and '
            'supports long-term heart health.',
            SageColors.moss,
          );
        }

      case 'Asthma':
        if (value < 80) {
          // value is % predicted peak flow
          return _ChronicNote(
            'Peak flow is low ($valStr% predicted) — choose a seated or '
            'lying-down pose and keep breathing gentle. Skip breath-hold techniques today.',
            SageColors.amber,
          );
        }
        if (!flaggedOnly) {
          return _ChronicNote(
            'Peak flow is good. Slow, controlled breathing during meditation '
            'can reduce asthma trigger sensitivity over time.',
            SageColors.moss,
          );
        }

      case 'High Cholesterol':
        if (!flaggedOnly) {
          return _ChronicNote(
            'Meditation reduces the cortisol that drives cholesterol '
            'production. Every session contributes to long-term improvement.',
            SageColors.moss,
          );
        }

      case 'Arthritis':
        if (!flaggedOnly) {
          return _ChronicNote(
            'If joints are stiff today, Chair Meditation or Savasana '
            'avoids pressure on knees and hips.',
            SageColors.moss,
          );
        }

      default:
        return null;
    }
    return null;
  }

  void _selectPoseForContext() {
    final suitablePoses = <int>[];
    for (int i = 0; i < _meditationPoses.length; i++) {
      if (_isPoseSuitable(i)) suitablePoses.add(i);
    }
    if (suitablePoses.isEmpty) return;

    final checkin = _bella.lastCheckin;
    final lastSleep = _bella.lastNightSleep;
    final isEvening = DateTime.now().hour >= 20;
    final poorSleep = lastSleep != null && lastSleep.quality <= 2;
    final highStress = checkin != null && checkin.stress >= 4;

    // Food context — a heavy recent meal makes seated meditation uncomfortable.
    final now = DateTime.now();
    final recentHeavyMeal = _bella.getFoodEntries(onDate: now).any((f) {
      final age = now.difference(f.time).inMinutes;
      return age <= 90 && (f.calories ?? 0) >= 500;
    });

    if (widget.bmi >= 30) {
      for (int i in suitablePoses) {
        if (_meditationPoses[i]['highBMIFriendly'] == true) {
          _selectedPoseIndex = i;
          _selectionReason = 'Selected for comfort at your BMI';
          return;
        }
      }
    }
    if (isEvening || poorSleep) {
      for (int i in suitablePoses) {
        final e = _meditationPoses[i]['energyLevel'] as String;
        if (e == 'Deeply Relaxing' || e == 'Calming') {
          _selectedPoseIndex = i;
          _selectionReason = poorSleep
              ? 'Selected for sleep recovery'
              : 'Selected for evening wind-down';
          return;
        }
      }
    }
    if (highStress) {
      for (int i in suitablePoses) {
        if (_meditationPoses[i]['difficulty'] == 'Beginner') {
          _selectedPoseIndex = i;
          _selectionReason = 'Selected for high-stress recovery';
          return;
        }
      }
    }
    _selectedPoseIndex = suitablePoses[0];
    _selectionReason = null;
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _breathTimer?.cancel();
    _orbController.dispose();
    _glowController.dispose();
    _bellPlayer.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String get _bmiCategory {
    if (widget.bmi < 18.5) return 'Underweight';
    if (widget.bmi < 25) return 'Normal';
    if (widget.bmi < 30) return 'Overweight';
    return 'Obese';
  }

  bool _isPoseSuitable(int index) {
    final suitable = _meditationPoses[index]['suitableForBMI'] as List<String>;
    return suitable.contains(_bmiCategory);
  }

  Color _getBMIColor() {
    if (widget.bmi < 18.5) return SageColors.sage;
    if (widget.bmi < 25) return SageColors.moss;
    if (widget.bmi < 30) return SageColors.amber;
    return SageColors.clay;
  }

  Color _getHRColor(int hr) {
    if (hr < 60) return SageColors.sage;
    if (hr < 100) return SageColors.moss;
    if (hr < 120) return SageColors.amber;
    return SageColors.clay;
  }

  int get _sessionDurationSeconds => _selectedDurationMinutes * 60;

  String _formatRemaining() {
    final remaining = _sessionDurationSeconds - _seconds;
    final m = (remaining ~/ 60).toString().padLeft(2, '0');
    final s = (remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double _calculateCalmScore(int startHR, int endHR) {
    final change = startHR - endHR;
    if (change > 15) return 1.0;
    if (change > 8) return 0.7;
    if (change > 0) return 0.4;
    return 0.1;
  }

  List<_BreathPhase> get _currentPhases {
    final id =
        _meditationPoses[_selectedPoseIndex]['breathingPatternId'] as String;
    return _phasesFor(id);
  }

  _BreathPhase get _currentPhase => _currentPhases[_phaseIndex];

  // How far through the current phase (0.0–1.0) — for the phase progress bar.
  double get _phaseProgress => _currentPhase.durationSeconds > 0
      ? (_phaseSeconds / _currentPhase.durationSeconds).clamp(0.0, 1.0)
      : 0.0;

  // ─────────────────────────────────────────────────────────────────────────
  // Session control
  // ─────────────────────────────────────────────────────────────────────────

  void _startMeditation() {
    setState(() {
      _isActive = true;
      _seconds = 0;
      _phaseIndex = 0;
      _phaseSeconds = 0;
      _heartRateHistory = [_currentHeartRate];
    });

    // Single soft bell to signal session start.
    _playBell();

    // Drive the orb to the first phase target immediately.
    _animateOrbToPhase(_currentPhases[0]);

    // Session clock — ticks every second.
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= _sessionDurationSeconds) {
        _completeMeditation();
      }
    });

    // Breath ticker — advances phases.
    _breathTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _phaseSeconds++;
        if (_phaseSeconds >= _currentPhase.durationSeconds) {
          _phaseSeconds = 0;
          _phaseIndex = (_phaseIndex + 1) % _currentPhases.length;
          _animateOrbToPhase(_currentPhases[_phaseIndex]);
        }
      });
    });
  }

  Future<void> _playBell({double volume = 0.45}) async {
    try {
      await _bellPlayer.stop();
      await _bellPlayer.play(AssetSource('audio/bell_high.mp3'),
          volume: volume);
    } catch (_) {} // degrade silently if asset missing
  }

  void _animateOrbToPhase(_BreathPhase phase) {
    _orbController.duration = Duration(seconds: phase.durationSeconds);
    // Determine start value from current animation position.
    final begin = _orbScale.value;
    _orbScale = Tween<double>(begin: begin, end: phase.orbTarget).animate(
      CurvedAnimation(parent: _orbController, curve: Curves.easeInOut),
    );
    _orbController.forward(from: 0);
  }

  void _stopMeditation() {
    _sessionTimer?.cancel();
    _breathTimer?.cancel();
    _orbController.stop();
    setState(() => _isActive = false);
    if (_seconds >= 60) {
      final pose = _meditationPoses[_selectedPoseIndex];
      _bella.logSession('meditation', _seconds ~/ 60,
          detail: pose['shortName'] as String?);
      _dataStorage.updateDailyGoal(
        goalType: 'meditation',
        progress: _seconds / 60.0,
        target: _selectedDurationMinutes.toDouble(),
        date: DateTime.now(),
      );
    }
  }

  void _completeMeditation() {
    _sessionTimer?.cancel();
    _breathTimer?.cancel();
    _orbController.stop();
    setState(() => _isActive = false);

    // Single bell to signal session end — slightly louder than the start bell.
    _playBell(volume: 0.6);

    final pose = _meditationPoses[_selectedPoseIndex];
    _bella.logSession('meditation', _seconds ~/ 60,
        detail: pose['shortName'] as String?);
    final initialHR = widget.initialHeartRate;
    final finalHR = _currentHeartRate;
    final change = initialHR - finalHR;

    _dataStorage.saveMeditationSession(
      poseName: pose['name'] as String,
      durationSeconds: _seconds,
      startHeartRate: initialHR,
      endHeartRate: finalHR,
      timestamp: DateTime.now(),
      benefits: (pose['benefits'] as List<String>).join(', '),
      calmScore: _calculateCalmScore(initialHR, finalHR),
    );
    _dataStorage.updateDailyGoal(
      goalType: 'meditation',
      progress: _seconds / 60.0,
      target: _selectedDurationMinutes.toDouble(),
      date: DateTime.now(),
    );

    _showCompletionDialog(initialHR, finalHR, change);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Completion dialog
  // ─────────────────────────────────────────────────────────────────────────

  void _showCompletionDialog(int initialHR, int finalHR, int change) {
    final weekSessions = _bella
        .getSessions(type: 'meditation')
        .where((s) => DateTime.now().difference(s.date).inDays < 7)
        .length;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SageColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: SageColors.moss.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child:
                Icon(Icons.self_improvement, color: SageColors.moss, size: 28),
          ),
          const SizedBox(height: 10),
          Text('Session complete',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: SageColors.ink),
              textAlign: TextAlign.center),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SageColors.linen,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SageColors.line),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _hrCol('$initialHR', 'Before', SageColors.inkSoft),
                  Icon(Icons.arrow_forward,
                      color: SageColors.inkSoft, size: 16),
                  _hrCol('$finalHR', 'After', SageColors.moss),
                  Icon(Icons.arrow_forward,
                      color: SageColors.inkSoft, size: 16),
                  _hrCol(
                    '${change.abs()} bpm',
                    change > 0
                        ? 'Down ↓'
                        : change < 0
                            ? 'Up ↑'
                            : 'Stable',
                    change > 0
                        ? SageColors.moss
                        : change < 0
                            ? SageColors.clay
                            : SageColors.amber,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              change > 5
                  ? 'Excellent — heart rate dropped significantly.'
                  : change > 0
                      ? 'Good work — heart rate decreased.'
                      : 'Try a different pose or longer session next time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: change > 5
                    ? SageColors.moss
                    : change > 0
                        ? SageColors.sage
                        : SageColors.amber,
                fontSize: 13,
              ),
            ),
            if (weekSessions > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: SageColors.moss.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$weekSessions session${weekSessions == 1 ? '' : 's'} this week 🌿',
                  style: TextStyle(
                      fontSize: 12,
                      color: SageColors.moss,
                      fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 6),
            Text('How are you feeling now?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: SageColors.inkSoft)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Skip', style: TextStyle(color: SageColors.inkSoft)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DailyCheckinScreen()));
            },
            style: ElevatedButton.styleFrom(backgroundColor: SageColors.moss),
            child: const Text('Log check-in'),
          ),
        ],
      ),
    );
  }

  Widget _hrCol(String value, String label, Color color) => Column(
        children: [
          Text(value,
              style: SageText.mono(
                  size: 15, weight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 10, color: SageColors.inkSoft)),
        ],
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pose = _meditationPoses[_selectedPoseIndex];
    final accent = pose['color'] as Color;
    final progress = (_seconds / _sessionDurationSeconds).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: SageColors.linen,
      appBar: _isActive
          ? null // hide app bar during active session for calm full-screen
          : AppBar(
              title: Text('Meditation', style: SageText.headline()),
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                // Today's progress chip
                Container(
                  margin: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: SageColors.moss.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: SageColors.moss.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    '$_todayMinutes / $_targetMinutes min today',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: SageColors.moss,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                // HR chip
                if (_currentHeartRate > 0)
                  Container(
                    margin:
                        const EdgeInsets.only(right: 16, top: 10, bottom: 10),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getHRColor(_currentHeartRate)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _getHRColor(_currentHeartRate)
                              .withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.favorite,
                          size: 12, color: _getHRColor(_currentHeartRate)),
                      const SizedBox(width: 4),
                      Text('$_currentHeartRate',
                          style: SageText.mono(
                              size: 12,
                              weight: FontWeight.w700,
                              color: _getHRColor(_currentHeartRate))),
                    ]),
                  ),
              ],
            ),
      body: AnimatedSwitcher(
        duration: SageMotion.revealSmall,
        switchInCurve: SageMotion.revealCurve,
        switchOutCurve: Curves.easeIn,
        child: _isActive
            ? KeyedSubtree(
                key: const ValueKey('active'),
                child: _buildActiveSession(pose, accent, progress),
              )
            : KeyedSubtree(
                key: const ValueKey('pre'),
                child: _buildPreSession(pose, accent),
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pre-session view
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPreSession(Map<String, dynamic> pose, Color accent) {
    // Compute recent heavy meal for food timing note.
    final now = DateTime.now();
    final recentHeavyMeal = _bella.getFoodEntries(onDate: now).any((f) {
      final age = now.difference(f.time).inMinutes;
      return age <= 90 && (f.calories ?? 0) >= 500;
    });

    return Column(
      children: [
        // ── Pose picker strip ──────────────────────────────────────────
        Container(
          color: SageColors.card,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CHOOSE POSE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                      color: SageColors.inkSoft)),
              const SizedBox(height: 10),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _meditationPoses.length,
                  itemBuilder: (context, index) => _buildPoseCard(index),
                ),
              ),
            ],
          ),
        ),

        // ── Scrollable body ────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pose detail card
                _buildPoseDetailCard(pose, accent),
                const SizedBox(height: 20),

                // Context row: streak + last session
                if (_weekStreak > 0 || _lastSessionLabel != null)
                  _buildContextRow(),

                if (_weekStreak > 0 || _lastSessionLabel != null)
                  const SizedBox(height: 20),

                // Chronic reading note — positive cue or gentle caution
                // based on the user's most recent relevant reading.
                if (_chronicReadingNote != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_chronicReadingColor ?? SageColors.moss)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: (_chronicReadingColor ?? SageColors.moss)
                              .withValues(alpha: 0.22)),
                    ),
                    child: Row(children: [
                      Icon(Icons.monitor_heart_outlined,
                          size: 15,
                          color: _chronicReadingColor ?? SageColors.moss),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _chronicReadingNote!,
                          style: TextStyle(
                              fontSize: 12,
                              color: _chronicReadingColor ?? SageColors.moss,
                              height: 1.4),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // Food timing note — a heavy recent meal makes seated
                // meditation uncomfortable; surface it before they start.
                if (recentHeavyMeal) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SageColors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: SageColors.amber.withValues(alpha: 0.22)),
                    ),
                    child: Row(children: [
                      Icon(Icons.restaurant_outlined,
                          size: 15, color: SageColors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Heavy meal logged in the last 90 min — a light snack or '
                          'waiting 30 min works better for seated meditation.',
                          style: TextStyle(
                              fontSize: 12,
                              color: SageColors.amber,
                              height: 1.4),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // Duration picker
                _buildDurationPicker(accent),
                const SizedBox(height: 20),

                // BMI note (compact)
                _buildBMINote(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // ── Start button ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          decoration: BoxDecoration(
            color: SageColors.card,
            border: Border(top: BorderSide(color: SageColors.line)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _startMeditation,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: SageColors.linen,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_arrow_rounded),
                  const SizedBox(width: 8),
                  Text(
                    'BEGIN ${(pose['shortName'] as String).toUpperCase()} · $_selectedDurationMinutes MIN',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPoseCard(int index) {
    final p = _meditationPoses[index];
    final isSelected = index == _selectedPoseIndex;
    final pAccent = p['color'] as Color;
    final isSuitable = _isPoseSuitable(index);

    return Pressable(
      onTap: () => setState(() {
        _selectedPoseIndex = index;
        _selectionReason = null;
      }),
      child: AnimatedContainer(
        duration: SageMotion.valueChange,
        width: 90,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              isSelected ? pAccent.withValues(alpha: 0.12) : SageColors.linen,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? pAccent : SageColors.line,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(p['icon'] as IconData,
                color: isSelected ? pAccent : SageColors.inkSoft, size: 22),
            const SizedBox(height: 6),
            Text(p['shortName'] as String,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected ? pAccent : SageColors.inkSoft,
                  height: 1.2,
                )),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: (isSelected ? pAccent : SageColors.inkSoft)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                (p['energyLevel'] as String).split(' ').first,
                style: TextStyle(
                  fontSize: 8.5,
                  color: isSelected ? pAccent : SageColors.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!isSuitable)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('check BMI',
                    style: TextStyle(fontSize: 7.5, color: SageColors.amber)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPoseDetailCard(Map<String, dynamic> pose, Color accent) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SageColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(pose['icon'] as IconData, color: accent, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pose['name'] as String,
                      style: SageText.headline().copyWith(fontSize: 17)),
                  if (_selectionReason != null) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.auto_awesome,
                          size: 11, color: SageColors.moss),
                      const SizedBox(width: 4),
                      Text(_selectionReason!,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: SageColors.moss,
                              fontWeight: FontWeight.w500)),
                    ]),
                  ],
                ],
              ),
            ),
          ]),

          const SizedBox(height: 14),

          // Info chips
          Row(children: [
            _infoChip(Icons.speed, pose['difficulty'] as String, accent),
            const SizedBox(width: 8),
            _infoChip(Icons.bolt, pose['energyLevel'] as String, accent),
          ]),

          const SizedBox(height: 14),

          // Benefits — shown inline (no sheet tap needed)
          Text('Benefits',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SageColors.inkSoft,
                  letterSpacing: 0.3)),
          const SizedBox(height: 8),
          ...(pose['benefits'] as List<String>).map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 13, color: SageColors.moss),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(b,
                          style: TextStyle(
                              fontSize: 13,
                              color: SageColors.ink,
                              height: 1.3)),
                    ),
                  ],
                ),
              )),

          const SizedBox(height: 12),

          // Breathing pattern chip
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: SageColors.moss.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SageColors.moss.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.air, color: SageColors.moss, size: 15),
              const SizedBox(width: 9),
              Expanded(
                child: Text(pose['breathingPattern'] as String,
                    style: TextStyle(
                        fontSize: 12.5, color: SageColors.ink, height: 1.4)),
              ),
            ]),
          ),

          const SizedBox(height: 12),

          // Steps & precautions tap
          GestureDetector(
            onTap: () => _showDetailsSheet(pose, accent),
            child: Row(children: [
              Text('Steps & precautions',
                  style: TextStyle(
                      fontSize: 13,
                      color: SageColors.moss,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios, size: 12, color: SageColors.moss),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildContextRow() {
    return Row(children: [
      if (_weekStreak > 0)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SageColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SageColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('THIS WEEK',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: SageColors.inkSoft)),
                const SizedBox(height: 6),
                Row(children: [
                  Text('$_weekStreak',
                      style: SageText.mono(
                          size: 24,
                          weight: FontWeight.w700,
                          color: SageColors.moss)),
                  const SizedBox(width: 5),
                  Text('day${_weekStreak == 1 ? '' : 's'} 🌿',
                      style:
                          TextStyle(fontSize: 13, color: SageColors.inkSoft)),
                ]),
              ],
            ),
          ),
        ),
      if (_weekStreak > 0 && _lastSessionLabel != null)
        const SizedBox(width: 12),
      if (_lastSessionLabel != null)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SageColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SageColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LAST SESSION',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: SageColors.inkSoft)),
                const SizedBox(height: 6),
                Text(_lastSessionLabel!,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SageColors.ink)),
              ],
            ),
          ),
        ),
    ]);
  }

  Widget _buildDurationPicker(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DURATION',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
                color: SageColors.inkSoft)),
        const SizedBox(height: 10),
        Row(
          children: _durationOptions.map((mins) {
            final selected = mins == _selectedDurationMinutes;
            return Expanded(
              child: Pressable(
                onTap: () => setState(() => _selectedDurationMinutes = mins),
                child: AnimatedContainer(
                  duration: SageMotion.valueChange,
                  margin: EdgeInsets.only(
                      right: mins == _durationOptions.last ? 0 : 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? accent : SageColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: selected ? accent : SageColors.line),
                  ),
                  child: Text(
                    '$mins min',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? SageColors.linen : SageColors.inkSoft,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBMINote() {
    final suitable = _isPoseSuitable(_selectedPoseIndex);
    final color = suitable ? _getBMIColor() : SageColors.amber;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, size: 15, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'BMI ${widget.bmi.toStringAsFixed(1)} · $_bmiCategory — '
            '${suitable ? 'This pose suits your profile.' : 'Consider an alternative pose for your profile.'}',
            style: TextStyle(fontSize: 12.5, color: color, height: 1.4),
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Active session — full-screen calm mode
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActiveSession(
      Map<String, dynamic> pose, Color accent, double progress) {
    final phase = _currentPhase;
    final phases = _currentPhases;

    return SafeArea(
      child: Column(
        children: [
          // Top bar: pose name + HR
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('MEDITATING',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                        color: SageColors.inkSoft)),
                Text(pose['shortName'] as String,
                    style: SageText.headline().copyWith(fontSize: 20)),
              ]),
              const Spacer(),
              if (_currentHeartRate > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:
                        _getHRColor(_currentHeartRate).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _getHRColor(_currentHeartRate)
                            .withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.favorite,
                        size: 12, color: _getHRColor(_currentHeartRate)),
                    const SizedBox(width: 4),
                    Text('$_currentHeartRate',
                        style: SageText.mono(
                            size: 12,
                            weight: FontWeight.w700,
                            color: _getHRColor(_currentHeartRate))),
                  ]),
                ),
            ]),
          ),

          // Orb + ring
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Phase label — changes with each breath phase
                  AnimatedSwitcher(
                    duration: SageMotion.valueChange,
                    child: Text(
                      phase.label.toUpperCase(),
                      key: ValueKey('${_phaseIndex}_${phase.label}'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.5,
                        color: accent,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Session ring + orb
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer session-progress ring
                      SizedBox(
                        width: 260,
                        height: 260,
                        child: CustomPaint(
                          painter: _MeditationRingPainter(
                            progress: progress,
                            color: accent,
                            trackColor: SageColors.line,
                          ),
                        ),
                      ),

                      // Breathing orb — scales with animation, glow aura
                      // pulses independently for a layered living feel.
                      AnimatedBuilder(
                        animation:
                            Listenable.merge([_orbController, _glowController]),
                        builder: (context, _) {
                          // Map 0.0–1.0 to 110–185 px diameter
                          final diam = 110.0 + (_orbScale.value * 75.0);
                          return Container(
                            width: diam,
                            height: diam,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(
                                  alpha: 0.07 + _orbScale.value * 0.10),
                              border: Border.all(
                                color: accent.withValues(
                                    alpha: _glowOpacity.value * 0.75),
                                width: 2,
                              ),
                              boxShadow: [
                                // Inner warm glow — follows orb size
                                BoxShadow(
                                  color: accent.withValues(
                                      alpha: _glowOpacity.value * 0.28),
                                  blurRadius: 32 * _orbScale.value,
                                  spreadRadius: 6 * _orbScale.value,
                                ),
                                // Outer soft aura — always visible, fades
                                // slowly regardless of orb position
                                BoxShadow(
                                  color: accent.withValues(
                                      alpha: _glowOpacity.value * 0.12),
                                  blurRadius: 60,
                                  spreadRadius: 20,
                                ),
                              ],
                            ),
                            child: const SizedBox.shrink(),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Phase progress dots
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: phases.asMap().entries.map((e) {
                      final active = e.key == _phaseIndex;
                      return AnimatedContainer(
                        duration: SageMotion.valueChange,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 20 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color:
                              active ? accent : accent.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),

                  // Session progress %
                  Text(
                    '${(progress * 100).round()}% complete',
                    style: TextStyle(fontSize: 13, color: SageColors.inkSoft),
                  ),
                ],
              ),
            ),
          ),

          // Stop button — subtle, bottom of screen
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: TextButton(
              onPressed: _stopMeditation,
              child: Text(
                'Stop session',
                style: TextStyle(
                  fontSize: 14,
                  color: SageColors.inkSoft,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pose details bottom sheet
  // ─────────────────────────────────────────────────────────────────────────

  void _showDetailsSheet(Map<String, dynamic> pose, Color accent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SageColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: SageColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      Icon(pose['icon'] as IconData, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(pose['name'] as String,
                      style: SageText.headline().copyWith(fontSize: 18)),
                ),
              ]),
              const SizedBox(height: 20),
              _sheetSection('Step-by-step', Icons.format_list_numbered, accent),
              ...(pose['stepByStep'] as List<String>)
                  .asMap()
                  .entries
                  .map((e) => _numberedRow(e.key + 1, e.value, accent)),
              const SizedBox(height: 16),
              _sheetSection('Precautions', Icons.warning_amber_outlined,
                  SageColors.amber),
              ...(pose['precautions'] as List<String>).map(
                  (p) => _bulletRow(p, Icons.warning_amber, SageColors.amber)),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetSection(String title, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: SageColors.ink)),
        ]),
      );

  Widget _bulletRow(String text, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13, color: SageColors.ink, height: 1.4))),
        ]),
      );

  Widget _numberedRow(int n, String text, Color accent) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text('$n',
                style: TextStyle(
                    color: SageColors.linen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: SageColors.ink, height: 1.4)),
          )),
        ]),
      );

  Widget _infoChip(IconData icon, String label, Color accent) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, color: accent, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Ring painter
// ─────────────────────────────────────────────────────────────────────────────

// Simple value type for a chronic-reading banner — text + accent color.
class _ChronicNote {
  final String text;
  final Color color;
  const _ChronicNote(this.text, this.color);
}

class _MeditationRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  const _MeditationRingPainter(
      {required this.progress, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round);

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_MeditationRingPainter old) =>
      old.progress != progress || old.color != color;
}