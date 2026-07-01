// screens/sleep_sounds_screen.dart
//
// Redesigned Sleep Sounds screen.
//
// What's new vs the original:
//   • Horizontal sound picker — large icon cards with accent fills, replacing the
//     awkward 2-col grid. Tap to select, tap again to deselect. No play/pause
//     confusion with the card itself.
//   • Sound Mixer — up to 2 sounds can play simultaneously with independent
//     volume sliders. Layering Rain + White Noise, for example.
//   • Sleep Timer — 15 / 30 / 45 / 60 / ∞ options shown as pill chips above
//     the now-playing panel. Countdown visible while active.
//   • Now-Playing panel redesigned: larger art circle (accent color), track name,
//     timer countdown, seek bar, and standard transport controls all in one
//     cohesive card that slides up when a sound is selected.
//   • Recommendation banner replaced with an inline "For you" badge on the sound
//     card plus a small explanatory chip at the top — less visual noise.
//   • Tips card kept but condensed to 3 contextual bullets, not 6+.
//   • embedded=true still works (no Scaffold/AppBar).
//
// Dependencies: audioplayers (already in pubspec), everything else from app.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/bella_service.dart';
import '../services/user_service.dart';
import '../services/sleep_sounds_player_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/reveal.dart';
import '../widgets/pressable.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data
// ─────────────────────────────────────────────────────────────────────────────

class _Sound {
  final String name;
  final String description;
  final IconData icon;
  final Color accent;
  final String asset;

  const _Sound({
    required this.name,
    required this.description,
    required this.icon,
    required this.accent,
    required this.asset,
  });
}

