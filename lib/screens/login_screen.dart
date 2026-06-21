import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../theme/bella_theme.dart';
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
  String? _errorMessage;

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

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

    if (!mounted) return;

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome to Bella.')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      setState(() => _errorMessage = error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: BellaColors.danger),
      );
    }
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BellaColors.appGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: BellaColors.surface.withOpacity(0.96),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: BellaColors.divider),
                    boxShadow: [
                      BoxShadow(
                        color: BellaColors.cardGlow.withOpacity(0.45),
                        blurRadius: 28,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          height: 82,
                          width: 82,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: BellaColors.primaryGradient,
                            boxShadow: [
                              BoxShadow(
                                color: BellaColors.primary.withOpacity(0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.nightlight_round,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Bella',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'L\'utente che utilizza questa app è molto bella',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: BellaColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        if (_errorMessage != null) ...[
                          _buildMessageCard(
                            icon: Icons.error_outline,
                            color: BellaColors.danger,
                            text: _errorMessage!,
                            onClose: _clearError,
                          ),
                          const SizedBox(height: 18),
                        ],
                        TextFormField(
                          controller: _usernameController,
                          onChanged: (_) => _clearError(),
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your username';
                            }
                            if (value.length < 3) {
                              return 'Username must be at least 3 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          onChanged: (_) => _clearError(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: BellaColors.textMuted,
                              ),
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
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Text('LOGIN'),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don’t have an account? ",
                              style: theme.textTheme.bodyMedium,
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SignupScreen(),
                                  ),
                                );
                              },
                              child: const Text(
                                'Sign Up',
                                style: TextStyle(
                                  color: BellaColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Bluetooth data flow remains unchanged.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageCard({
    required IconData icon,
    required Color color,
    required String text,
    VoidCallback? onClose,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              icon: Icon(Icons.close, size: 18, color: color),
            ),
        ],
      ),
    );
  }
}
