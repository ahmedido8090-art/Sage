// screens/login_screen.dart
//
// Two-phase entrance (logo first, form follows) is now built on Reveal's
// delay parameter instead of two hand-rolled AnimationControllers — same
// primitive, same tokens, just staggered by an explicit delay so the logo
// settles before the form rises in underneath it.
import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/page_transitions.dart';
import '../widgets/reveal.dart';
import '../widgets/pressable.dart';
import 'dashboard_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _keepLoggedIn = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      final error = UserService().authenticate(
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );

      setState(() => _isLoading = false);

      if (mounted) {
        if (error == null) {
          if (_keepLoggedIn) {
            UserService().persistSession(_usernameController.text.trim());
          } else {
            UserService().clearPersistedSession();
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Welcome back, ${_usernameController.text.trim()}!'),
              backgroundColor: SageColors.moss,
              duration: const Duration(seconds: 2),
            ),
          );

          Navigator.pushReplacement(
            context,
            fadeRoute(const DashboardScreen()),
          );
        } else {
          setState(() => _errorMessage = error);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: SageColors.clay,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  InputDecoration _inputDecoration(String label, IconData icon,
      {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: SageColors.inkSoft),
      prefixIcon: Icon(icon, color: SageColors.moss, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: SageColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: SageColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: SageColors.moss, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: SageColors.clay, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: SageColors.clay, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SageColors.linen,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Logo / greeting — settles first ──
                  Reveal(
                    child: Column(
                        children: [
                          Text('Sage', style: SageText.wordmark().copyWith(fontSize: 32)),
                          const SizedBox(height: 10),
                          Text(
                            'Welcome back',
                            textAlign: TextAlign.center,
                            style: SageText.headline(),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sign in to continue your wellness journey',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: SageColors.inkSoft, fontSize: 13.5),
                          ),
                        ],
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Form fields — rise in just after the logo ──
                  Reveal(
                    size: RevealSize.large,
                    delay: SageMotion.staggerStep * 3,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Error box
                          AnimatedSize(
                            duration: SageMotion.valueChange,
                            curve: Curves.easeOut,
                            child: _errorMessage != null
                                ? Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: SageColors.clay
                                              .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: SageColors.clay
                                                  .withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.error_outline,
                                                color: SageColors.clay,
                                                size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _errorMessage!,
                                                style: TextStyle(
                                                    color: SageColors.clay),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close,
                                                  size: 16),
                                              onPressed: _clearError,
                                              color: SageColors.clay,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),

                          TextFormField(
                            controller: _usernameController,
                            decoration: _inputDecoration(
                                'Username', Icons.person_outline),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your username';
                              }
                              if (value.length < 3) {
                                return 'Username must be at least 3 characters';
                              }
                              return null;
                            },
                            onChanged: (_) => _clearError(),
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: _inputDecoration(
                              'Password',
                              Icons.lock_outline,
                              suffix: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: SageColors.inkSoft,
                                  size: 19,
                                ),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                            onChanged: (_) => _clearError(),
                          ),

                          const SizedBox(height: 14),

                          Row(
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: Checkbox(
                                  value: _keepLoggedIn,
                                  activeColor: SageColors.moss,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (value) => setState(
                                      () => _keepLoggedIn = value ?? false),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(
                                    () => _keepLoggedIn = !_keepLoggedIn),
                                child: Text(
                                  'Keep me logged in',
                                  style: TextStyle(
                                      color: SageColors.inkSoft,
                                      fontSize: 13.5),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),

                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SageColors.moss,
                                foregroundColor: SageColors.linen,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: AnimatedSwitcher(
                                duration: SageMotion.valueChange,
                                child: _isLoading
                                    ? SizedBox(
                                        key: const ValueKey('loader'),
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: SageColors.linen,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'LOG IN',
                                        key: ValueKey('label'),
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 26),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account? ",
                                style: TextStyle(
                                    color: SageColors.inkSoft,
                                    fontSize: 13.5),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  slideRightRoute(const SignupScreen()),
                                ),
                                child: Text(
                                  'Sign up',
                                  style: TextStyle(
                                    color: SageColors.moss,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ), // Reveal (form)
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}