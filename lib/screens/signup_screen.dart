// screens/signup_screen.dart
import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/bella_service.dart';
import '../services/care_rules.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/page_transitions.dart';
import '../widgets/reveal.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

  String _selectedGender = 'Male';
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  final Set<String> _selectedConditions = {};

  void _handleSignup() async {
    if (_formKey.currentState!.validate()) {
      if (_passwordController.text != _confirmPasswordController.text) {
        setState(() => _errorMessage = 'Passwords do not match');
        return;
      }

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      await Future.delayed(const Duration(milliseconds: 800));

      // Create user object
      final user = User(
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        age: int.tryParse(_ageController.text) ?? 0,
        gender: _selectedGender,
        height: double.tryParse(_heightController.text) ?? 0.0,
        weight: double.tryParse(_weightController.text) ?? 0.0,
        chronicDiseases: _selectedConditions.toList(),
      );

      // Register user
      final result = UserService().register(user);

      // Seed sensible Bella targets immediately after registration so new
      // users don't see "0/0" progress rings or divide-by-zero guards on
      // their very first session. Conditions-aware water target comes from
      // CareRules; activity targets use the same defaults the rest of the
      // app falls back to, but stored explicitly so they can be overridden
      // later without changing code-level fallbacks everywhere.
      if (result == 'Registration successful!') {
        // Log in temporarily so BellaService resolves the correct user key.
        UserService().authenticate(user.username, user.password);
        final h = user.height / 100;
        final bmi = h > 0 ? user.weight / (h * h) : 22.5;
        final plan = CareRules.generatePlan(
          bmi: bmi,
          conditions: user.chronicDiseases,
        );
        await BellaService().saveTargets({
          'waterMl': plan.dailyWaterMlTarget,
          'calorieTarget': 2000,
          'meditationMinutes': 10,
          'walkMinutes': 30,
          'breathworkSessions': 1,
        });
        // Clear the session so they land on the login screen as expected.
        UserService().logout();
      }

      setState(() => _isLoading = false);

      if (mounted) {
        if (result == "Registration successful!") {
          // Clear form
          _usernameController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
          _ageController.clear();
          _heightController.clear();
          _weightController.clear();

          // Show success and go to login
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result),
              backgroundColor: SageColors.moss,
              duration: const Duration(seconds: 3),
            ),
          );

          // Go back to login screen
          Navigator.pushReplacement(
            context,
            fadeRoute(const LoginScreen()),
          );
        } else {
          setState(() => _errorMessage = result);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result),
              backgroundColor: SageColors.clay,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SageColors.linen,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: SageColors.moss),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Reveal(
        size: RevealSize.large,
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tell us about yourself', style: SageText.headline()),
              const SizedBox(height: 6),
              Text(
                'Create your Sage Health account',
                style: TextStyle(color: SageColors.inkSoft, fontSize: 13.5),
              ),

              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SageColors.clay.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SageColors.clay.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: SageColors.clay, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: SageColors.clay),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: _clearError,
                        color: SageColors.clay,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),

              _sectionLabel('CREDENTIALS'),
              const SizedBox(height: 10),
              _buildTextField(
                controller: _usernameController,
                label: 'Username',
                icon: Icons.person,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Username is required';
                  }
                  if (value.length < 3) {
                    return 'Username must be at least 3 characters';
                  }
                  return null;
                },
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock,
                isPassword: true,
                obscure: _obscurePassword,
                onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _confirmPasswordController,
                label: 'Confirm password',
                icon: Icons.lock,
                isPassword: true,
                obscure: _obscureConfirm,
                onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 28),

              _sectionLabel('BODY METRICS'),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _ageController,
                      label: 'Age',
                      icon: Icons.calendar_today,
                      inputType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Age is required';
                        }
                        final age = int.tryParse(value);
                        if (age == null || age < 13 || age > 120) {
                          return 'Enter a valid age (13-120)';
                        }
                        return null;
                      },
                      onChanged: (_) => _clearError(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedGender,
                      decoration: _inputDecoration('Gender', Icons.wc),
                      items: ['Male', 'Female'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (newValue) =>
                          setState(() => _selectedGender = newValue!),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Gender is required';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _heightController,
                      label: 'Height (cm)',
                      icon: Icons.height,
                      inputType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Height is required';
                        }
                        final height = double.tryParse(value);
                        if (height == null || height < 50 || height > 250) {
                          return 'Enter valid height (50-250 cm)';
                        }
                        return null;
                      },
                      onChanged: (_) => _clearError(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      controller: _weightController,
                      label: 'Weight (kg)',
                      icon: Icons.monitor_weight,
                      inputType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Weight is required';
                        }
                        final weight = double.tryParse(value);
                        if (weight == null || weight < 20 || weight > 300) {
                          return 'Enter valid weight (20-300 kg)';
                        }
                        return null;
                      },
                      onChanged: (_) => _clearError(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              _sectionLabel('CHRONIC CONDITIONS (OPTIONAL)'),
              const SizedBox(height: 4),
              Text(
                'Select any that apply — leave blank if none.',
                style: TextStyle(color: SageColors.inkSoft, fontSize: 12),
              ),
              const SizedBox(height: 10),
              _buildConditionChips(),

              const SizedBox(height: 36),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SageColors.moss,
                    foregroundColor: SageColors.linen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: SageColors.linen, strokeWidth: 2),
                        )
                      : const Text(
                          'CREATE ACCOUNT',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: TextStyle(color: SageColors.inkSoft, fontSize: 13.5),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        fadeRoute(const LoginScreen()),
                      );
                    },
                    child: Text(
                      'Sign in',
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
        ),
        ), // SingleChildScrollView
      ), // Reveal
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: SageColors.inkSoft,
      ),
    );
  }

  Widget _buildConditionChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ChronicConditions.options.map((condition) {
        final selected = _selectedConditions.contains(condition);
        return FilterChip(
          label: Text(condition),
          selected: selected,
          onSelected: (value) {
            setState(() {
              if (value) {
                _selectedConditions.add(condition);
              } else {
                _selectedConditions.remove(condition);
              }
            });
          },
          showCheckmark: false,
          backgroundColor: SageColors.card,
          selectedColor: SageColors.moss.withValues(alpha: 0.15),
          side: BorderSide(color: selected ? SageColors.moss : SageColors.line),
          labelStyle: TextStyle(
            fontSize: 12.5,
            color: selected ? SageColors.moss : SageColors.inkSoft,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      }).toList(),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    TextInputType inputType = TextInputType.text,
    required String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword ? obscure : false,
      keyboardType: inputType,
      decoration: _inputDecoration(
        label,
        icon,
        suffix: isPassword
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: SageColors.inkSoft,
                  size: 19,
                ),
                onPressed: onToggleObscure,
              )
            : null,
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, {Widget? suffix}) {
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
}