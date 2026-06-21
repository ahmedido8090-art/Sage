import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/user_service.dart';
import '../theme/bella_theme.dart';
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
  List<String> _selectedDiseases = [];
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

  bool _isLoading = false;
  bool _isEditing = false;
  bool _showPasswordFields = false;
  String? _errorMessage;
  String? _successMessage;
  double _bmi = 0.0;
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
      _selectedDiseases = List.from(_currentUser!.chronicDiseases);
      _calculateBMI();
    }
  }

  void _calculateBMI() {
    if (_currentUser != null &&
        _currentUser!.height > 0 &&
        _currentUser!.weight > 0) {
      final heightInMeters = _currentUser!.height / 100;
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
    if (_bmi < 18.5) return BellaColors.warning;
    if (_bmi < 25) return BellaColors.success;
    if (_bmi < 30) return BellaColors.warning;
    return BellaColors.danger;
  }

  void _toggleDisease(String disease) {
    setState(() {
      if (_selectedDiseases.contains(disease)) {
        _selectedDiseases.remove(disease);
      } else {
        _selectedDiseases.add(disease);
      }
    });
  }

  void _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    final updatedUser = User(
      username: _usernameController.text.trim(),
      password: _currentUser!.password,
      age: int.tryParse(_ageController.text) ?? _currentUser!.age,
      gender: _selectedGender,
      height: double.tryParse(_heightController.text) ?? _currentUser!.height,
      weight: double.tryParse(_weightController.text) ?? _currentUser!.weight,
      dailyStepGoal: _currentUser!.dailyStepGoal,
      chronicDiseases: _selectedDiseases,
      waterGoal: _currentUser!.waterGoal,
      caloriesGoal: _currentUser!.caloriesGoal,
    );

    UserService().updateUserDetails(_currentUser!.username, updatedUser);

    setState(() {
      _isLoading = false;
      _isEditing = false;
      _currentUser = updatedUser;
      _calculateBMI();
      _successMessage = 'Profile updated successfully.';
    });

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')));
  }

  void _changePassword() {
    if (_currentPasswordController.text.isEmpty ||
        _newPasswordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill all password fields');
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'New passwords do not match');
      return;
    }
    if (_currentPasswordController.text != _currentUser!.password) {
      setState(() => _errorMessage = 'Current password is incorrect');
      return;
    }
    UserService()
        .updatePassword(_currentUser!.username, _newPasswordController.text);
    setState(() {
      _showPasswordFields = false;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _successMessage = 'Password changed successfully.';
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully.')));
  }

  void _logout() {
    UserService().logout();
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BellaColors.appGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Profile',
                          style: TextStyle(
                              color: BellaColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 28)),
                      const Spacer(),
                      if (!_isEditing)
                        IconButton(
                          icon: const Icon(Icons.edit,
                              color: BellaColors.primary),
                          onPressed: () => setState(() {
                            _isEditing = true;
                            _errorMessage = null;
                            _successMessage = null;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 104,
                          height: 104,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: BellaColors.primaryGradient),
                          child: const Icon(Icons.person,
                              size: 50, color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        Text(_currentUser!.username,
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: BellaColors.textPrimary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionCard(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text('Health Metrics',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: BellaColors.textPrimary)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                  color: _getBMIColor().withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(_getBMICategory(),
                                  style: TextStyle(
                                      color: _getBMIColor(),
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _metric(
                                'BMI', _bmi.toStringAsFixed(1), Icons.scale),
                            _metric(
                                'Height',
                                _currentUser!.height.toStringAsFixed(1),
                                Icons.height,
                                unit: 'cm'),
                            _metric(
                                'Weight',
                                _currentUser!.weight.toStringAsFixed(1),
                                Icons.monitor_weight,
                                unit: 'kg'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_errorMessage != null)
                    _messageCard(_errorMessage!, BellaColors.danger,
                        Icons.error_outline),
                  if (_successMessage != null)
                    _messageCard(_successMessage!, BellaColors.success,
                        Icons.check_circle_outline),
                  if (_errorMessage != null || _successMessage != null)
                    const SizedBox(height: 18),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Personal Information',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: BellaColors.textPrimary)),
                        const SizedBox(height: 20),
                        TextFormField(
                            controller: _usernameController,
                            enabled: false,
                            decoration: const InputDecoration(
                                labelText: 'Username',
                                prefixIcon: Icon(Icons.person))),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _ageController,
                          enabled: _isEditing,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Age',
                              prefixIcon: Icon(Icons.calendar_today)),
                          validator: (value) {
                            if (value == null || value.isEmpty)
                              return 'Please enter your age';
                            final age = int.tryParse(value);
                            return (age == null || age < 13 || age > 120)
                                ? 'Enter a valid age (13-120)'
                                : null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _selectedGender,
                          dropdownColor: BellaColors.surfaceAlt,
                          style:
                              const TextStyle(color: BellaColors.textPrimary),
                          decoration: const InputDecoration(
                              labelText: 'Gender', prefixIcon: Icon(Icons.wc)),
                          items: const [
                            DropdownMenuItem(
                                value: 'Male', child: Text('Male')),
                            DropdownMenuItem(
                                value: 'Female', child: Text('Female')),
                          ],
                          onChanged: _isEditing
                              ? (newValue) =>
                                  setState(() => _selectedGender = newValue!)
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _heightController,
                                enabled: _isEditing,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Height (cm)',
                                    prefixIcon: Icon(Icons.height)),
                                validator: (value) {
                                  if (value == null || value.isEmpty)
                                    return 'Height required';
                                  final height = double.tryParse(value);
                                  return (height == null ||
                                          height < 50 ||
                                          height > 250)
                                      ? '50-250 cm'
                                      : null;
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _weightController,
                                enabled: _isEditing,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Weight (kg)',
                                    prefixIcon: Icon(Icons.monitor_weight)),
                                validator: (value) {
                                  if (value == null || value.isEmpty)
                                    return 'Weight required';
                                  final weight = double.tryParse(value);
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
                        const Text(
                            'Chronic Conditions (optional, multi‑select)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: BellaColors.textPrimary)),
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
                                  onSelected: _isEditing
                                      ? (_) => _toggleDisease(disease)
                                      : null,
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Password Settings',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: BellaColors.textPrimary)),
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                  _showPasswordFields
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: BellaColors.primary),
                              onPressed: () => setState(() =>
                                  _showPasswordFields = !_showPasswordFields),
                            ),
                          ],
                        ),
                        if (_showPasswordFields) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                              controller: _currentPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                  labelText: 'Current Password',
                                  prefixIcon: Icon(Icons.lock))),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _newPasswordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                                labelText: 'New Password',
                                prefixIcon: Icon(Icons.lock_outline)),
                            validator: (value) => (value != null &&
                                    value.isNotEmpty &&
                                    value.length < 6)
                                ? 'Password must be at least 6 characters'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                  labelText: 'Confirm New Password',
                                  prefixIcon: Icon(Icons.lock_reset))),
                          const SizedBox(height: 16),
                          ElevatedButton(
                              onPressed: _changePassword,
                              child: const Text('Change Password')),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_isEditing)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() {
                              _isEditing = false;
                              _loadUserData();
                            }),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: BellaColors.danger,
                                side: const BorderSide(
                                    color: BellaColors.danger)),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _updateProfile,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 18),
                  OutlinedButton(
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: BellaColors.danger,
                        side: const BorderSide(color: BellaColors.danger)),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout, size: 18),
                          SizedBox(width: 8),
                          Text('Logout')
                        ]),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: BellaColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: BellaColors.divider)),
        child: child,
      );

  Widget _metric(String title, String value, IconData icon,
          {String unit = ''}) =>
      Column(
        children: [
          Icon(icon, size: 24, color: BellaColors.primary),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: BellaColors.textPrimary)),
          Text('$title ${unit.trim()}'.trim(),
              style: const TextStyle(
                  fontSize: 12, color: BellaColors.textSecondary)),
        ],
      );

  Widget _messageCard(String text, Color color, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.24))),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color)))
        ]),
      );
}
