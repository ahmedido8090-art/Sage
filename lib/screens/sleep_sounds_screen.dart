import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../services/data_storage_service.dart';
import '../theme/bella_theme.dart';

class SleepSoundsScreen extends StatefulWidget {
  const SleepSoundsScreen({super.key});

  @override
  State<SleepSoundsScreen> createState() => _SleepSoundsScreenState();
}

class _SleepSoundsScreenState extends State<SleepSoundsScreen>
    with WidgetsBindingObserver {
  late AudioPlayer _audioPlayer;
  final DataStorageService _dataStorage = DataStorageService();

  String? _currentlyPlaying;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isDisposed = false;
  DateTime? _startTime;

  final List<Map<String, dynamic>> _sleepSounds = [
    {
      'name': 'Rainfall',
      'description': 'Gentle rain for relaxation',
      'icon': Icons.water_drop,
      'color': BellaColors.secondary,
      'audioAsset': 'audio/rain.mp3',
      'duration': '10 min',
    },
    {
      'name': 'Ocean Waves',
      'description': 'Calming ocean sounds',
      'icon': Icons.waves,
      'color': BellaColors.accent,
      'audioAsset': 'audio/waves.mp3',
      'duration': '10 min',
    },
    {
      'name': 'Forest Night',
      'description': 'Crickets and wind',
      'icon': Icons.forest,
      'color': BellaColors.success,
      'audioAsset': 'audio/ghaba.mp3',
      'duration': '10 min',
    },
    {
      'name': 'White Noise',
      'description': 'Blocks distractions',
      'icon': Icons.volume_up,
      'color': BellaColors.textSecondary,
      'audioAsset': 'audio/whitenoise.mp3',
      'duration': '10 min',
    },
    {
      'name': 'Piano Melodies',
      'description': 'Soft piano for sleep',
      'icon': Icons.music_note,
      'color': BellaColors.primary,
      'audioAsset': 'audio/piano.mp3',
      'duration': '10 min',
    },
    {
      'name': 'Tibetan Bowl',
      'description': 'Healing frequencies',
      'icon': Icons.self_improvement,
      'color': BellaColors.warning,
      'audioAsset': 'audio/tibetbowls.mp3',
      'duration': '10 min',
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _setupAudioListeners();
  }

  void _setupAudioListeners() {
    _audioPlayer.onDurationChanged.listen((duration) {
      if (!_isDisposed && mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (!_isDisposed && mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!_isDisposed && mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (!_isDisposed && mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pauseIfPlaying();
    }
  }

  void _pauseIfPlaying() async {
    if (_isPlaying) {
      try {
        await _audioPlayer.pause();
        if (!_isDisposed && mounted) {
          setState(() {
            _isPlaying = false;
          });
        }
      } catch (_) {}
    }
  }

  void _playSound(String soundName, String assetPath) async {
    try {
      if (_currentlyPlaying == soundName && _isPlaying) {
        await _audioPlayer.pause();
        if (!_isDisposed && mounted) {
          setState(() {
            _isPlaying = false;
          });
        }
        return;
      }

      if (_currentlyPlaying != soundName) {
        await _audioPlayer.stop();
        await _audioPlayer.play(AssetSource(assetPath));
        if (!_isDisposed && mounted) {
          setState(() {
            _currentlyPlaying = soundName;
            _position = Duration.zero;
            _isPlaying = true;
            _startTime = DateTime.now();
          });
        }
      } else {
        await _audioPlayer.resume();
        if (!_isDisposed && mounted) {
          setState(() {
            _isPlaying = true;
            _startTime ??= DateTime.now();
          });
        }
      }
    } catch (_) {
      if (!_isDisposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error playing audio'),
            backgroundColor: BellaColors.danger,
          ),
        );
      }
    }
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      if (!_isDisposed && mounted) {
        setState(() {
          _isPlaying = false;
        });
      }
    } else {
      await _audioPlayer.resume();
      if (!_isDisposed && mounted) {
        setState(() {
          _isPlaying = true;
          _startTime ??= DateTime.now();
        });
      }
    }
  }

  void _stopAllSounds() async {
    try {
      await _audioPlayer.stop();

      if (_currentlyPlaying != null && _startTime != null) {
        final duration = DateTime.now().difference(_startTime!).inSeconds;
        if (duration > 30) {
          _trackSleepSoundUsage(_currentlyPlaying!, duration);
        }
      }

      if (!_isDisposed && mounted) {
        setState(() {
          _currentlyPlaying = null;
          _isPlaying = false;
          _position = Duration.zero;
          _startTime = null;
        });
      }
    } catch (_) {}
  }

  void _trackSleepSoundUsage(String soundName, int durationSeconds) {
    _dataStorage.saveSleepSoundsSession(
      soundName: soundName,
      durationSeconds: durationSeconds,
      timestamp: DateTime.now(),
      relaxationScore: _calculateRelaxationScore(durationSeconds),
    );

    _dataStorage.updateDailyGoal(
      goalType: 'relaxation',
      progress: durationSeconds / 60.0,
      target: 15.0,
      date: DateTime.now(),
    );
  }

  double _calculateRelaxationScore(int duration) {
    if (duration > 600) return 1.0;
    if (duration > 300) return 0.7;
    if (duration > 60) return 0.4;
    return 0.1;
  }

  void _seekForward() async {
    final newPosition = _position + const Duration(seconds: 10);
    if (newPosition <= _duration) {
      await _audioPlayer.seek(newPosition);
    }
  }

  void _seekBackward() async {
    final newPosition = _position - const Duration(seconds: 10);
    if (newPosition >= Duration.zero) {
      await _audioPlayer.seek(newPosition);
    }
  }

  void _seekToPosition(double value) async {
    final position = Duration(seconds: (value * _duration.inSeconds).toInt());
    await _audioPlayer.seek(position);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stopAllSounds();
    _audioPlayer.dispose();
    super.dispose();
  }

  Widget _buildTipTile(String text, IconData icon) {
    return Row(
      children: [
        const SizedBox(width: 2),
        Icon(icon, size: 16, color: BellaColors.secondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: BellaColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSound = _sleepSounds.firstWhere(
      (sound) => sound['name'] == _currentlyPlaying,
      orElse: () => _sleepSounds[0],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sleep Sounds'),
        actions: [
          if (_isPlaying)
            IconButton(
              onPressed: _stopAllSounds,
              icon: const Icon(Icons.stop),
              tooltip: 'Stop all sounds',
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: BellaColors.appGradient,
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sleep Better',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: BellaColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Choose relaxing sounds to unwind and support recovery.',
                    style: TextStyle(
                      fontSize: 14,
                      color: BellaColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.86,
                      ),
                      itemCount: _sleepSounds.length,
                      itemBuilder: (context, index) {
                        final sound = _sleepSounds[index];
                        final isPlaying =
                            _currentlyPlaying == sound['name'] && _isPlaying;

                        return Container(
                          decoration: BoxDecoration(
                            color: BellaColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: BellaColors.divider),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _playSound(
                                sound['name'],
                                sound['audioAsset'],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: 58,
                                          height: 58,
                                          decoration: BoxDecoration(
                                            color: (sound['color'] as Color)
                                                .withOpacity(0.14),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            sound['icon'] as IconData,
                                            color: sound['color'] as Color,
                                            size: 28,
                                          ),
                                        ),
                                        if (isPlaying)
                                          Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              width: 24,
                                              height: 24,
                                              decoration: BoxDecoration(
                                                color: BellaColors.danger,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: BellaColors.surface,
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.pause,
                                                color: Colors.white,
                                                size: 12,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      sound['name'],
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: sound['color'] as Color,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      sound['description'],
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: BellaColors.textSecondary,
                                        height: 1.3,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: (sound['color'] as Color)
                                            .withOpacity(0.10),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.timer,
                                            size: 10,
                                            color: sound['color'] as Color,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            sound['duration'],
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: sound['color'] as Color,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: BellaColors.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: BellaColors.secondary.withOpacity(0.18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                color: BellaColors.secondary,
                                size: 20,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Tips for Better Sleep',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: BellaColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTipTile('Use 30 minutes before bed',
                              Icons.nightlight_round),
                          const SizedBox(height: 12),
                          _buildTipTile(
                              'Keep volume comfortable', Icons.volume_up),
                          const SizedBox(height: 12),
                          _buildTipTile(
                              'Combine with breathing', Icons.self_improvement),
                          const SizedBox(height: 12),
                          _buildTipTile('Follow a consistent sleep schedule',
                              Icons.schedule),
                        ],
                      ),
                    ),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
            if (_currentlyPlaying != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: BellaColors.surface,
                  border: Border(top: BorderSide(color: BellaColors.divider)),
                ),
                child: Column(
                  children: [
                    SliderTheme(
                      data: const SliderThemeData(
                        trackHeight: 4,
                        thumbShape:
                            RoundSliderThumbShape(enabledThumbRadius: 8),
                        overlayShape:
                            RoundSliderOverlayShape(overlayRadius: 16),
                        activeTrackColor: BellaColors.secondary,
                        inactiveTrackColor: BellaColors.surfaceSoft,
                        thumbColor: BellaColors.secondary,
                      ),
                      child: Slider(
                        value: _duration.inSeconds > 0
                            ? _position.inSeconds / _duration.inSeconds
                            : 0,
                        onChanged: _seekToPosition,
                        onChangeEnd: _seekToPosition,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_position),
                            style: const TextStyle(
                              fontSize: 12,
                              color: BellaColors.textMuted,
                            ),
                          ),
                          Text(
                            _formatDuration(_duration),
                            style: const TextStyle(
                              fontSize: 12,
                              color: BellaColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: (currentSound['color'] as Color)
                                .withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            currentSound['icon'] as IconData,
                            color: currentSound['color'] as Color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentlyPlaying ?? 'Playing',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: BellaColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isPlaying ? 'Now Playing' : 'Paused',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: BellaColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _seekBackward,
                              icon: const Icon(
                                Icons.replay_10,
                                color: BellaColors.secondary,
                                size: 26,
                              ),
                            ),
                            Container(
                              decoration: const BoxDecoration(
                                color: BellaColors.secondary,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: _togglePlayPause,
                                icon: Icon(
                                  _isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _seekForward,
                              icon: const Icon(
                                Icons.forward_10,
                                color: BellaColors.secondary,
                                size: 26,
                              ),
                            ),
                            IconButton(
                              onPressed: _stopAllSounds,
                              icon: const Icon(
                                Icons.stop,
                                color: BellaColors.danger,
                                size: 26,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
