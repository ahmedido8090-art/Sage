// services/sleep_sounds_player_service.dart
//
// Owns the Sleep Sounds mixer's AudioPlayers and slot state at the app
// level instead of inside SleepSoundsScreenState.
//
// Why this exists: previously every bit of mixer state (which sounds are
// playing, at what volume, the sleep timer) lived directly on the screen's
// State object, and the two AudioPlayer instances were created in initState
// and disposed in dispose(). That meant leaving the screen — even just to
// go do a Daily Check-in — popped the route, ran dispose(), and killed
// playback immediately, regardless of the "Play in background" toggle.
// That toggle only ever protected against the OS backgrounding the *app*,
// not in-app navigation away from this one screen.
//
// Moving ownership here means the players, and the mixer state, live for
// as long as the app process does. The screen becomes a thin UI layer that
// reads/writes through this singleton and rebuilds via ChangeNotifier.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'bella_service.dart';

class SleepSoundsPlayerService extends ChangeNotifier
    with WidgetsBindingObserver {
  static final SleepSoundsPlayerService _instance =
      SleepSoundsPlayerService._internal();
  factory SleepSoundsPlayerService() => _instance;
  SleepSoundsPlayerService._internal();

  final BellaService _bella = BellaService();

  bool _initialized = false;
  bool _observerAttached = false;

  // ── Mixer state — max 2 simultaneous sounds ──────────────────────────────
  final List<AudioPlayer> players = [AudioPlayer(), AudioPlayer()];
  final List<String?> slotSound = [null, null];
  final List<double> slotVolume = [1.0, 0.5];
  final List<bool> slotPlaying = [false, false];

  // ── Session time tracking ─────────────────────────────────────────────────
  //
  // We track *accumulated* play seconds per slot rather than a single start
  // timestamp.  This is necessary because pausing and resuming with a naive
  // start timestamp causes dead/paused time to be counted as play time,
  // making the logged duration inconsistent.
  //
  //  _slotAccumulatedSecs[i]  — play-seconds banked before the latest resume
  //  _slotResumeTime[i]       — wall-clock moment the slot last resumed,
  //                             or null when paused / not playing
  //  _slotLogged[i]           — true once saveSessionIfNeeded has committed
  //                             this slot's data, so we never double-log
  final List<int> _slotAccumulatedSecs = [0, 0];
  final List<DateTime?> _slotResumeTime = [null, null];
  final List<bool> _slotLogged = [false, false];

  // ── Sleep timer ───────────────────────────────────────────────────────────
  /// null = "Always on". Defaults to 30 minutes to match the screen's
  /// original default selection.
  int? selectedTimerMinutes = 30;
  Timer? _countdownTimer;
  int timerSecondsLeft = 0;

  /// When true, sounds keep playing if the screen turns off, the user
  /// navigates elsewhere in the app, or the app is backgrounded entirely —
  /// instead of auto-pausing. Persisted per-user via Bella.
  bool playInBackground = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Setup
  // ─────────────────────────────────────────────────────────────────────────

  /// Safe to call every time SleepSoundsScreen mounts — only does real work
  /// once per app run.
  void init() {
    if (_initialized) return;
    _initialized = true;

    playInBackground =
        _bella.getTarget<bool>('sleepSoundsPlayInBackground') ?? false;

    for (int i = 0; i < players.length; i++) {
      players[i].setAudioContext(_audioContext());
      final slot = i;
      players[slot].onPlayerStateChanged.listen((state) {
        final nowPlaying = state == PlayerState.playing;

        if (nowPlaying && !slotPlaying[slot]) {
          // Transitioned to playing — record resume time so we can
          // accumulate real play seconds from this moment.
          _slotResumeTime[slot] = DateTime.now();
        } else if (!nowPlaying && slotPlaying[slot]) {
          // Transitioned to paused/stopped — bank the seconds played
          // since the last resume before we lose the reference.
          _bankSeconds(slot);
        }

        slotPlaying[slot] = nowPlaying;
        notifyListeners();
      });
    }

    if (!_observerAttached) {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    }
  }

  AudioContext _audioContext() => AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          // 'none' keeps both sound slots mixable; background playback
          // itself is governed by playInBackground, not focus mode.
          audioFocus: AndroidAudioFocus.none,
        ),
      );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (playInBackground) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      for (int i = 0; i < players.length; i++) {
        if (slotPlaying[i]) {
          players[i].pause();
          // _bankSeconds will be called by onPlayerStateChanged above
          // when the player confirms it has paused.
        }
      }
    }
  }

  Future<void> setPlayInBackground(bool value) async {
    playInBackground = value;
    await _bella.setTarget('sleepSoundsPlayInBackground', value);
    for (int i = 0; i < players.length; i++) {
      await players[i].setAudioContext(_audioContext());
    }
    notifyListeners();
  }

  // ── Convenience lookups ───────────────────────────────────────────────────

  bool isActive(String name) => slotSound.contains(name);
  bool isPlaying(String name) {
    final idx = slotSound.indexOf(name);
    return idx >= 0 && slotPlaying[idx];
  }

  int slotOf(String name) => slotSound.indexOf(name);
  bool get anyPlaying => slotPlaying.any((p) => p);
  bool get anyActive => slotSound.any((s) => s != null);

  List<DateTime?>? get slotStart => null;

  // ── Time-tracking helpers ─────────────────────────────────────────────────

  /// Add the seconds elapsed since the slot last resumed into its bank.
  /// Safe to call even if the slot is paused (resume time will be null).
  void _bankSeconds(int slot) {
    final resume = _slotResumeTime[slot];
    if (resume == null) return;
    _slotAccumulatedSecs[slot] += DateTime.now().difference(resume).inSeconds;
    _slotResumeTime[slot] = null;
  }

  /// Total play seconds for a slot: banked + currently-playing delta.
  int _totalPlaySecs(int slot) {
    final banked = _slotAccumulatedSecs[slot];
    final resume = _slotResumeTime[slot];
    if (resume == null) return banked;
    return banked + DateTime.now().difference(resume).inSeconds;
  }

  /// Reset all time-tracking state for a slot (call after logging or evicting).
  void _resetSlotTracking(int slot) {
    _slotAccumulatedSecs[slot] = 0;
    _slotResumeTime[slot] = null;
    _slotLogged[slot] = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Playback control
  // ─────────────────────────────────────────────────────────────────────────

  /// Select [name] (with its asset path [asset]). Toggles play/pause if
  /// already in a slot, otherwise claims a free slot (evicting the
  /// secondary slot if both are full) and starts playback.
  Future<void> selectSound(String name, String asset) async {
    final idx = slotOf(name);

    if (idx >= 0) {
      // Already loaded — just toggle play/pause.
      // Time tracking is handled in onPlayerStateChanged.
      if (slotPlaying[idx]) {
        await players[idx].pause();
      } else {
        await players[idx].resume();
      }
      notifyListeners();
      return;
    }

    int slot = slotSound[0] == null ? 0 : (slotSound[1] == null ? 1 : -1);
    if (slot < 0) {
      slot = 1;
      await evictSlot(slot);
    }

    // Reset tracking before we start so the new session is clean.
    _resetSlotTracking(slot);

    await players[slot].setReleaseMode(ReleaseMode.loop);
    await players[slot].setVolume(slotVolume[slot]);
    await players[slot].play(AssetSource(asset));

    slotSound[slot] = name;
    slotPlaying[slot] = true;
    // onPlayerStateChanged will set _slotResumeTime when the player
    // confirms it's playing.  Set it here too as an immediate fallback
    // so we don't lose the first few seconds if the event is delayed.
    _slotResumeTime[slot] = DateTime.now();
    notifyListeners();

    startTimerIfNeeded();
  }

  Future<void> evictSlot(int slot) async {
    saveSessionIfNeeded(slot);
    await players[slot].stop();
    slotSound[slot] = null;
    slotPlaying[slot] = false;
    _resetSlotTracking(slot);
    notifyListeners();
  }

  /// Returns true if both slots are now empty (caller may want to close
  /// any now-playing panel UI).
  Future<bool> removeSound(String name) async {
    final idx = slotOf(name);
    if (idx < 0) return slotSound[0] == null && slotSound[1] == null;
    await evictSlot(idx);
    final empty = slotSound[0] == null && slotSound[1] == null;
    if (empty) stopTimer();
    return empty;
  }

  Future<void> toggleSlotPlayPause(int slot) async {
    if (slotPlaying[slot]) {
      await players[slot].pause();
      // _bankSeconds called by onPlayerStateChanged on the pause event.
    } else {
      await players[slot].resume();
      // _slotResumeTime set by onPlayerStateChanged on the play event.
    }
    notifyListeners();
  }

  Future<void> setSlotVolume(int slot, double v) async {
    await players[slot].setVolume(v);
    slotVolume[slot] = v;
    notifyListeners();
  }

  /// Log this slot's session to Bella if the user played long enough.
  ///
  /// Rules:
  ///  • Skip if already logged this session (prevents double-logging when
  ///    both evictSlot and stopAllAndClose touch the same slot).
  ///  • Skip if total play time is under 60 seconds — not a meaningful
  ///    session.  (The old code had a 30-second gate followed by a
  ///    separate ≥60-second check, leaving a 30–59 s dead zone where
  ///    nothing was logged at all — that was the main source of
  ///    inconsistency.)
  ///  • Bank any still-running seconds first so the total is accurate.
  void saveSessionIfNeeded(int slot) {
    if (_slotLogged[slot]) return; // already committed — don't double-log
    if (slotSound[slot] == null) return;

    // Bank any seconds still accumulating (slot may still be playing).
    _bankSeconds(slot);

    final totalSecs = _slotAccumulatedSecs[slot];
    if (totalSecs < 60) return; // under a minute — not worth logging

    _bella.logSession('sleep_sounds', totalSecs ~/ 60);
    _slotLogged[slot] = true; // mark so subsequent calls don't re-log
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sleep timer
  // ─────────────────────────────────────────────────────────────────────────

  void setSelectedTimerMinutes(int? minutes) {
    selectedTimerMinutes = minutes;
    if (anyActive) startTimerIfNeeded();
    notifyListeners();
  }

  void startTimerIfNeeded() {
    _countdownTimer?.cancel();
    if (selectedTimerMinutes == null) {
      timerSecondsLeft = 0;
      notifyListeners();
      return; // "Always on"
    }
    timerSecondsLeft = selectedTimerMinutes! * 60;
    notifyListeners();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      timerSecondsLeft--;
      notifyListeners();
      if (timerSecondsLeft <= 0) {
        stopTimer();
        stopAllAndClose();
      }
    });
  }

  void stopTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    timerSecondsLeft = 0;
    notifyListeners();
  }

  Future<void> stopAllAndClose() async {
    for (int i = 0; i < players.length; i++) {
      saveSessionIfNeeded(i);
      await players[i].stop();
      slotSound[i] = null;
      slotPlaying[i] = false;
      _resetSlotTracking(i);
    }
    notifyListeners();
  }
}