// Timer option — null minutes = play indefinitely.
class _TimerOption {
  final String label;
  final int? minutes;
  const _TimerOption(this.label, this.minutes);
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class SleepSoundsScreen extends StatefulWidget {
  final bool embedded;
  const SleepSoundsScreen({super.key, this.embedded = false});

  @override
  State<SleepSoundsScreen> createState() => _SleepSoundsScreenState();
}

class _SleepSoundsScreenState extends State<SleepSoundsScreen>
    with TickerProviderStateMixin {
  // ── Services ───────────────────────────────────────────────────────────────
  final BellaService _bella = BellaService();

  // ── Sound catalogue ────────────────────────────────────────────────────────
  static const List<_Sound> _sounds = [
    _Sound(
        name: 'Rainfall',
        description: 'Gentle rain',
        icon: Icons.water_drop,
        accent: Color(0xFF49B884),
        asset: 'audio/rain.mp3'),
    _Sound(
        name: 'Ocean Waves',
        description: 'Open water',
        icon: Icons.waves,
        accent: Color(0xFF2E9E6B),
        asset: 'audio/waves.mp3'),
    _Sound(
        name: 'Forest Night',
        description: 'Crickets & wind',
        icon: Icons.forest,
        accent: Color(0xFF55C28C),
        asset: 'audio/ghaba.mp3'),
    _Sound(
        name: 'White Noise',
        description: 'Block distractions',
        icon: Icons.blur_on,
        accent: Color(0xFF6E756D),
        asset: 'audio/whitenoise.mp3'),
    _Sound(
        name: 'Piano',
        description: 'Soft melodies',
        icon: Icons.music_note,
        accent: Color(0xFFE2734B),
        asset: 'audio/piano.mp3'),
    _Sound(
        name: 'Tibetan Bowl',
        description: 'Healing tones',
        icon: Icons.self_improvement,
        accent: Color(0xFFEAAE49),
        asset: 'audio/tibetbowls.mp3'),
  ];

  // ── Timer options ──────────────────────────────────────────────────────────
  static const List<_TimerOption> _timerOptions = [
    _TimerOption('15 min', 15),
    _TimerOption('30 min', 30),
    _TimerOption('45 min', 45),
    _TimerOption('60 min', 60),
    _TimerOption('Always on', null),
  ];

  // ── Player service ───────────────────────────────────────────────────────
  // Playback, the mixer slots, and the sleep timer all now live in this
  // app-wide singleton instead of on this State — see
  // sleep_sounds_player_service.dart for why. Everything below is a thin
  // getter/wrapper over it so the rest of this file (build methods etc.)
  // didn't need to change.
  final SleepSoundsPlayerService _svc = SleepSoundsPlayerService();

  _TimerOption get _selectedTimer => _timerOptions.firstWhere(
        (o) => o.minutes == _svc.selectedTimerMinutes,
        orElse: () => _timerOptions[1],
      );
  int get _timerSecondsLeft => _svc.timerSecondsLeft;

  // ── Mixer state — max 2 simultaneous sounds ────────────────────────────────
  // slot 0 = primary, slot 1 = secondary (optional)
  List<String?> get _slotSound => _svc.slotSound; // sound name in each slot
  List<double> get _slotVolume => _svc.slotVolume; // 0.0–1.0
  List<bool> get _slotPlaying => _svc.slotPlaying;
  List<DateTime?>? get _slotStart => _svc.slotStart;

  // Convenience: which sounds are currently active in any slot.
  bool _isActive(String name) => _svc.isActive(name);
  bool _isPlaying(String name) => _svc.isPlaying(name);
  int _slotOf(String name) => _svc.slotOf(name);

  // ── Recommendation ─────────────────────────────────────────────────────────
  String? _recommendedSound;
  String? _recommendReason;

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _isDisposed = false;

  // ── Session tracking (for Bella logging) ─────────────────────────────────
  // Records when playback first starts so elapsed minutes can be computed
  // when the user stops. Only set while something is playing.
  DateTime? _sessionStartedAt;

  /// When true, sounds keep playing if the screen turns off, the user
  /// switches to another feature (or screen) in the app, or backgrounds the
  /// app entirely — instead of auto-pausing. Persisted per-user via Bella.
  bool get _playInBackground => _svc.playInBackground;

  // Animation for the now-playing panel slide-in.
  late AnimationController _panelController;
  late Animation<Offset> _panelSlide;

  // ── Pulse animation for active icon ───────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulse;

  // ── Scroll ─────────────────────────────────────────────────────────────────
  final ScrollController _scrollCtrl = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────
  // Init / dispose
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _svc.init();
    _svc.addListener(_onServiceChanged);

    _panelController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _panelSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _panelController, curve: Curves.easeOut));

    // If sounds are already playing — e.g. the user left this screen
    // earlier with "Play in background" on, then came back — open the
    // now-playing panel immediately rather than animating in.
    if (_svc.anyActive) _panelController.value = 1.0;

    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.12).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _computeRecommendation();
  }

  /// Called whenever playback/mixer/timer state changes in the singleton —
  /// keeps this screen's UI in sync, keeps the now-playing panel's slide
  /// animation in sync, and tracks session start/end for Bella logging.
  void _onServiceChanged() {
    if (_isDisposed || !mounted) return;

    // Session tracking: stamp start time when playback first becomes active;
    // log to Bella when playback transitions from active → fully stopped.
    if (_svc.anyPlaying) {
      _sessionStartedAt ??= DateTime.now();
    } else if (!_svc.anyActive && _sessionStartedAt != null) {
      _logSleepSoundsSession();
    }

    setState(() {});
    if (_svc.anyActive) {
      if (_panelController.status != AnimationStatus.forward &&
          _panelController.status != AnimationStatus.completed) {
        _panelController.forward();
      }
    } else {
      if (_panelController.status != AnimationStatus.reverse &&
          _panelController.status != AnimationStatus.dismissed) {
        _panelController.reverse();
      }
    }
  }

  /// Logs the completed sleep-sounds session to Bella so it shows up in
  /// Insights, achievements, and the wellness score. Only logs sessions
  /// of at least 1 minute to avoid phantom entries from quick taps.
  void _logSleepSoundsSession() {
    final started = _sessionStartedAt;
    _sessionStartedAt = null;
    if (started == null) return;
    final minutes = DateTime.now().difference(started).inMinutes;
    if (minutes < 1) return;
    _bella.logSession('sleep_sounds', minutes);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _svc.removeListener(_onServiceChanged);
    _panelController.dispose();
    _pulseController.dispose();
    _scrollCtrl.dispose();
    // "Play in background" governs leaving this screen too, not just OS
    // backgrounding — if it's off, leaving (even just to do a check-in)
    // stops playback, matching the original behaviour. If it's on, the
    // singleton keeps the players running after this State is gone.
    if (!_svc.playInBackground) {
      _logSleepSoundsSession(); // log elapsed time before stopping
      _svc.stopAllAndClose();
    }
    super.dispose();
  }

  /// Toggle the "play in background" preference and persist it. Also
  /// governs whether playback survives navigating away from this screen —
  /// see dispose() above.
  Future<void> _setPlayInBackground(bool value) =>
      _svc.setPlayInBackground(value);

  // ─────────────────────────────────────────────────────────────────────────
  // Audio helpers — thin wrappers over SleepSoundsPlayerService.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _selectSound(String name) async {
    final sound = _sounds.firstWhere((s) => s.name == name);
    await _svc.selectSound(name, sound.asset);
  }

  Future<void> _removeSound(String name) => _svc.removeSound(name);

  Future<void> _toggleSlotPlayPause(int slot) => _svc.toggleSlotPlayPause(slot);

  Future<void> _setSlotVolume(int slot, double v) =>
      _svc.setSlotVolume(slot, v);

  bool get _anyPlaying => _svc.anyPlaying;
  bool get _anyActive => _svc.anyActive;

  // ─────────────────────────────────────────────────────────────────────────
  // Sleep timer — thin wrappers over SleepSoundsPlayerService.
  // ─────────────────────────────────────────────────────────────────────────

  void _stopTimer() => _svc.stopTimer();

  Future<void> _stopAllAndClose() => _svc.stopAllAndClose();

  String _fmtTimer(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _selectTimer(_TimerOption option) =>
      _svc.setSelectedTimerMinutes(option.minutes);

  // ─────────────────────────────────────────────────────────────────────────
  // Recommendation
  // ─────────────────────────────────────────────────────────────────────────

  void _computeRecommendation() {
    final checkin = _bella.lastCheckin;
    final lastSleep = _bella.lastNightSleep;
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];
    final hour = DateTime.now().hour;

    // If the user already did breathwork or meditation tonight, they're
    // already in a parasympathetic state — favour gentle, immersive sounds
    // that extend that calm rather than stimulating ones.
    final breathworkToday = _bella.sessionsToday('breathwork');
    final meditationMinToday = _bella.sessionMinutesToday('meditation');
    final alreadyWindingDown = breathworkToday > 0 || meditationMinToday >= 5;

    if (alreadyWindingDown) {
      // Carry the calm forward with ocean waves or forest night.
      final hour = DateTime.now().hour;
      if (hour >= 20 || hour < 6) {
        _recommendedSound = 'Ocean Waves';
        _recommendReason =
            'You\'ve already wound down with practice — ocean waves will carry that calm into sleep.';
      } else {
        _recommendedSound = 'Forest Night';
        _recommendReason =
            'Great session earlier — soft naturals keep the relaxation going.';
      }
      return;
    }

    if (checkin != null && checkin.stress >= 4) {
      _recommendedSound = 'Tibetan Bowl';
      _recommendReason =
          'High stress — healing tones calm your nervous system.';
    } else if (lastSleep != null && lastSleep.quality <= 2) {
      _recommendedSound = 'Ocean Waves';
      _recommendReason = 'Poor recent sleep — ocean waves promote deeper rest.';
    } else if (conditions.contains('Hypertension') ||
        conditions.contains('Heart Disease')) {
      _recommendedSound = 'Rainfall';
      _recommendReason = 'Rain sounds lower heart rate naturally.';
    } else if (conditions.contains('Asthma')) {
      _recommendedSound = 'Forest Night';
      _recommendReason = 'Soft naturals support relaxed breathing.';
    } else if (hour >= 21 || hour < 6) {
      _recommendedSound = 'Piano';
      _recommendReason = 'Soft piano is ideal for winding down this late.';
    } else if (checkin != null && checkin.energy <= 2) {
      _recommendedSound = 'White Noise';
      _recommendReason = 'White noise blocks distractions for low-energy rest.';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildBody();
    return Scaffold(
      backgroundColor: SageColors.linen,
      appBar: AppBar(
        title: Text('Sleep Sounds', style: SageText.headline()),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_anyActive)
            TextButton.icon(
              onPressed: () async {
                _stopTimer();
                await _stopAllAndClose();
              },
              icon: Icon(Icons.stop_rounded, size: 16, color: SageColors.clay),
              label: Text('Stop all',
                  style: TextStyle(fontSize: 13, color: SageColors.clay)),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        // ── Main scrollable content ──────────────────────────────────────
        SingleChildScrollView(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 8, 20, _anyActive ? 220 : 32),
          child: Reveal(
            size: RevealSize.large,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recommendation chip
              if (_recommendedSound != null) _buildRecommendationChip(),
              const SizedBox(height: 16),

              // Section label
              _sectionLabel('SOUNDS'),
              const SizedBox(height: 12),

              // Sound picker — horizontal scroll
              _buildSoundPicker(),
              const SizedBox(height: 24),

              // Mixer (only when 2 sounds active)
              if (_slotSound[0] != null && _slotSound[1] != null) ...[
                _sectionLabel('MIXER'),
                const SizedBox(height: 12),
                _buildMixer(),
                const SizedBox(height: 24),
              ],

              // Sleep timer
              _sectionLabel('SLEEP TIMER'),
              const SizedBox(height: 10),
              _buildTimerPills(),
              const SizedBox(height: 28),

              // Tips
              _sectionLabel('WIND-DOWN TIPS'),
              const SizedBox(height: 12),
              _buildTipsCard(),
            ],
            ),
          ),
        ),

        // ── Now-playing panel (slides up from bottom) ────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SlideTransition(
            position: _panelSlide,
            child: _buildNowPlayingPanel(),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Recommendation chip
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRecommendationChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SageColors.moss.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SageColors.moss.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(Icons.auto_awesome_rounded, color: SageColors.moss, size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                  fontSize: 12.5, color: SageColors.moss, height: 1.4),
              children: [
                TextSpan(
                  text: '$_recommendedSound — ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: _recommendReason),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sound picker
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSoundPicker() {
    return SizedBox(
      height: 134,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _sounds.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _buildSoundCard(_sounds[i]),
      ),
    );
  }

  Widget _buildSoundCard(_Sound sound) {
    final active = _isActive(sound.name);
    final playing = _isPlaying(sound.name);
    final recommended = sound.name == _recommendedSound;
    final accent = sound.accent;

    return Pressable(
      onTap: () => _selectSound(sound.name),
      child: AnimatedContainer(
        duration: SageMotion.valueChange,
        curve: Curves.easeOut,
        width: 100,
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.14) : SageColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active
                ? accent
                : recommended
                    ? accent.withValues(alpha: 0.45)
                    : SageColors.line,
            width: active ? 2.0 : 1.0,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon circle with optional pulse
            active && playing
                ? AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, child) => Transform.scale(
                      scale: _pulse.value,
                      child: child,
                    ),
                    child: _soundIconCircle(sound, active, accent, size: 48),
                  )
                : _soundIconCircle(sound, active, accent, size: 48),

            const SizedBox(height: 10),

            // "For you" badge
            if (recommended && !active)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'For you',
                  style: TextStyle(
                      fontSize: 8.5,
                      color: accent,
                      fontWeight: FontWeight.w700),
                ),
              ),

            Text(
              sound.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? accent : SageColors.ink,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _soundIconCircle(_Sound sound, bool active, Color accent,
      {required double size}) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active
                ? accent.withValues(alpha: 0.22)
                : accent.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(sound.icon, color: accent, size: size * 0.45),
        ),
        if (active)
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              border: Border.all(color: SageColors.card, width: 1.5),
            ),
            child: Icon(
              _isPlaying(sound.name) ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 10,
            ),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mixer
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMixer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: SageColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SageColors.line),
      ),
      child: Column(
        children: [
          for (int slot = 0; slot < 2; slot++)
            if (_slotSound[slot] != null) _buildMixerRow(slot),
        ],
      ),
    );
  }

  Widget _buildMixerRow(int slot) {
    final name = _slotSound[slot]!;
    final sound = _sounds.firstWhere((s) => s.name == name);
    final accent = sound.accent;

    return Padding(
      padding: slot == 0 ? const EdgeInsets.only(bottom: 12) : EdgeInsets.zero,
      child: Row(
        children: [
          // Icon chip
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(sound.icon, color: accent, size: 16),
          ),
          const SizedBox(width: 10),

          // Name + volume slider
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: SageColors.ink)),
                const SizedBox(height: 4),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: accent,
                    inactiveTrackColor: SageColors.line,
                    thumbColor: accent,
                    overlayColor: accent.withValues(alpha: 0.15),
                  ),
                  child: Slider(
                    min: 0.0,
                    max: 1.0,
                    value: _slotVolume[slot],
                    onChanged: (v) => _setSlotVolume(slot, v),
                  ),
                ),
              ],
            ),
          ),

          // Play/pause + remove
          Row(children: [
            Pressable(
              onTap: () => _toggleSlotPlayPause(slot),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _slotPlaying[slot] ? Icons.pause : Icons.play_arrow,
                  color: accent,
                  size: 15,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Pressable(
              onTap: () => _removeSound(name),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: SageColors.clay.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, color: SageColors.clay, size: 14),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Timer pills
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTimerPills() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _timerOptions.map((opt) {
        final selected = _selectedTimer.label == opt.label;
        return Pressable(
          onTap: () => _selectTimer(opt),
          child: AnimatedContainer(
            duration: SageMotion.valueChange,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? SageColors.moss : SageColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? SageColors.moss : SageColors.line,
              ),
            ),
            child: Text(
              opt.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? SageColors.linen : SageColors.inkSoft,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Now-playing panel
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNowPlayingPanel() {
    if (!_anyActive) return const SizedBox.shrink();

    // Use the primary slot for the panel's accent colour.
    final primaryName = _slotSound[0] ?? _slotSound[1];
    final primarySound = primaryName != null
        ? _sounds.firstWhere((s) => s.name == primaryName,
            orElse: () => _sounds[0])
        : _sounds[0];
    final accent = primarySound.accent;
    final secondaryName =
        _slotSound[1] != null && _slotSound[0] != null ? _slotSound[1] : null;

    // Build label: "Rainfall" or "Rainfall + Ocean Waves"
    final labelParts = [_slotSound[0], _slotSound[1]]
        .where((n) => n != null)
        .map((n) => n!)
        .toList();
    final label = labelParts.join(' + ');

    return Container(
      decoration: BoxDecoration(
        color: SageColors.card,
        border: Border(top: BorderSide(color: SageColors.line)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: SageColors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header row: icon + label + timer countdown + stop
          Row(
            children: [
              // Art circle
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(primarySound.icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: SageColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Timer countdown or "Playing"
                    _timerSecondsLeft > 0
                        ? Row(children: [
                            Icon(Icons.timer_outlined,
                                size: 12, color: SageColors.inkSoft),
                            const SizedBox(width: 4),
                            Text(
                              'Stops in ${_fmtTimer(_timerSecondsLeft)}',
                              style: TextStyle(
                                  fontSize: 11.5, color: SageColors.inkSoft),
                            ),
                          ])
                        : Text(
                            _anyPlaying ? 'Now playing' : 'Paused',
                            style: TextStyle(
                                fontSize: 11.5, color: SageColors.inkSoft),
                          ),
                  ],
                ),
              ),

              // Stop all button
              Pressable(
                onTap: () async {
                  _stopTimer();
                  await _stopAllAndClose();
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: SageColors.clay.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.stop_rounded,
                      color: SageColors.clay, size: 18),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Transport controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Primary play/pause (slot 0)
              _buildBigPlayButton(
                slot: 0,
                accent: accent,
                icon: primarySound.icon,
              ),
              if (secondaryName != null) ...[
                const SizedBox(width: 14),
                // Secondary play/pause (slot 1)
                _buildBigPlayButton(
                  slot: 1,
                  accent:
                      _sounds.firstWhere((s) => s.name == secondaryName).accent,
                  icon: _sounds.firstWhere((s) => s.name == secondaryName).icon,
                  small: true,
                ),
              ],
            ],
          ),

          const SizedBox(height: 14),

          // Play in background toggle — keeps sound running with the
          // screen off, the app backgrounded, or while using another
          // feature, instead of auto-pausing.
          InkWell(
            onTap: () => _setPlayInBackground(!_playInBackground),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.dark_mode_outlined,
                      size: 16, color: SageColors.inkSoft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Play in background',
                      style:
                          TextStyle(fontSize: 12.5, color: SageColors.inkSoft),
                    ),
                  ),
                  Switch(
                    value: _playInBackground,
                    onChanged: _setPlayInBackground,
                    activeThumbColor: accent,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBigPlayButton({
    required int slot,
    required Color accent,
    required IconData icon,
    bool small = false,
  }) {
    final size = small ? 48.0 : 58.0;
    final inner = small ? 22.0 : 28.0;
    final playing = _slotPlaying[slot];

    return Pressable(
      onTap: () => _toggleSlotPlayPause(slot),
      child: AnimatedContainer(
        duration: SageMotion.valueChange,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: playing ? accent : accent.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: playing ? Colors.white : accent,
          size: inner,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tips card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTipsCard() {
    final tips = _buildTips();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SageColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SageColors.line),
      ),
      child: Column(
        children: tips.map((t) {
          final idx = tips.indexOf(t);
          return Padding(
            padding: EdgeInsets.only(top: idx == 0 ? 0 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(t['icon'] as IconData, size: 16, color: SageColors.moss),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t['text'] as String,
                    style: TextStyle(
                        fontSize: 13, color: SageColors.ink, height: 1.4),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Map<String, dynamic>> _buildTips() {
    final tips = <Map<String, dynamic>>[
      {
        'text': 'Start 30 min before bed for the best effect.',
        'icon': Icons.nightlight_round
      },
      {
        'text': 'Keep volume comfortable — not too loud.',
        'icon': Icons.volume_down_rounded
      },
    ];
    final checkin = _bella.lastCheckin;
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];

    // Food timing — most relevant context for a bedtime screen.
    final now = DateTime.now();
    final recentHeavyMeal = _bella.getFoodEntries(onDate: now).any((f) {
      final age = now.difference(f.time).inMinutes;
      return age <= 180 && (f.calories ?? 0) >= 500;
    });
    if (recentHeavyMeal) {
      tips.insert(0, {
        'text':
            'Heavy meal recently — give digestion 30+ min before sleeping to improve sleep depth.',
        'icon': Icons.restaurant_outlined,
      });
    }

    // Session-aware breathwork tip: acknowledge completed sessions, suggest
    // one only if the user hasn't done any breathwork or meditation today.
    final breathworkToday = _bella.sessionsToday('breathwork');
    final meditationMinToday = _bella.sessionMinutesToday('meditation');
    final hasWindDownSession = breathworkToday > 0 || meditationMinToday >= 5;

    if (hasWindDownSession) {
      // Affirm rather than suggest — they already did the work.
      final what = breathworkToday > 0 && meditationMinToday >= 5
          ? 'Breathwork and meditation'
          : breathworkToday > 0
              ? 'Breathwork'
              : 'Meditation';
      tips.add({
        'text':
            '$what done tonight — the sounds will carry that calm through into sleep.',
        'icon': Icons.air,
      });
    } else if (checkin != null && checkin.stress >= 4) {
      // High stress + no session yet: nudge toward 4-7-8 specifically.
      tips.add({
        'text':
            'Try 4-7-8 breathing alongside your sound for faster relaxation.',
        'icon': Icons.air,
      });
    } else {
      // No session, normal stress: gentle suggestion.
      tips.add({
        'text': 'Pair with a short breathwork session to wind down faster.',
        'icon': Icons.air,
      });
    }

    if (conditions.contains('Hypertension')) {
      tips.add({
        'text':
            'Lower room temp (18–20 °C) reduces blood pressure during sleep.',
        'icon': Icons.thermostat_outlined
      });
    }
    if (conditions.contains('Diabetes')) {
      tips.add({
        'text':
            'Check blood glucose before bed — sleep quality affects morning readings.',
        'icon': Icons.monitor_heart_outlined
      });
    }
    return tips.take(3).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: SageColors.inkSoft,
      ),
    );
  }
}