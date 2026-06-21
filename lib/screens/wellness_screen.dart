import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/user_service.dart';
import 'breathwork_screen.dart';
import 'meditation_screen.dart';
import 'sleep_sounds_screen.dart';
import 'walking_screen.dart';

class WellnessScreen extends StatefulWidget {
  const WellnessScreen({super.key});

  @override
  State<WellnessScreen> createState() => _WellnessScreenState();
}

class _WellnessScreenState extends State<WellnessScreen> {
  final BluetoothService _bt = BluetoothService.instance;
  StreamSubscription? _dataSubscription;

  int _heartRate = 72;
  int _steps = 0;
  double _bmi = 22.5;

  final List<Map<String, String>> _quotes = [
    {
      'quote':
          'The body heals with play, the mind heals with laughter, and the spirit heals with joy.',
      'author': 'Proverb',
    },
    {
      'quote':
          'Almost everything will work again if you unplug it for a few minutes, including you.',
      'author': 'Anne Lamott',
    },
    {
      'quote': 'Take care of your body. It is the only place you have to live.',
      'author': 'Jim Rohn',
    },
    {
      'quote': 'Wellness is built one small choice at a time.',
      'author': 'Bella',
    },
  ];

  int _quoteIndex = 0;

  @override
  void initState() {
    super.initState();

    _dataSubscription = _bt.dataStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _heartRate = data.heartRate;
        _steps = data.steps;
      });
    });

    _calculateBMI();
  }

  void _calculateBMI() {
    final user = UserService().currentUserObject;
    if (user != null && user.height > 0 && user.weight > 0) {
      final heightInMeters = user.height / 100;
      setState(() {
        _bmi = user.weight / (heightInMeters * heightInMeters);
      });
    }
  }

  String _getBMICategory() {
    if (_bmi < 18.5) return 'Underweight';
    if (_bmi < 25) return 'Normal';
    if (_bmi < 30) return 'Overweight';
    return 'Obese';
  }

  String _getHealthAdvice() {
    final user = UserService().currentUserObject;
    if (user == null) return 'Start building a steadier wellness routine.';

    if (_bmi < 18.5) {
      return 'Focus on nourishing meals, lighter cardio, and strength-building routines.';
    } else if (_bmi < 25) {
      return 'You are in a balanced range. Keep consistency with movement, sleep, and recovery.';
    } else if (_bmi < 30) {
      return 'Walking, breathwork, and mindful nutrition can support steady long-term progress.';
    } else {
      return 'Gentle activity, recovery work, and a guided health plan can help you progress safely.';
    }
  }

  Color _getBMIColor() {
    if (_bmi < 18.5) return const Color(0xFF7C8CFF);
    if (_bmi < 25) return const Color(0xFF37C48E);
    if (_bmi < 30) return const Color(0xFFFFB84D);
    return const Color(0xFFFF6B6B);
  }

  void _showNewQuote() {
    setState(() {
      _quoteIndex = (_quoteIndex + 1) % _quotes.length;
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quotes[_quoteIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              _buildHealthStatusCard(),
              const SizedBox(height: 18),
              _buildSectionTitle('Wellness tools'),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.94,
                children: [
                  _buildWellnessCard(
                    title: 'Breathwork',
                    subtitle: 'Breathing Technique',
                    icon: Icons.air_rounded,
                    color: const Color(0xFF62B6FF),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BreathworkScreen(
                          initialHeartRate: _heartRate,
                        ),
                      ),
                    ),
                  ),
                  _buildWellnessCard(
                    title: 'Meditation',
                    subtitle: 'Guided Sessions',
                    icon: Icons.self_improvement_rounded,
                    color: const Color(0xFFB388FF),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MeditationScreen(
                          initialHeartRate: _heartRate,
                          bmi: _bmi,
                          bmiCategory: '',
                        ),
                      ),
                    ),
                  ),
                  _buildWellnessCard(
                    title: 'Walking',
                    subtitle: 'Track Activity',
                    icon: Icons.directions_walk_rounded,
                    color: const Color(0xFF37C48E),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => WalkingScreen(
                          initialHeartRate: _heartRate,
                          initialSteps: _steps,
                        ),
                      ),
                    ),
                  ),
                  _buildWellnessCard(
                    title: 'Sleep Sounds',
                    subtitle: 'Relax & Rest',
                    icon: Icons.nightlight_round,
                    color: const Color(0xFF7C8CFF),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SleepSoundsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildQuoteCard(quote),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A2240),
            Color(0xFF11182D),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF8C7BFF).withOpacity(0.16),
            ),
            child: const Icon(
              Icons.spa_rounded,
              color: Color(0xFFD5CEFF),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wellness Center',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Breathe • Move • Rest',
                  style: TextStyle(
                    color: Color(0xFF9AA6C8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthStatusCard() {
    final bmiColor = _getBMIColor();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121A2F),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.monitor_heart_outlined,
                color: Color(0xFFE6ECFF),
                size: 22,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Your health status',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: bmiColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _getBMICategory(),
                  style: TextStyle(
                    color: bmiColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  value: _bmi.toStringAsFixed(1),
                  label: 'BMI',
                  accent: bmiColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricItem(
                  value: '$_heartRate',
                  label: 'Heart Rate',
                  accent: const Color(0xFFFF7A8A),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricItem(
                  value: '$_steps',
                  label: 'Steps',
                  accent: const Color(0xFF62B6FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2440),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFFFD66B),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _getHealthAdvice(),
                    style: const TextStyle(
                      color: Color(0xFFB7C2E0),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildMetricItem({
    required String value,
    required String label,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A223B),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8E9BBC),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWellnessCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121A2F),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF8E9BBC),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuoteCard(Map<String, String> quote) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF8B5CF6),
            Color(0xFF5B6CFF),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B6CFF).withOpacity(0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.format_quote_rounded,
            color: Colors.white,
            size: 30,
          ),
          const SizedBox(height: 12),
          Text(
            '"${quote['quote']}"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '- ${quote['author']}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _showNewQuote,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.75)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
            ),
            child: const Text('New Inspiration'),
          ),
        ],
      ),
    );
  }
}
