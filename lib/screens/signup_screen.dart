import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/user_service.dart';
import '../theme/bella_theme.dart';
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
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  // Expanded chronic diseases list (20 conditions)
  final List<String> _availableDiseases = [
    'Hypertension',
    'Diabetes (Type 2)',
    'Asthma',
    'Anemia',
    'High Cholesterol',
    'Arthritis',
    'Osteoporosis',
    'Chronic Kidney Disease',
    'Depression',
    'Anxiety Disorder',
    'Migraine',
    'Thyroid Disorder (Hypothyroidism)',
    'Gout',
    'IBS (Irritable Bowel Syndrome)',
    'GERD (Acid Reflux)',
    'COPD',
    'Psoriasis',
    'Eczema',
    'Fibromyalgia',
    'Sleep Apnea'
  ];
  final List<String> _selectedDiseases = [];

  void _toggleDisease(String disease) {
    setState(() {
      if (_selectedDiseases.contains(disease)) {
        _selectedDiseases.remove(disease);
      } else {
        _selectedDiseases.add(disease);
      }
    });
  }

  void _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 800));

    final user = User(
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      age: int.tryParse(_ageController.text) ?? 0,
      gender: _selectedGender,
      height: double.tryParse(_heightController.text) ?? 0.0,
      weight: double.tryParse(_weightController.text) ?? 0.0,
      chronicDiseases: List.from(_selectedDiseases),
    );

    final result = UserService().register(user);

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result == 'Registration successful!') {
      _usernameController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _ageController.clear();
      _heightController.clear();
      _weightController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your Bella account is ready.')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } else {
      setState(() => _errorMessage = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result), backgroundColor: BellaColors.danger),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: BellaColors.surface.withOpacity(0.96),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: BellaColors.divider),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back,
                              color: BellaColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text('Create your Bella account',
                            style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        Text(
                          'Set up your profile, body metrics, and wellness preferences.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: BellaColors.danger.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: BellaColors.danger.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: BellaColors.danger, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(_errorMessage!,
                                        style: const TextStyle(
                                            color: BellaColors.danger))),
                                IconButton(
                                  onPressed: _clearError,
                                  icon: const Icon(Icons.close,
                                      size: 18, color: BellaColors.danger),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        _sectionLabel('Credentials'),
                        const SizedBox(height: 10),
                        _buildTextField(
                          controller: _usernameController,
                          label: 'Username',
                          icon: Icons.person_outline,
                          validator: (v) => v == null || v.isEmpty
                              ? 'Username is required'
                              : (v.length < 3
                                  ? 'Username must be at least 3 characters'
                                  : null),
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'Password',
                          icon: Icons.lock_outline,
                          isPassword: true,
                          obscureText: _obscurePassword,
                          onTogglePassword: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Password is required'
                              : (v.length < 6
                                  ? 'Password must be at least 6 characters'
                                  : null),
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _confirmPasswordController,
                          label: 'Confirm Password',
                          icon: Icons.lock_reset,
                          isPassword: true,
                          obscureText: _obscureConfirmPassword,
                          onTogglePassword: () => setState(() =>
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Please confirm your password'
                              : (v != _passwordController.text
                                  ? 'Passwords do not match'
                                  : null),
                        ),
                        const SizedBox(height: 24),
                        _sectionLabel('Body Metrics'),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _ageController,
                                label: 'Age',
                                icon: Icons.calendar_today_outlined,
                                inputType: TextInputType.number,
                                validator: (v) {
                                  if (v == null || v.isEmpty)
                                    return 'Age is required';
                                  final age = int.tryParse(v);
                                  return (age == null || age < 13 || age > 120)
                                      ? 'Enter a valid age'
                                      : null;
                                },
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedGender,
                                dropdownColor: BellaColors.surfaceAlt,
                                style: const TextStyle(
                                    color: BellaColors.textPrimary),
                                decoration: const InputDecoration(
                                  labelText: 'Gender',
                                  prefixIcon: Icon(Icons.wc),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'Male', child: Text('Male')),
                                  DropdownMenuItem(
                                      value: 'Female', child: Text('Female')),
                                ],
                                onChanged: (value) =>
                                    setState(() => _selectedGender = value!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _heightController,
                                label: 'Height (cm)',
                                icon: Icons.height,
                                inputType: TextInputType.number,
                                validator: (v) {
                                  if (v == null || v.isEmpty)
                                    return 'Height required';
                                  final height = double.tryParse(v);
                                  return (height == null ||
                                          height < 50 ||
                                          height > 250)
                                      ? '50-250 cm'
                                      : null;
                                },
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _buildTextField(
                                controller: _weightController,
                                label: 'Weight (kg)',
                                icon: Icons.monitor_weight_outlined,
                                inputType: TextInputType.number,
                                validator: (v) {
                                  if (v == null || v.isEmpty)
                                    return 'Weight required';
                                  final weight = double.tryParse(v);
                                  return (weight == null ||
                                          weight < 20 ||
                                          weight > 300)
                                      ? '20-300 kg'
                                      : null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _sectionLabel(
                            'Chronic Diseases (optional, multi‑select)'),
                        const SizedBox(height: 8),
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: BellaColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: BellaColors.divider),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _availableDiseases.map((disease) {
                                final isSelected =
                                    _selectedDiseases.contains(disease);
                                return FilterChip(
                                  label: Text(disease),
                                  selected: isSelected,
                                  onSelected: (_) => _toggleDisease(disease),
                                  backgroundColor: BellaColors.surface,
                                  selectedColor:
                                      BellaColors.primary.withOpacity(0.3),
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? BellaColors.primary
                                        : BellaColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleSignup,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.2))
                              : const Text('CREATE ACCOUNT'),
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: Wrap(
                            children: [
                              Text('Already have an account? ',
                                  style: theme.textTheme.bodyMedium),
                              GestureDetector(
                                onTap: () => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const LoginScreen()),
                                ),
                                child: const Text(
                                  'Sign In',
                                  style: TextStyle(
                                      color: BellaColors.primary,
                                      fontWeight: FontWeight.w700),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: BellaColors.primary,
            letterSpacing: 0.2),
      );

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onTogglePassword,
    TextInputType inputType = TextInputType.text,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword ? obscureText : false,
      keyboardType: inputType,
      onChanged: (_) => _clearError(),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: isPassword
            ? IconButton(
                onPressed: onTogglePassword,
                icon: Icon(
                    obscureText ? Icons.visibility_off : Icons.visibility,
                    color: BellaColors.textMuted),
              )
            : null,
      ),
      validator: validator,
    );
  }
}
