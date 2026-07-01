// screens/profile_screen.dart
//
// Entrance is now Reveal (large) instead of a hand-rolled
// AnimationController, and the metric/condition/password cards are
// staggered via StaggerColumn — same primitives as every other screen.
import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/bella_service.dart';
import '../services/care_rules.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../utils/page_transitions.dart';
import '../widgets/animated_number.dart';
import '../widgets/reveal.dart';
import '../widgets/stagger.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  late TextEditingController _ageController;
  late TextEditingController _heightController;
  late TextEditingController _weightController;
  late TextEditingController _currentPasswordController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;

  String _selectedGender = 'Male';
  bool _isLoading = false;
  bool _isEditing = false;
  bool _showPasswordFields = false;
  String? _errorMessage;
  String? _successMessage;
  double _bmi = 0.0;
  final Set<String> _selectedConditions = {};

  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final userService = UserService();
    _currentUser = userService.currentUserObject;

    if (_currentUser != null) {
      _usernameController = TextEditingController(text: _currentUser!.username);
      _ageController =
          TextEditingController(text: _currentUser!.age.toString());
      _heightController =
          TextEditingController(text: _currentUser!.height.toStringAsFixed(1));
      _weightController =
          TextEditingController(text: _currentUser!.weight.toStringAsFixed(1));
      _currentPasswordController = TextEditingController();
      _newPasswordController = TextEditingController();
      _confirmPasswordController = TextEditingController();
      _selectedGender = _currentUser!.gender;

      _selectedConditions
        ..clear()
        ..addAll(_currentUser!.chronicDiseases);

      _calculateBMI();
    }
  }

  void _calculateBMI() {
    if (_currentUser != null &&
        _currentUser!.height > 0 &&
        _currentUser!.weight > 0) {
      double heightInMeters = _currentUser!.height / 100;
      _bmi = _currentUser!.weight / (heightInMeters * heightInMeters);
    }
  }

  String _getBMICategory() {
    if (_bmi < 18.5) return 'Underweight';
    if (_bmi < 25) return 'Normal weight';
    if (_bmi < 30) return 'Overweight';
    return 'Obese';
  }

  Color _getBMIColor() {
    if (_bmi < 18.5) return SageColors.amber;
    if (_bmi < 25) return SageColors.moss;
    if (_bmi < 30) return SageColors.amber;
    return SageColors.clay;
  }

  void _updateProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _successMessage = null;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      // Create updated user object
      final updatedUser = User(
        username: _usernameController.text.trim(),
        password: _currentUser!.password, // Keep current password
        age: int.tryParse(_ageController.text) ?? _currentUser!.age,
        gender: _selectedGender,
        height: double.tryParse(_heightController.text) ?? _currentUser!.height,
        weight: double.tryParse(_weightController.text) ?? _currentUser!.weight,
        chronicDiseases: _selectedConditions.toList(),
      );

      // Update user details
      UserService().updateUserDetails(_currentUser!.username, updatedUser);

      // Re-derive the water target from the updated weight/BMI and conditions
      // so PurePlate's hydration goal stays in sync without requiring the user
      // to manually re-visit that screen.
      final h = updatedUser.height / 100;
      final bmi = h > 0 ? updatedUser.weight / (h * h) : 22.5;
      final plan = CareRules.generatePlan(
        bmi: bmi,
        conditions: updatedUser.chronicDiseases,
      );
      final bella = BellaService();
      final currentTargets = bella.getTargets();
      // Only overwrite waterMl — leave calorieTarget and activity targets alone
      // so the user's PurePlate customisations aren't silently reset.
      await bella.saveTargets({
        ...currentTargets,
        'waterMl': plan.dailyWaterMlTarget,
      });

      setState(() {
        _isLoading = false;
        _isEditing = false;
        _currentUser = updatedUser;
        _calculateBMI();
        _successMessage = 'Profile updated successfully!';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated successfully!'),
          backgroundColor: SageColors.moss,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _changePassword() {
    if (_currentPasswordController.text.isEmpty ||
        _newPasswordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill all password fields';
      });
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'New passwords do not match';
      });
      return;
    }

    if (_currentPasswordController.text != _currentUser!.password) {
      setState(() {
        _errorMessage = 'Current password is incorrect';
      });
      return;
    }

    // Update password
    final userService = UserService();
    userService.updatePassword(
      _currentUser!.username,
      _newPasswordController.text,
    );

    setState(() {
      _showPasswordFields = false;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _successMessage = 'Password changed successfully!';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Password changed successfully!'),
        backgroundColor: SageColors.moss,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _logout() {
    UserService().logout();
    Navigator.pushAndRemoveUntil(
      context,
      fadeRoute(const LoginScreen()),
      (route) => false,
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon,
      {bool enabled = true}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: SageColors.inkSoft),
      prefixIcon: Icon(icon, color: SageColors.moss, size: 20),
      filled: true,
      fillColor:
          enabled ? SageColors.linen : SageColors.line.withValues(alpha: 0.3),
      enabled: enabled,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: SageColors.line),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: SageColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: SageColors.moss, width: 1.5),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: SageColors.card,
      border: Border.all(color: SageColors.line),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(4),
        topRight: Radius.circular(20),
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        backgroundColor: SageColors.linen,
        appBar: AppBar(
          title: const Text('Profile'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: CircularProgressIndicator(color: SageColors.moss),
        ),
      );
    }

    return Scaffold(
      backgroundColor: SageColors.linen,
      appBar: AppBar(
        title: Text('Profile', style: SageText.headline()),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: Icon(Icons.edit_outlined, color: SageColors.moss),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
        ],
      ),
      body: Reveal(
        size: RevealSize.large,
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header — avatar + username
              Center(
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SageColors.moss,
                  ),
                  child: Center(
                    child: Text(
                      _currentUser!.username.isNotEmpty
                          ? _currentUser!.username[0].toUpperCase()
                          : '?',
                      style: SageText.mono(
                          size: 36,
                          weight: FontWeight.w500,
                          color: SageColors.linen),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(_currentUser!.username, style: SageText.headline()),
              ),
              const SizedBox(height: 30),

              StaggerColumn(
                initialDelay: const Duration(milliseconds: 120),
                children: [

              // BMI Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Health metrics',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: _getBMIColor().withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _getBMICategory(),
                            style: TextStyle(
                                color: _getBMIColor(),
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMetricCard('BMI', _bmi, '',
                            Icons.scale_outlined),
                        _buildMetricCard(
                            'Height',
                            _currentUser!.height,
                            'cm',
                            Icons.height),
                        _buildMetricCard(
                            'Weight',
                            _currentUser!.weight,
                            'kg',
                            Icons.monitor_weight_outlined),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Messages
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SageColors.clay.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: SageColors.clay.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: SageColors.clay, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!,
                            style: TextStyle(color: SageColors.clay)),
                      ),
                    ],
                  ),
                ),
              if (_successMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SageColors.moss.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: SageColors.moss.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: SageColors.moss, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_successMessage!,
                            style: TextStyle(color: SageColors.moss)),
                      ),
                    ],
                  ),
                ),

              // Personal Information
              Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Personal information',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 18),

                    TextFormField(
                      controller: _usernameController,
                      decoration: _fieldDecoration(
                          'Username', Icons.person_outline,
                          enabled: false),
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _ageController,
                      decoration: _fieldDecoration(
                          'Age', Icons.calendar_today_outlined,
                          enabled: _isEditing),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your age';
                        }
                        final age = int.tryParse(value);
                        if (age == null || age < 13 || age > 120) {
                          return 'Enter a valid age (13-120)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    DropdownButtonFormField<String>(
                      initialValue: _selectedGender,
                      decoration: _fieldDecoration('Gender', Icons.wc_outlined,
                          enabled: _isEditing),
                      items: ['Male', 'Female', 'Other'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: _isEditing
                          ? (newValue) {
                              setState(() {
                                _selectedGender = newValue!;
                              });
                            }
                          : null,
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _heightController,
                            decoration: _fieldDecoration(
                                'Height (cm)', Icons.height,
                                enabled: _isEditing),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter height';
                              }
                              final height = double.tryParse(value);
                              if (height == null ||
                                  height < 50 ||
                                  height > 250) {
                                return 'Enter valid height (50-250 cm)';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextFormField(
                            controller: _weightController,
                            decoration: _fieldDecoration(
                                'Weight (kg)', Icons.monitor_weight_outlined,
                                enabled: _isEditing),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter weight';
                              }
                              final weight = double.tryParse(value);
                              if (weight == null ||
                                  weight < 20 ||
                                  weight > 300) {
                                return 'Enter valid weight (20-300 kg)';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Chronic Conditions
              Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chronic conditions',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isEditing
                          ? 'Tap to add or remove a condition.'
                          : (_selectedConditions.isEmpty
                              ? 'None on file'
                              : '${_selectedConditions.length} on file'),
                      style: TextStyle(color: SageColors.inkSoft, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    _buildConditionChips(),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Appearance — dark mode toggle
              Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: ValueListenableBuilder<bool>(
                  valueListenable: ThemeController.isDark,
                  builder: (context, isDark, _) {
                    return Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: SageColors.moss.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isDark
                                ? Icons.dark_mode_outlined
                                : Icons.light_mode_outlined,
                            size: 18,
                            color: SageColors.moss,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Dark mode',
                                  style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                isDark
                                    ? 'On — easier on the eyes at night'
                                    : 'Off — bright and clean',
                                style: TextStyle(
                                    fontSize: 11.5, color: SageColors.inkSoft),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isDark,
                          activeThumbColor: SageColors.moss,
                          onChanged: (value) => ThemeController.setDark(value),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Password Change
              Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Password settings',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          icon: Icon(
                            _showPasswordFields
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: SageColors.moss,
                          ),
                          onPressed: () {
                            setState(() {
                              _showPasswordFields = !_showPasswordFields;
                            });
                          },
                        ),
                      ],
                    ),
                    if (_showPasswordFields) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _currentPasswordController,
                        obscureText: true,
                        decoration: _fieldDecoration(
                            'Current password', Icons.lock_outline),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _newPasswordController,
                        obscureText: true,
                        decoration: _fieldDecoration(
                            'New password', Icons.lock_outline),
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        decoration: _fieldDecoration(
                            'Confirm new password', Icons.lock_reset_outlined),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _changePassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SageColors.moss,
                            foregroundColor: SageColors.linen,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            elevation: 0,
                          ),
                          child: const Text('Change password'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Action Buttons
              if (_isEditing)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _isEditing = false;
                            _loadUserData();
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SageColors.clay,
                          side: BorderSide(color: SageColors.clay),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _updateProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SageColors.moss,
                          foregroundColor: SageColors.linen,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: SageColors.linen, strokeWidth: 2),
                              )
                            : const Text('Save changes'),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 18),

              // Logout Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _logout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SageColors.clay,
                    side: BorderSide(color: SageColors.clay),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout, size: 18),
                      SizedBox(width: 8),
                      Text('Logout'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              ], // end StaggerColumn children
              ), // end StaggerColumn
            ], // Column children
          ), // Column
        ), // Form
      ), // SingleChildScrollView
      ), // Reveal
    ); // Scaffold
  }

  Widget _buildConditionChips() {
    if (!_isEditing) {
      if (_selectedConditions.isEmpty) return const SizedBox.shrink();
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _selectedConditions.map((condition) {
          return Chip(
            label: Text(condition),
            backgroundColor: SageColors.moss.withValues(alpha: 0.12),
            labelStyle: TextStyle(
                fontSize: 12.5,
                color: SageColors.moss,
                fontWeight: FontWeight.w600),
            side: BorderSide(color: SageColors.moss.withValues(alpha: 0.3)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          );
        }).toList(),
      );
    }

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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      }).toList(),
    );
  }

  Widget _buildMetricCard(
      String title, double value, String unit, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 22, color: SageColors.moss),
        const SizedBox(height: 8),
        AnimatedDouble(
          value: value,
          formatter: (v) => v.toStringAsFixed(1),
          style: SageText.mono(size: 19),
        ),
        const SizedBox(height: 2),
        Text(
          '$title $unit',
          style: TextStyle(fontSize: 11.5, color: SageColors.inkSoft),
        ),
      ],
    );
  }
}