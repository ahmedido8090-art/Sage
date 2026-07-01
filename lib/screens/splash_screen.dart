// screens/splash_screen.dart
//
// Branded launch screen. Animates in on startup, holds for a moment,
// then replaces itself with either DashboardScreen or LoginScreen
// depending on whether a persisted session exists.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/user_service.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Wordmark fade + rise
  late final AnimationController _wordmarkCtrl;
  late final Animation<double> _wordmarkOpacity;
  late final Animation<Offset> _wordmarkSlide;

  // Tagline fade (delayed)
  late final AnimationController _taglineCtrl;
  late final Animation<double> _taglineOpacity;

  // Pulse ring that breathes once before we navigate
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  // Dot indicator row
  late final AnimationController _dotsCtrl;
  late final Animation<double> _dotsOpacity;

  @override
  void initState() {
    super.initState();

    _wordmarkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _wordmarkOpacity = CurvedAnimation(
      parent: _wordmarkCtrl,
      curve: Curves.easeOut,
    );
    _wordmarkSlide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _wordmarkCtrl, curve: Curves.easeOut));

    _taglineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _taglineCtrl,
      curve: Curves.easeOut,
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseScale = Tween<double>(begin: 0.6, end: 1.2).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.7, end: 0.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeIn),
    );

    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _dotsOpacity = CurvedAnimation(
      parent: _dotsCtrl,
      curve: Curves.easeOut,
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // 1. Wordmark rises in
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _wordmarkCtrl.forward();

    // 2. Tagline fades in shortly after
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _taglineCtrl.forward();

    // 3. Pulse ring blooms
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _pulseCtrl.forward();

    // 4. Loading dots appear
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _dotsCtrl.forward();

    // 5. Hold briefly then navigate
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _navigate();
  }

  void _navigate() {
    if (!mounted) return;
    final loggedIn = UserService().currentUser != null;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) =>
            loggedIn ? const DashboardScreen() : const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _wordmarkCtrl.dispose();
    _taglineCtrl.dispose();
    _pulseCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SageColors.linen,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulse ring behind the icon
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Stack(
                alignment: Alignment.center,
                children: [
                  // Expanding ring
                  Transform.scale(
                    scale: _pulseScale.value,
                    child: Opacity(
                      opacity: _pulseOpacity.value,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: SageColors.moss,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Static inner circle
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SageColors.moss.withValues(alpha: 0.10),
                      border: Border.all(
                        color: SageColors.moss.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.spa_outlined,
                      size: 30,
                      color: SageColors.moss,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Wordmark
            SlideTransition(
              position: _wordmarkSlide,
              child: FadeTransition(
                opacity: _wordmarkOpacity,
                child: Text('Sage', style: SageText.wordmark(color: SageColors.moss).copyWith(fontSize: 36)),
              ),
            ),

            const SizedBox(height: 8),

            // Tagline
            FadeTransition(
              opacity: _taglineOpacity,
              child: Text(
                'Your personal wellness companion',
                style: TextStyle(
                  fontSize: 13.5,
                  color: SageColors.inkSoft,
                  letterSpacing: 0.2,
                ),
              ),
            ),

            const SizedBox(height: 52),

            // Animated loading dots
            FadeTransition(
              opacity: _dotsOpacity,
              child: _LoadingDots(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three dots that pulse in sequence, giving a soft "loading" feel
/// without a harsh spinner.
class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    _anims = _controllers
        .map((c) => Tween<double>(begin: 0.3, end: 1.0).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();

    _startWave();
  }

  Future<void> _startWave() async {
    while (mounted) {
      for (int i = 0; i < 3; i++) {
        if (!mounted) break;
        _controllers[i].forward(from: 0);
        await Future.delayed(const Duration(milliseconds: 160));
      }
      if (!mounted) break;
      await Future.delayed(const Duration(milliseconds: 400));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SageColors.moss.withValues(alpha: _anims[i].value),
            ),
          ),
        );
      }),
    );
  }
}