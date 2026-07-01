// screens/breathwork_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/bluetooth_service.dart';
import '../services/bella_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/pressable.dart';
import 'daily_checkin_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mood model
// ─────────────────────────────────────────────────────────────────────────────

class _Mood {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<String> techniqueIds;
  const _Mood({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.techniqueIds,
  });
}

const List<_Mood> _moods = [
  _Mood(
    label: 'Stressed',
    subtitle: 'Racing mind or tense body',
    icon: Icons.bolt_rounded,
    color: Color(0xFFE2734B),
    techniqueIds: ['478', 'box', 'relaxing'],
  ),
  _Mood(
    label: 'Anxious',
    subtitle: 'Chest tight, heart fast',
    icon: Icons.favorite_border_rounded,
    color: Color(0xFFE2734B),
    techniqueIds: ['478', 'coherent', 'relaxing'],
  ),
  _Mood(
    label: 'Low energy',
    subtitle: 'Sluggish or mentally flat',
    icon: Icons.battery_2_bar_rounded,
    color: Color(0xFFEAAE49),
    techniqueIds: ['energizing', 'box'],
  ),
  _Mood(
    label: 'Unfocused',
    subtitle: 'Scattered or distracted',
    icon: Icons.center_focus_strong_rounded,
    color: Color(0xFF2E9E6B),
    techniqueIds: ['box', 'alternate', 'coherent'],
  ),
  _Mood(
    label: 'Winding down',
    subtitle: 'Preparing for sleep',
    icon: Icons.nightlight_round,
    color: Color(0xFF49B884),
    techniqueIds: ['478', 'relaxing', 'coherent'],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Technique model
// ─────────────────────────────────────────────────────────────────────────────

class BreathingTechnique {
  final String id;
  final String name;
  final String tagline;
  final String useCase;
  final List<Map<String, dynamic>> steps;
  final int totalCycles;
  final Color color;
  final IconData icon;
  final List<String> benefits;
  final String scienceNote;

  const BreathingTechnique({
    required this.id,
    required this.name,
    required this.tagline,
    required this.useCase,
    required this.steps,
    required this.totalCycles,
    required this.color,
    required this.icon,
    required this.benefits,
    required this.scienceNote,
  });

  int get totalSeconds =>
      steps.fold<int>(0, (s, e) => s + (e['duration'] as int)) * totalCycles;

  String get durationLabel {
    final mins = totalSeconds ~/ 60;
    return mins > 0 ? '~$mins min' : '${totalSeconds}s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen flow
// ─────────────────────────────────────────────────────────────────────────────

enum _BreathScreen { mood, select, session, complete }

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class BreathworkScreen extends StatefulWidget {
  final int initialHeartRate;
  final bool fromCheckin;

  /// When true, skip the mood and technique-picker screens entirely and
  /// jump straight into the technique Bella judges best for the user's
  /// current state (mood/sleep/heart-rate/conditions). Used by recommendation
  /// entry points (Chronic Care, ZZZify, Daily Check-in) so the user isn't
  /// asked to choose something they came here precisely because they didn't
  /// want to think about.
  final bool autoStart;
  const BreathworkScreen({
    super.key,
    required this.initialHeartRate,
    this.fromCheckin = false,
    this.autoStart = false,
  });

  @override
  State<BreathworkScreen> createState() => _BreathworkScreenState();
}

class _BreathworkScreenState extends State<BreathworkScreen>
    with TickerProviderStateMixin {
  // ── Services ───────────────────────────────────────────────────────────────
  final BluetoothService _bt = BluetoothService.instance;
  final BellaService _bella = BellaService();
  // Two players: one for inhale tone, one for exhale tone, so they never
  // cancel each other mid-playback.
  final AudioPlayer _inhalePlayer = AudioPlayer();
  final AudioPlayer _exhalePlayer = AudioPlayer();

  // ── Screen ─────────────────────────────────────────────────────────────────
  _BreathScreen _screen = _BreathScreen.mood;
  _Mood? _selectedMood;
  // FIX: track whether user came from "browse all" (no mood selected)
  bool _browseAllMode = false;
  BreathingTechnique? _selectedTechnique;

  // ── Session ────────────────────────────────────────────────────────────────
  Timer? _sessionTimer;
  int _totalElapsed = 0;
  int _phaseElapsed = 0;
  int _currentStepIndex = 0;
  int _cycleCount = 0;
  bool _sessionLogged = false;
  int _currentHeartRate = 0;
  int _initialHeartRate = 0;
  final List<int> _hrSamples = [];

  // ── Bella ──────────────────────────────────────────────────────────────────
  int _dailySessions = 0;
  int _targetSessions = 1;
  int _weekStreak = 0;
  String? _lastSessionLabel;

  /// True when a high-calorie meal was logged within the last 90 minutes.
  /// Breathwork relies on the diaphragm — a full stomach restricts it.
  bool _recentHeavyMeal = false;

  /// Today's flagged chronic reading note, if any — same pattern as
  /// Walking/Meditation: check the actual reading value today, not just
  /// whether the user has the condition.
  String? _readingNote;

  // ── Animations ─────────────────────────────────────────────────────────────
  late AnimationController _orbController;
  late AnimationController _glowController;
  late AnimationController _completeRingCtrl;
  late Animation<double> _orbScale;
  late Animation<double> _glowOpacity;
  late Animation<double> _completeRing;

  // ── Techniques ─────────────────────────────────────────────────────────────
  static const List<BreathingTechnique> _techniques = [
    BreathingTechnique(
      id: '478',
      name: '4-7-8',
      tagline: 'Calm the nervous system fast',
      useCase: 'Anxiety & Sleep',
      steps: [
        {
          'name': 'Inhale',
          'duration': 4,
          'instruction': 'Breathe in slowly through your nose'
        },
        {
          'name': 'Hold',
          'duration': 7,
          'instruction': 'Hold your breath gently'
        },
        {
          'name': 'Exhale',
          'duration': 8,
          'instruction': 'Exhale completely through your mouth'
        },
        {'name': 'Rest', 'duration': 4, 'instruction': 'Rest naturally'},
      ],
      totalCycles: 4,
      color: Color(0xFF49B884),
      icon: Icons.nightlight_round,
      benefits: [
        'Activates the parasympathetic nervous system',
        'Reduces pre-sleep anxiety',
        'Lowers cortisol within minutes',
        'Slows heart rate measurably',
      ],
      scienceNote:
          'The extended exhale activates the vagus nerve, directly slowing heart rate.',
    ),
    BreathingTechnique(
      id: 'box',
      name: 'Box Breathing',
      tagline: 'Regulate and refocus under pressure',
      useCase: 'Focus & Stress Control',
      steps: [
        {
          'name': 'Inhale',
          'duration': 4,
          'instruction': 'Breathe in deeply through your nose'
        },
        {'name': 'Hold', 'duration': 4, 'instruction': 'Hold at the top'},
        {
          'name': 'Exhale',
          'duration': 4,
          'instruction': 'Exhale slowly through your mouth'
        },
        {'name': 'Hold', 'duration': 4, 'instruction': 'Hold at the bottom'},
      ],
      totalCycles: 5,
      color: Color(0xFF2E9E6B),
      icon: Icons.grid_4x4_rounded,
      benefits: [
        'Creates nervous system equilibrium',
        'Improves focus without sedation',
        'Reduces acute stress response',
        'Used in high-performance training',
      ],
      scienceNote:
          'Equal-ratio breathing produces balanced autonomic regulation.',
    ),
    BreathingTechnique(
      id: 'coherent',
      name: 'Coherent',
      tagline: 'Balance heart rhythm and mood',
      useCase: 'Heart Rate Variability',
      steps: [
        {
          'name': 'Inhale',
          'duration': 5,
          'instruction': 'Breathe in gently through your nose'
        },
        {
          'name': 'Exhale',
          'duration': 5,
          'instruction': 'Exhale smoothly through your nose'
        },
      ],
      totalCycles: 6,
      color: Color(0xFFE2734B),
      icon: Icons.favorite_border_rounded,
      benefits: [
        'Maximises heart rate variability (HRV)',
        'Synchronises heart and breath rhythms',
        'Reduces cortisol and adrenaline',
        'Improves emotional regulation',
      ],
      scienceNote:
          'Six breaths per minute is the resonance frequency of the cardiovascular system.',
    ),
    BreathingTechnique(
      id: 'energizing',
      name: 'Energizing',
      tagline: 'Wake up body and mind quickly',
      useCase: 'Energy & Alertness',
      steps: [
        {
          'name': 'Inhale',
          'duration': 2,
          'instruction': 'Sharp inhale through your nose'
        },
        {
          'name': 'Exhale',
          'duration': 2,
          'instruction': 'Sharp exhale through your nose'
        },
      ],
      totalCycles: 30,
      color: Color(0xFFEAAE49),
      icon: Icons.bolt_rounded,
      benefits: [
        'Rapidly increases blood oxygen',
        'Stimulates the sympathetic nervous system',
        'Clears mental fog within 60 seconds',
        'Natural alternative to caffeine',
      ],
      scienceNote:
          'Rapid breathing temporarily raises CO2 sensitivity, producing a natural alertness spike.',
    ),
    BreathingTechnique(
      id: 'relaxing',
      name: 'Deep Relax',
      tagline: 'Release tension breath by breath',
      useCase: 'Muscle Tension & Recovery',
      steps: [
        {
          'name': 'Inhale',
          'duration': 6,
          'instruction': 'Breathe in deeply through your nose'
        },
        {'name': 'Hold', 'duration': 2, 'instruction': 'Brief pause'},
        {
          'name': 'Exhale',
          'duration': 8,
          'instruction': 'Exhale slowly through your mouth'
        },
      ],
      totalCycles: 5,
      color: Color(0xFF7FC79B),
      icon: Icons.waves_rounded,
      benefits: [
        'Releases physical muscle tension',
        'Lowers diastolic blood pressure',
        'Promotes full-body relaxation',
        'Quiets the default mode network',
      ],
      scienceNote:
          'The 6:8 inhale-to-exhale ratio extends the parasympathetic window per cycle.',
    ),
    BreathingTechnique(
      id: 'alternate',
      name: 'Alternate Nostril',
      tagline: 'Balance and clear a scattered mind',
      useCase: 'Mental Clarity',
      steps: [
        {
          'name': 'Right in',
          'duration': 4,
          'instruction': 'Close left nostril · inhale through right'
        },
        {'name': 'Hold', 'duration': 4, 'instruction': 'Hold gently'},
        {
          'name': 'Left out',
          'duration': 4,
          'instruction': 'Close right · exhale through left'
        },
        {
          'name': 'Left in',
          'duration': 4,
          'instruction': 'Inhale through left nostril'
        },
        {'name': 'Hold', 'duration': 4, 'instruction': 'Hold gently'},
        {
          'name': 'Right out',
          'duration': 4,
          'instruction': 'Close left · exhale through right'
        },
      ],
      totalCycles: 4,
      color: Color(0xFF6E756D),
      icon: Icons.sync_alt_rounded,
      benefits: [
        'Balances left and right hemispheres',
        'Reduces mental chatter rapidly',
        'Improves sustained attention',
        'Ancient pranayama with modern evidence',
      ],
      scienceNote:
          'Alternating airflow influences contralateral brain hemisphere activity via olfactory neurons.',
    ),
  ];

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _currentHeartRate = widget.initialHeartRate;
    _initialHeartRate = widget.initialHeartRate;
    _hrSamples.add(widget.initialHeartRate);

    _targetSessions = _bella.getTarget<int>('breathworkSessions') ?? 1;
    _dailySessions = _bella.sessionsToday('breathwork');
    _loadBellaContext();

    _bt.dataStream.listen((data) {
      if (mounted) setState(() => _currentHeartRate = data.heartRate);
    });

    _orbController =
        AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _orbScale = Tween<double>(begin: 0.55, end: 1.0).animate(
        CurvedAnimation(parent: _orbController, curve: Curves.easeInOut));

    _glowController =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..repeat(reverse: true);
    _glowOpacity = Tween<double>(begin: 0.2, end: 0.85).animate(
        CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));

    _completeRingCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _completeRing =
        Tween<double>(begin: 0.0, end: 0.0).animate(_completeRingCtrl);

    _autoSelectMood();

    if (widget.autoStart) {
      // Fall back to a sensible neutral mood if none of the heuristics in
      // _autoSelectMood matched (e.g. no check-in/sleep data yet), so we
      // always have a mood to pick a "best" technique from.
      _selectedMood ??= _moods[3]; // Unfocused — box breathing, broadly safe
      final best = _techniquesForMood(_selectedMood!).first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _beginSession(best);
      });
    }

    // Configure audio players to not steal focus from sleep sounds
    _inhalePlayer.setAudioContext(AudioContext(
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
    _exhalePlayer.setAudioContext(AudioContext(
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
    final sessions = _bella.getSessions(type: 'breathwork');
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
    final days = _bella
        .getSessions(type: 'breathwork')
        .where((s) => now.difference(s.date).inDays < 7)
        .map((s) => '${s.date.year}-${s.date.month}-${s.date.day}')
        .toSet();
    _weekStreak = days.length;

    // Food timing — a heavy meal restricts the diaphragm, reducing the
    // effectiveness of belly breathing and making techniques uncomfortable.
    final recentFood = _bella.getFoodEntries(onDate: now).where((f) {
      final age = now.difference(f.time).inMinutes;
      return age <= 90 && (f.calories ?? 0) >= 500;
    }).toList();
    _recentHeavyMeal = recentFood.isNotEmpty;

    // Chronic readings — checks today's actual reading value, same pattern
    // Walking already uses, instead of only knowing the condition exists.
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];
    if (conditions.contains('Hypertension') ||
        conditions.contains('Heart Disease')) {
      final cond = conditions.contains('Hypertension')
          ? 'Hypertension'
          : 'Heart Disease';
      final readings = _bella.getReadings(condition: cond);
      if (readings.isNotEmpty) {
        final r = readings.first;
        final isToday = now.difference(r.time).inHours <= 12;
        if (isToday && (r.value >= 140 || (r.secondaryValue ?? 0) >= 90)) {
          _readingNote =
              'BP is elevated today — box breathing and 4-7-8 are your best options. Skip energizing techniques.';
        }
      }
    }
    if (_readingNote == null && conditions.contains('Asthma')) {
      final readings = _bella.getReadings(condition: 'Asthma');
      if (readings.isNotEmpty) {
        final r = readings.first;
        final isToday = now.difference(r.time).inHours <= 12;
        if (isToday && r.value < 300) {
          _readingNote =
              'Peak flow is low today — avoid breath-holds and stick to gentle, steady techniques.';
        }
      }
    }
  }

  void _autoSelectMood() {
    final checkin = _bella.lastCheckin;
    final lastSleep = _bella.lastNightSleep;
    final hr = _currentHeartRate;
    final hour = DateTime.now().hour;

    // Poor sleep quality pushes toward wind-down (4-7-8, relaxing) even
    // during the day — the body needs parasympathetic recovery.
    final poorSleep = lastSleep != null && lastSleep.quality <= 2;

    if (hr > 100 || (checkin != null && checkin.stress >= 4)) {
      setState(() => _selectedMood = _moods[0]); // Stressed
    } else if (checkin != null && checkin.mood <= 2) {
      setState(() => _selectedMood = _moods[1]); // Anxious
    } else if (poorSleep && hour < 20) {
      // Poor sleep + not evening → winding-down restorative techniques
      setState(() => _selectedMood = _moods[4]); // Winding down
    } else if (checkin != null && checkin.energy <= 2 && !poorSleep) {
      // Low energy without poor sleep → energising techniques
      setState(() => _selectedMood = _moods[2]); // Low energy
    } else if (hour >= 20 || poorSleep) {
      setState(() => _selectedMood = _moods[4]); // Winding down
    }
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _orbController.dispose();
    _glowController.dispose();
    _completeRingCtrl.dispose();
    _inhalePlayer.dispose();
    _exhalePlayer.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Technique list helpers
  // ─────────────────────────────────────────────────────────────────────────

  List<BreathingTechnique> _techniquesForMood(_Mood mood) {
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];
    final hasHeartIssue = conditions.contains('Hypertension') ||
        conditions.contains('Heart Disease');
    final hasAsthma = conditions.contains('Asthma');
    // Today's peak flow is flagged → avoid breath-holds specifically,
    // not just deprioritize "Energizing".
    final asthmaFlaggedToday =
        hasAsthma && (_readingNote?.contains('Peak flow') ?? false);

    final preferred = mood.techniqueIds
        .map((id) => _techniques.firstWhere((t) => t.id == id))
        .toList();
    final rest =
        _techniques.where((t) => !mood.techniqueIds.contains(t.id)).toList();
    final ordered = [...preferred, ...rest];

    if (hasHeartIssue || hasAsthma) {
      final energizing = ordered.firstWhere((t) => t.id == 'energizing');
      ordered.remove(energizing);
      ordered.add(energizing);
    }

    if (asthmaFlaggedToday) {
      // Hold-heavy techniques (4-7-8, box) move behind hold-free ones
      // (coherent, relaxing) when peak flow is low today.
      const holdHeavyIds = {'478', 'box'};
      ordered.sort((a, b) {
        final aHold = holdHeavyIds.contains(a.id) ? 1 : 0;
        final bHold = holdHeavyIds.contains(b.id) ? 1 : 0;
        return aHold.compareTo(bHold);
      });
    }
    return ordered;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session control
  // ─────────────────────────────────────────────────────────────────────────

  void _beginSession(BreathingTechnique technique) {
    setState(() {
      _selectedTechnique = technique;
      _totalElapsed = 0;
      _phaseElapsed = 0;
      _currentStepIndex = 0;
      _cycleCount = 0;
      _sessionLogged = false;
      _screen = _BreathScreen.session;
    });
    _orbController.value = 0;
    _animatePhase(technique.steps[0]);
    _playTone(technique.steps[0]['name'] as String);

    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _totalElapsed++;
        _phaseElapsed++;
        if (_totalElapsed % 30 == 0) _hrSamples.add(_currentHeartRate);

        final step = _selectedTechnique!.steps[_currentStepIndex];
        if (_phaseElapsed >= (step['duration'] as int)) {
          _phaseElapsed = 0;
          _currentStepIndex++;
          if (_currentStepIndex >= _selectedTechnique!.steps.length) {
            _currentStepIndex = 0;
            _cycleCount++;
            if (_cycleCount >= _selectedTechnique!.totalCycles) {
              _completeSession();
              return;
            }
          }
          final nextStep = _selectedTechnique!.steps[_currentStepIndex];
          _animatePhase(nextStep);
          _haptic(nextStep['name'] as String);
          _playTone(nextStep['name'] as String);
        }
      });
    });
  }

  void _animatePhase(Map<String, dynamic> step) {
    final name = (step['name'] as String).toLowerCase();
    final dur = step['duration'] as int;
    _orbController.stop();
    _orbController.duration = Duration(seconds: dur);
    if (name.contains('in')) {
      _orbController.forward(from: 0);
    } else if (name.contains('out') || name == 'exhale') {
      _orbController.reverse(from: 1);
    }
    // hold / rest: stays at current value
  }

  void _haptic(String phaseName) {
    final lower = phaseName.toLowerCase();
    if (lower.contains('in')) {
      HapticFeedback.mediumImpact();
    } else if (lower.contains('out') || lower == 'exhale') {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  // FIX: sounds now actually work — separate AudioPlayer per tone so
  // they never cancel each other, and we catch errors silently.
  Future<void> _playTone(String phaseName) async {
    final lower = phaseName.toLowerCase();
    try {
      if (lower.contains('in')) {
        await _inhalePlayer.stop();
        await _inhalePlayer.play(AssetSource('audio/bell_high.mp3'),
            volume: 0.5);
      } else if (lower.contains('out') || lower == 'exhale') {
        await _exhalePlayer.stop();
        await _exhalePlayer.play(AssetSource('audio/bell_low.mp3'),
            volume: 0.4);
      }
    } catch (_) {
      // Asset missing — degrade silently, haptics still fire
    }
  }

  void _stopSession() {
    _sessionTimer?.cancel();
    _orbController.stop();
    if (_totalElapsed >= 30 && !_sessionLogged) {
      _bella.logSession('breathwork', _totalElapsed ~/ 60,
          detail: _selectedTechnique?.name);
      _sessionLogged = true;
    }
    // FIX: go back to select, not mood, so the user doesn't lose their
    // technique list after stopping mid-session.
    setState(() => _screen = _BreathScreen.select);
  }

  void _completeSession() {
    _sessionTimer?.cancel();
    _orbController.stop();
    if (!_sessionLogged) {
      _bella.logSession('breathwork', _totalElapsed ~/ 60,
          detail: _selectedTechnique?.name);
      _sessionLogged = true;
    }
    final score = _calmScore();
    _completeRing = Tween<double>(begin: 0.0, end: score).animate(
        CurvedAnimation(parent: _completeRingCtrl, curve: Curves.easeOut));
    _completeRingCtrl.forward(from: 0);
    setState(() => _screen = _BreathScreen.complete);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  double _calmScore() {
    final change = _initialHeartRate - _currentHeartRate;
    if (_initialHeartRate == 0) return 0.5;
    if (change > 12) return 1.0;
    if (change > 7) return 0.82;
    if (change > 3) return 0.65;
    if (change >= 0) return 0.5;
    return 0.35;
  }

  String _calmLabel(double score) {
    if (score >= 0.9) return 'Excellent calm';
    if (score >= 0.75) return 'Good progress';
    if (score >= 0.55) return 'Steady breath';
    return 'Keep practising';
  }

  String _calmInsight() {
    final change = _initialHeartRate - _currentHeartRate;
    if (change > 10)
      return 'Heart rate dropped $change bpm — your nervous system responded well.';
    if (change > 4)
      return 'A $change bpm reduction shows your body is learning to regulate.';
    if (change >= 0)
      return 'Your heart rate held steady. Consistency builds the response over time.';
    return 'Heart rate rose slightly — try a longer exhale in your next session.';
  }

  bool _hasHeartWarning(BreathingTechnique t) {
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];
    return t.id == 'energizing' &&
        (conditions.contains('Hypertension') ||
            conditions.contains('Heart Disease'));
  }

  Map<String, dynamic> get _currentStep =>
      _selectedTechnique?.steps[_currentStepIndex] ??
      {'name': '...', 'duration': 0, 'instruction': ''};

  int get _phaseRemaining => (_currentStep['duration'] as int) - _phaseElapsed;

  double get _sessionProgress {
    final total = _selectedTechnique?.totalSeconds ?? 1;
    return (_totalElapsed / total).clamp(0.0, 1.0);
  }

  Color get _phaseColor {
    final name = (_currentStep['name'] as String).toLowerCase();
    final base = _selectedTechnique?.color ?? SageColors.moss;
    if (name.contains('in')) return base;
    if (name.contains('out') || name == 'exhale')
      return base.withValues(alpha: 0.55);
    return SageColors.inkSoft;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build router
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: SageMotion.revealSmall,
      switchInCurve: SageMotion.revealCurve,
      switchOutCurve: Curves.easeIn,
      child: switch (_screen) {
        _BreathScreen.mood =>
          KeyedSubtree(key: const ValueKey('mood'), child: _buildMoodScreen()),
        _BreathScreen.select => KeyedSubtree(
            key: const ValueKey('select'), child: _buildSelectScreen()),
        _BreathScreen.session => KeyedSubtree(
            key: const ValueKey('session'), child: _buildSessionScreen()),
        _BreathScreen.complete => KeyedSubtree(
            key: const ValueKey('complete'), child: _buildCompleteScreen()),
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SCREEN 1 — Mood gate
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildMoodScreen() {
    // FIX: WillPopScope so the user can exit the screen entirely
    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: SageColors.linen,
        // FIX: AppBar with a real back button so the user can always leave
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: SageColors.ink),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Breathwork', style: SageText.headline()),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How are you feeling right now?',
                style: TextStyle(
                    fontSize: 16, color: SageColors.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 20),

              // Chronic reading note — surfaces today's flagged BP or peak
              // flow reading so the user sees it before picking a technique.
              if (_readingNote != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: SageColors.clay.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: SageColors.clay.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    Icon(Icons.favorite_border_rounded,
                        size: 15, color: SageColors.clay),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _readingNote!,
                        style: TextStyle(
                            fontSize: 12, color: SageColors.clay, height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ],

              // Food timing note — a heavy meal within 90 min restricts the
              // diaphragm, reducing the effectiveness of belly breathing.
              if (_recentHeavyMeal) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: SageColors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: SageColors.amber.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    Icon(Icons.restaurant_outlined,
                        size: 15, color: SageColors.amber),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Heavy meal recently — your diaphragm works better '
                        'on a lighter stomach. Waiting 30 min improves the depth of belly breathing.',
                        style: TextStyle(
                            fontSize: 12, color: SageColors.amber, height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ],

              // Mood grid — wrapped in Expanded to prevent overflow
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  physics: const NeverScrollableScrollPhysics(),
                  children: _moods.map((mood) {
                    final selected = _selectedMood?.label == mood.label;
                    return Pressable(
                      onTap: () => setState(() => _selectedMood = mood),
                      child: AnimatedContainer(
                        duration: SageMotion.valueChange,
                        decoration: BoxDecoration(
                          color: selected
                              ? mood.color.withValues(alpha: 0.12)
                              : SageColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? mood.color : SageColors.line,
                            width: selected ? 1.5 : 1.0,
                          ),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: mood.color
                                    .withValues(alpha: selected ? 0.2 : 0.1),
                                shape: BoxShape.circle,
                              ),
                              child:
                                  Icon(mood.icon, color: mood.color, size: 16),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(mood.label,
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? mood.color
                                            : SageColors.ink)),
                                const SizedBox(height: 2),
                                Text(mood.subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        color: SageColors.inkSoft,
                                        height: 1.3)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // Primary CTA
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _selectedMood == null
                      ? null
                      : () {
                          setState(() {
                            _browseAllMode = false;
                            _screen = _BreathScreen.select;
                          });
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedMood?.color ?? SageColors.moss,
                    disabledBackgroundColor: SageColors.line,
                    foregroundColor: SageColors.linen,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(
                    _selectedMood == null
                        ? 'Choose how you feel'
                        : 'Find me a technique',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // FIX: "Browse all techniques" goes to select screen WITHOUT
              // a mood, so no "Best match" card appears — just the full list.
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => setState(() {
                    _browseAllMode = true;
                    _screen = _BreathScreen.select;
                  }),
                  child: Text('Browse all techniques',
                      style:
                          TextStyle(fontSize: 13, color: SageColors.inkSoft)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SCREEN 2 — Technique selection
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildSelectScreen() {
    // FIX: when browseAllMode = true, show all techniques flat with no
    // "Best match" card. When a mood is selected, show quick-start + rest.
    final mood = _browseAllMode ? null : _selectedMood;
    final list = mood != null
        ? _techniquesForMood(mood)
        : List<BreathingTechnique>.from(_techniques);

    return WillPopScope(
      onWillPop: () async {
        setState(() => _screen = _BreathScreen.mood);
        return false;
      },
      child: Scaffold(
        backgroundColor: SageColors.linen,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: SageColors.ink),
            onPressed: () => setState(() => _screen = _BreathScreen.mood),
          ),
          title: Text(
            _browseAllMode ? 'All Techniques' : 'Breathwork',
            style: SageText.headline(),
          ),
          actions: [
            if (_currentHeartRate > 0) _hrChip(_currentHeartRate),
            const SizedBox(width: 16),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Streak row
              if (_weekStreak > 0 || _dailySessions > 0) ...[
                _buildStreakRow(),
                const SizedBox(height: 16),
              ],

              // Mood context label — only when a mood was selected
              if (mood != null) ...[
                Row(children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: mood.color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(mood.icon, size: 12, color: mood.color),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'For "${mood.label}" — ranked for you',
                    style: TextStyle(
                        fontSize: 13,
                        color: SageColors.inkSoft,
                        fontWeight: FontWeight.w500),
                  ),
                ]),
                const SizedBox(height: 14),

                // Quick-start card only when mood chosen
                _buildQuickStartCard(list.first, mood),
                const SizedBox(height: 20),

                Text('ALL TECHNIQUES',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                        color: SageColors.inkSoft)),
                const SizedBox(height: 10),

                // Skip the recommended one since it's already in the card
                ...list.skip(1).map((t) => _buildTechniqueRow(t)),
              ] else ...[
                // Browse-all mode: plain list, no quick-start, no mood label
                ...list.map((t) => _buildTechniqueRow(t)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreakRow() {
    return Row(children: [
      if (_weekStreak > 0)
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: SageColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SageColors.line),
            ),
            child: Row(children: [
              Icon(Icons.local_fire_department_rounded,
                  color: SageColors.clay, size: 18),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_weekStreak day${_weekStreak == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: SageColors.clay)),
                Text('this week',
                    style:
                        TextStyle(fontSize: 10.5, color: SageColors.inkSoft)),
              ]),
            ]),
          ),
        ),
      if (_weekStreak > 0 && _dailySessions > 0) const SizedBox(width: 10),
      if (_dailySessions > 0)
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: SageColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SageColors.line),
            ),
            child: Row(children: [
              Icon(Icons.air, color: SageColors.moss, size: 18),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_dailySessions / $_targetSessions',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: SageColors.moss)),
                Text('sessions today',
                    style:
                        TextStyle(fontSize: 10.5, color: SageColors.inkSoft)),
              ]),
            ]),
          ),
        ),
    ]);
  }

  Widget _buildQuickStartCard(BreathingTechnique t, _Mood mood) {
    return Container(
      decoration: BoxDecoration(
        color: t.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.color.withValues(alpha: 0.35), width: 1.5),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: t.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(t.icon, color: t.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(t.name,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: SageColors.ink)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: t.color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 9, color: Colors.white),
                        const SizedBox(width: 3),
                        Text('Best match',
                            style: const TextStyle(
                                fontSize: 9.5,
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(t.tagline,
                      style:
                          TextStyle(fontSize: 12.5, color: SageColors.inkSoft)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),

          // Step preview chips — scrollable to avoid overflow
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: t.steps.map((step) {
                return Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: SageColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: t.color.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    '${step['name']} ${step['duration']}s',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: t.color,
                        fontWeight: FontWeight.w600),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),

          // Science note
          Row(children: [
            Icon(Icons.science_outlined, size: 12, color: SageColors.inkSoft),
            const SizedBox(width: 6),
            Expanded(
              child: Text(t.scienceNote,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: SageColors.inkSoft,
                      height: 1.4,
                      fontStyle: FontStyle.italic)),
            ),
          ]),
          const SizedBox(height: 14),

          // Footer row
          Row(children: [
            _infoChip(Icons.timer_outlined, t.durationLabel, t.color),
            const SizedBox(width: 8),
            _infoChip(
                Icons.repeat_rounded,
                '${t.totalCycles} cycle${t.totalCycles == 1 ? '' : 's'}',
                t.color),
            const Spacer(),
            if (_hasHeartWarning(t))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.warning_amber_rounded,
                    color: SageColors.amber, size: 18),
              ),
            Pressable(
              onTap: () => _beginSession(t),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: t.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text('Begin now',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildTechniqueRow(BreathingTechnique t) {
    return Pressable(
      onTap: () => _beginSession(t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SageColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SageColors.line),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(t.icon, color: t.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: SageColors.ink)),
                const SizedBox(height: 2),
                Text(t.tagline,
                    style: TextStyle(fontSize: 12, color: SageColors.inkSoft)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _infoChip(Icons.timer_outlined, t.durationLabel, t.color),
                  _infoChip(Icons.loop_rounded, t.useCase, t.color),
                  if (_hasHeartWarning(t))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: SageColors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: SageColors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 10, color: SageColors.amber),
                        const SizedBox(width: 3),
                        Text('Check with doctor',
                            style: TextStyle(
                                fontSize: 9.5,
                                color: SageColors.amber,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                ]),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: SageColors.inkSoft, size: 20),
        ]),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SCREEN 3 — Active session
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildSessionScreen() {
    final t = _selectedTechnique!;
    final step = _currentStep;
    final phaseName = step['name'] as String;
    final instruction = step['instruction'] as String;
    final orbMax =
        (MediaQuery.of(context).size.width * 0.65).clamp(160.0, 260.0);

    // FIX: WillPopScope lets hardware back button stop the session and
    // return to the select screen — so the user is never trapped.
    return WillPopScope(
      onWillPop: () async {
        _stopSession();
        return false;
      },
      child: Scaffold(
        backgroundColor: SageColors.linen,
        body: SafeArea(
          child: Column(
            children: [
              // Status row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(children: [
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: SageColors.inkSoft)),
                        Text('Cycle ${_cycleCount + 1} of ${t.totalCycles}',
                            style: TextStyle(
                                fontSize: 11.5, color: SageColors.inkSoft)),
                      ]),
                  const Spacer(),
                  if (_currentHeartRate > 0) _hrChip(_currentHeartRate),
                ]),
              ),

              // Progress bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _sessionProgress,
                    backgroundColor: SageColors.line,
                    color: t.color,
                    minHeight: 3,
                  ),
                ),
              ),

              // Orb area
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Phase label
                      AnimatedSwitcher(
                        duration: SageMotion.valueChange,
                        child: Text(
                          phaseName.toUpperCase(),
                          key: ValueKey(phaseName),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                            color: _phaseColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Orb
                      AnimatedBuilder(
                        animation:
                            Listenable.merge([_orbController, _glowController]),
                        builder: (context, _) {
                          final d = (orbMax * 0.55) +
                              (_orbScale.value * orbMax * 0.45);
                          return Container(
                            width: d,
                            height: d,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: t.color.withValues(
                                  alpha: 0.08 + _orbScale.value * 0.09),
                              border: Border.all(
                                color: t.color.withValues(
                                    alpha: _glowOpacity.value * 0.7),
                                width: 2.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: t.color.withValues(
                                      alpha: _glowOpacity.value * 0.22),
                                  blurRadius: 40 * _orbScale.value,
                                  spreadRadius: 8 * _orbScale.value,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$_phaseRemaining',
                                    style: SageText.mono(
                                      size: orbMax * 0.18,
                                      weight: FontWeight.w700,
                                      color: t.color,
                                    ),
                                  ),
                                  Text('sec',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              t.color.withValues(alpha: 0.6))),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // Instruction
                      AnimatedSwitcher(
                        duration: SageMotion.valueChange,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Text(
                            instruction,
                            key: ValueKey(instruction),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 15,
                                color: SageColors.inkSoft,
                                height: 1.5),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Phase dots
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: t.steps.asMap().entries.map((e) {
                          final active = e.key == _currentStepIndex;
                          return AnimatedContainer(
                            duration: SageMotion.valueChange,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? t.color
                                  : t.color.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              // Stop button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: TextButton(
                  onPressed: _stopSession,
                  child: Text('Stop session',
                      style: TextStyle(
                          fontSize: 13.5,
                          color: SageColors.inkSoft.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SCREEN 4 — Completion
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildCompleteScreen() {
    final t = _selectedTechnique!;
    final score = _calmScore();
    final label = _calmLabel(score);
    final change = _initialHeartRate - _currentHeartRate;
    final mins = _totalElapsed ~/ 60;
    final secs = _totalElapsed % 60;

    // FIX: WillPopScope on complete screen goes back to mood (start fresh)
    return WillPopScope(
      onWillPop: () async {
        setState(() => _screen = _BreathScreen.mood);
        return false;
      },
      child: Scaffold(
        backgroundColor: SageColors.linen,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(t.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SageColors.inkSoft,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text('Session complete',
                    style: SageText.headline().copyWith(fontSize: 26)),
                const SizedBox(height: 28),

                // Animated score ring
                AnimatedBuilder(
                  animation: _completeRingCtrl,
                  builder: (context, _) => SizedBox(
                    width: 190,
                    height: 190,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(190, 190),
                          painter: _SessionRingPainter(
                            progress: _completeRing.value,
                            color: t.color,
                            trackColor: SageColors.line,
                            strokeWidth: 8,
                          ),
                        ),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            '${(_completeRing.value * 100).round()}',
                            style: SageText.mono(
                                size: 44,
                                weight: FontWeight.w700,
                                color: t.color),
                          ),
                          Text('calm score',
                              style: TextStyle(
                                  fontSize: 12, color: SageColors.inkSoft)),
                          const SizedBox(height: 2),
                          Text(label,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: t.color)),
                        ]),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Stat cards
                Row(children: [
                  _statCard(
                      Icons.timer_outlined,
                      mins > 0 ? '${mins}m ${secs}s' : '${secs}s',
                      'Duration',
                      t.color),
                  const SizedBox(width: 10),
                  _statCard(
                      Icons.repeat_rounded, '$_cycleCount', 'Cycles', t.color),
                  const SizedBox(width: 10),
                  _statCard(
                    Icons.favorite_border_rounded,
                    change >= 0 ? '−$change' : '+${change.abs()}',
                    'BPM change',
                    change >= 0 ? SageColors.moss : SageColors.clay,
                  ),
                ]),

                const SizedBox(height: 18),

                // Insight
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: t.color.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.color.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.insights_rounded, color: t.color, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_calmInsight(),
                              style: TextStyle(
                                  fontSize: 13.5,
                                  color: SageColors.ink,
                                  height: 1.5)),
                        ),
                      ]),
                ),

                const SizedBox(height: 24),

                Text('How do you feel now?',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: SageColors.ink)),
                const SizedBox(height: 12),

                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          setState(() => _screen = _BreathScreen.mood),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SageColors.inkSoft,
                        side: BorderSide(color: SageColors.line),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Breathe again'),
                    ),
                  ),
                  if (!widget.fromCheckin && !_bella.hasCheckedInToday()) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const DailyCheckinScreen())),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.color,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Log check-in',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shared widgets
  // ─────────────────────────────────────────────────────────────────────────

  Widget _hrChip(int hr) {
    final color = hr > 100
        ? SageColors.clay
        : hr > 80
            ? SageColors.amber
            : SageColors.moss;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.favorite, size: 11, color: color),
        const SizedBox(width: 4),
        Text('$hr',
            style:
                SageText.mono(size: 12, weight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _statCard(IconData icon, String value, String label, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: SageColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SageColors.line),
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 6),
            Text(value,
                style: SageText.mono(
                    size: 18, weight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 10.5, color: SageColors.inkSoft)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Ring painter
// ─────────────────────────────────────────────────────────────────────────────

class _SessionRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  const _SessionRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    this.strokeWidth = 6.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
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
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SessionRingPainter old) =>
      old.progress != progress || old.color != color;
}