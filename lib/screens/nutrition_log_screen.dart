import 'package:bella/models/user.dart';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/data_storage_service.dart';
import '../services/user_service.dart';
import '../theme/bella_theme.dart';

class NutritionLogScreen extends StatefulWidget {
  const NutritionLogScreen({super.key});

  @override
  State<NutritionLogScreen> createState() => _NutritionLogScreenState();
}

class _NutritionLogScreenState extends State<NutritionLogScreen> {
  final _formKey = GlobalKey<FormState>();
  final _waterController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _mealsController = TextEditingController();

  final DataStorageService _storage = DataStorageService();
  final UserService _userService = UserService();
  bool _isSaving = false;

  int _userWaterGoal = 2500;
  int _userCaloriesGoal = 2000;
  int _todayWater = 0;
  int _todayCalories = 0;
  int _todayMeals = 0;

  String _waterAdvice = '';
  String _calorieAdvice = '';
  String _chronicAdvice = '';
  String _bmiAdvice = '';
  int _suggestedWaterGoal = 2500;
  int _suggestedCalorieGoal = 2000;
  bool _hasAllChronicDiseases = false;
  String? _currentUserId;

  // Complete list of 20 chronic diseases
  final List<String> _allDiseases = [
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

  // Map of chronic disease to nutrition advice
  final Map<String, String> _diseaseNutritionAdvice = {
    'Hypertension':
        '❤️ Limit sodium, increase potassium (bananas, spinach), stay hydrated.',
    'Diabetes (Type 2)':
        '🩸 Spread carbs evenly, choose low-GI foods, monitor portion sizes.',
    'Asthma':
        '🌬️ Include anti-inflammatory foods (leafy greens, berries), stay hydrated.',
    'Anemia':
        '🩸 Eat iron-rich foods (spinach, red meat) with vitamin C (citrus).',
    'High Cholesterol':
        '🥑 Reduce saturated fats, increase fiber (oats, beans), eat omega-3s.',
    'Arthritis': '🦴 Anti-inflammatory diet: turmeric, ginger, fatty fish.',
    'Osteoporosis': '🦴 Calcium-rich foods (dairy, kale) and vitamin D.',
    'Chronic Kidney Disease':
        '🥔 Monitor protein, potassium, and phosphorus; consult nephrologist.',
    'Depression':
        '😊 Eat omega-3s, whole grains, and maintain regular meal times.',
    'Anxiety Disorder':
        '🧘 Limit caffeine, eat magnesium-rich foods (nuts, seeds).',
    'Migraine':
        '🤕 Avoid triggers (aged cheese, wine), stay hydrated, eat regularly.',
    'Thyroid Disorder (Hypothyroidism)':
        '🍣 Ensure iodine and selenium (fish, nuts), avoid goitrogens raw.',
    'Gout': '🦶 Limit purines (red meat, seafood), drink plenty of water.',
    'IBS (Irritable Bowel Syndrome)':
        '🥑 Low-FODMAP diet, small frequent meals, avoid gas-forming foods.',
    'GERD (Acid Reflux)':
        '🔥 Avoid spicy, fatty foods; eat smaller meals, no late-night eating.',
    'COPD': '🫁 Protein-rich diet, small frequent meals to avoid bloating.',
    'Psoriasis': '🌿 Anti-inflammatory diet (fish, veggies), reduce alcohol.',
    'Eczema': '💧 Avoid food triggers, increase omega-3s, stay hydrated.',
    'Fibromyalgia':
        '😴 Balanced diet, avoid processed foods, magnesium supplementation.',
    'Sleep Apnea':
        '😴 Weight management if overweight, avoid alcohol before bed.',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = _userService.currentUserObject;
    if (user != null) {
      _currentUserId = user.username;
      await _loadGoalsAndRecommendations();
      await _loadTodayData();
    }
  }

  Future<void> _loadGoalsAndRecommendations() async {
    final user = _userService.currentUserObject;
    if (user == null || _currentUserId == null) return;

    setState(() {
      _userWaterGoal = user.waterGoal;
      _userCaloriesGoal = user.caloriesGoal;
      // Check if user has ALL 20 chronic diseases
      _hasAllChronicDiseases = _allDiseases
          .every((disease) => user.chronicDiseases.contains(disease));
    });
    await _updateRecommendations();
  }

  Future<void> _updateRecommendations() async {
    final user = _userService.currentUserObject;
    if (user == null || _currentUserId == null) return;

    // Special case: user has all chronic diseases
    if (_hasAllChronicDiseases) {
      setState(() {
        _chronicAdvice =
            '⚠️ You have selected all chronic conditions. Please go to **Sage Hospital** for full treatment.';
        _waterAdvice = 'Consult with a specialist about your hydration needs.';
        _calorieAdvice =
            'A medical professional should design your dietary plan.';
        _bmiAdvice = 'Comprehensive medical evaluation recommended.';
      });
      return;
    }

    // Get average daily steps
    int avgSteps = 0;
    try {
      final logs = await _storage.getBandData(daysBack: 7);
      if (logs.isNotEmpty) {
        avgSteps = logs.map((e) => e['steps'] as int).reduce((a, b) => a + b) ~/
            logs.length;
      }
    } catch (_) {}

    // Water advice
    if (_todayWater >= _userWaterGoal) {
      _waterAdvice =
          '✅ Great! You reached your daily water goal of $_userWaterGoal ml.';
    } else {
      final remaining = _userWaterGoal - _todayWater;
      _waterAdvice =
          '💧 You still need $remaining ml to reach your goal of $_userWaterGoal ml.';
    }

    // Calorie advice
    if (_todayCalories >= _userCaloriesGoal) {
      _calorieAdvice =
          '✅ You reached your daily calorie goal of $_userCaloriesGoal kcal.';
    } else {
      final remaining = _userCaloriesGoal - _todayCalories;
      _calorieAdvice =
          '🍽️ You have $remaining kcal left to reach your goal of $_userCaloriesGoal kcal.';
    }

    // Chronic disease advice (build from map)
    List<String> chronicAdviceList = [];
    for (final disease in user.chronicDiseases) {
      if (_diseaseNutritionAdvice.containsKey(disease)) {
        chronicAdviceList.add(_diseaseNutritionAdvice[disease]!);
      }
    }
    if (chronicAdviceList.isEmpty) {
      chronicAdviceList
          .add('No chronic conditions reported. Keep up the healthy habits!');
    }
    _chronicAdvice = chronicAdviceList.join('  •  ');

    // BMI advice
    final bmi = user.bmi;
    if (bmi < 18.5) {
      _bmiAdvice =
          '📉 BMI ${bmi.toStringAsFixed(1)} (Underweight) – Nutrient‑dense, calorie‑rich foods.';
    } else if (bmi < 25) {
      _bmiAdvice =
          '✅ BMI ${bmi.toStringAsFixed(1)} (Normal) – Maintain balance.';
    } else if (bmi < 30) {
      _bmiAdvice =
          '⚠️ BMI ${bmi.toStringAsFixed(1)} (Overweight) – Portion control and regular activity.';
    } else {
      _bmiAdvice =
          '⚠️ BMI ${bmi.toStringAsFixed(1)} (Obese) – Consult a professional for a sustainable plan.';
    }

    // Suggested goals (based on BMR, activity, BMI, and chronic adjustments)
    double bmr;
    if (user.gender == 'Male') {
      bmr = 10 * user.weight + 6.25 * user.height - 5 * user.age + 5;
    } else {
      bmr = 10 * user.weight + 6.25 * user.height - 5 * user.age - 161;
    }
    double activityMultiplier = avgSteps > 10000
        ? 1.55
        : (avgSteps > 7000 ? 1.375 : (avgSteps > 4000 ? 1.2 : 1.2));
    int maintenance = (bmr * activityMultiplier).round();
    int recommendedCal = maintenance;
    if (bmi < 18.5)
      recommendedCal = maintenance + 250;
    else if (bmi >= 30)
      recommendedCal = maintenance - 500;
    else if (bmi >= 25)
      recommendedCal = maintenance - 300;
    else
      recommendedCal = maintenance - 100;
    recommendedCal = recommendedCal.clamp(1500, 3000);

    int recommendedWater = (user.weight * 33).round();
    if (avgSteps > 8000) recommendedWater += 400;
    if (bmi > 30) recommendedWater += 300;
    if (user.hasChronicDisease('Diabetes (Type 2)')) recommendedWater += 500;
    if (user.hasChronicDisease('Hypertension')) recommendedWater += 400;
    recommendedWater = recommendedWater.clamp(1800, 4000);

    setState(() {
      _suggestedWaterGoal = recommendedWater;
      _suggestedCalorieGoal = recommendedCal;
    });
  }

  Future<void> _loadTodayData() async {
    if (_currentUserId == null) return;
    final today = await _storage.getTodayNutrition(userId: _currentUserId!);
    setState(() {
      _todayWater = today['water']!;
      _todayCalories = today['calories']!;
      _todayMeals = today['meals']!;
    });
    await _updateRecommendations();
  }

  Future<void> _saveLog() async {
    if (_currentUserId == null) return;
    final hasWater = _waterController.text.isNotEmpty;
    final hasCalories = _caloriesController.text.isNotEmpty;
    final hasMeals = _mealsController.text.isNotEmpty;
    if (!hasWater && !hasCalories && !hasMeals) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please log at least one item: water, calories, or meals.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    await _storage.saveNutritionLog(
      userId: _currentUserId!,
      waterMl: hasWater ? int.tryParse(_waterController.text) : null,
      calories: hasCalories ? int.tryParse(_caloriesController.text) : null,
      meals: hasMeals ? int.tryParse(_mealsController.text) : null,
      timestamp: DateTime.now(),
    );
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Log saved!')));
    _waterController.clear();
    _caloriesController.clear();
    _mealsController.clear();
    await _loadTodayData();
  }

  void _editWaterGoal() async {
    final user = _userService.currentUserObject;
    if (user == null) return;
    final controller = TextEditingController(text: _userWaterGoal.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Water Goal'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Daily water (ml)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final newGoal = int.tryParse(controller.text);
              if (newGoal != null && newGoal >= 500)
                Navigator.pop(ctx, newGoal);
              else {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(const SnackBar(content: Text('≥500 ml')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result != _userWaterGoal) {
      final updatedUser = User(
        username: user.username,
        password: user.password,
        age: user.age,
        gender: user.gender,
        height: user.height,
        weight: user.weight,
        dailyStepGoal: user.dailyStepGoal,
        chronicDiseases: user.chronicDiseases,
        waterGoal: result,
        caloriesGoal: user.caloriesGoal,
      );
      _userService.updateUserDetails(user.username, updatedUser);
      setState(() => _userWaterGoal = result);
      await _updateRecommendations();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Water goal updated')));
    }
  }

  void _editCalorieGoal() async {
    final user = _userService.currentUserObject;
    if (user == null) return;
    final controller =
        TextEditingController(text: _userCaloriesGoal.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Calorie Goal'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Daily calories (kcal)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final newGoal = int.tryParse(controller.text);
              if (newGoal != null && newGoal >= 1000)
                Navigator.pop(ctx, newGoal);
              else
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(const SnackBar(content: Text('≥1000 kcal')));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result != _userCaloriesGoal) {
      final updatedUser = User(
        username: user.username,
        password: user.password,
        age: user.age,
        gender: user.gender,
        height: user.height,
        weight: user.weight,
        dailyStepGoal: user.dailyStepGoal,
        chronicDiseases: user.chronicDiseases,
        waterGoal: user.waterGoal,
        caloriesGoal: result,
      );
      _userService.updateUserDetails(user.username, updatedUser);
      setState(() => _userCaloriesGoal = result);
      await _updateRecommendations();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Calorie goal updated')));
    }
  }

  void _applySuggestedGoals() async {
    final user = _userService.currentUserObject;
    if (user == null) return;
    final updatedUser = User(
      username: user.username,
      password: user.password,
      age: user.age,
      gender: user.gender,
      height: user.height,
      weight: user.weight,
      dailyStepGoal: user.dailyStepGoal,
      chronicDiseases: user.chronicDiseases,
      waterGoal: _suggestedWaterGoal,
      caloriesGoal: _suggestedCalorieGoal,
    );
    _userService.updateUserDetails(user.username, updatedUser);
    setState(() {
      _userWaterGoal = _suggestedWaterGoal;
      _userCaloriesGoal = _suggestedCalorieGoal;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Goals updated to recommendations!')));
    await _loadTodayData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nutriva Tracker')),
      body: Container(
        decoration: const BoxDecoration(gradient: BellaColors.appGradient),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Today\'s Progress',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildProgressCard(),
              const SizedBox(height: 24),
              const Text('Log Nutrition',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Fill any fields you want – leave empty to skip.',
                  style: TextStyle(color: BellaColors.textSecondary)),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _waterController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Water (ml) – optional',
                        prefixIcon: Icon(Icons.water_drop),
                      ),
                      validator: (v) =>
                          (v != null && v.isNotEmpty && int.tryParse(v) == null)
                              ? 'Enter a number'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _caloriesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Calories (kcal) – optional',
                        prefixIcon: Icon(Icons.restaurant),
                      ),
                      validator: (v) =>
                          (v != null && v.isNotEmpty && int.tryParse(v) == null)
                              ? 'Enter a number'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _mealsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Number of meals – optional',
                        prefixIcon: Icon(Icons.fastfood),
                      ),
                      validator: (v) =>
                          (v != null && v.isNotEmpty && int.tryParse(v) == null)
                              ? 'Enter a number'
                              : null,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveLog,
                      child: _isSaving
                          ? const CircularProgressIndicator()
                          : const Text('ADD TO TODAY'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildRecommendationsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    final waterPercent = _userWaterGoal > 0
        ? (_todayWater / _userWaterGoal).clamp(0.0, 1.0)
        : 0.0;
    final calPercent = _userCaloriesGoal > 0
        ? (_todayCalories / _userCaloriesGoal).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BellaColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BellaColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _progressTile(
                  icon: Icons.water_drop,
                  label: 'Water',
                  value: '$_todayWater / $_userWaterGoal ml',
                  percent: waterPercent,
                  color: BellaColors.secondary,
                  onEdit: _editWaterGoal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _progressTile(
                  icon: Icons.restaurant,
                  label: 'Calories',
                  value: '$_todayCalories / $_userCaloriesGoal kcal',
                  percent: calPercent,
                  color: BellaColors.warning,
                  onEdit: _editCalorieGoal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _progressTile(
            icon: Icons.fastfood,
            label: 'Meals',
            value: '$_todayMeals meals today',
            percent: _todayMeals / 4.0,
            color: BellaColors.success,
            onEdit: null,
          ),
        ],
      ),
    );
  }

  Widget _progressTile({
    required IconData icon,
    required String label,
    required String value,
    required double percent,
    required Color color,
    VoidCallback? onEdit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (onEdit != null)
              IconButton(
                icon: Icon(Icons.edit,
                    size: 16, color: BellaColors.textSecondary),
                onPressed: onEdit,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: color.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BellaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BellaColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: BellaColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Personalized AI Recommendations',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_hasAllChronicDiseases)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BellaColors.danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_hospital, color: BellaColors.danger),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _chronicAdvice,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: BellaColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _adviceTile(Icons.water_drop, 'Hydration', _waterAdvice,
                BellaColors.secondary),
            const SizedBox(height: 8),
            _adviceTile(Icons.restaurant, 'Calories', _calorieAdvice,
                BellaColors.warning),
            const SizedBox(height: 8),
            _adviceTile(Icons.health_and_safety, 'Chronic Conditions',
                _chronicAdvice, BellaColors.danger),
            const SizedBox(height: 8),
            _adviceTile(Icons.monitor_weight, 'BMI Analysis', _bmiAdvice,
                BellaColors.primary),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: BellaColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Suggested daily goals:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      OutlinedButton(
                        onPressed: _applySuggestedGoals,
                        child: const Text('Apply'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(70, 30),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('💧 $_suggestedWaterGoal ml water',
                      style: const TextStyle(fontSize: 14)),
                  Text('🍽️ $_suggestedCalorieGoal kcal',
                      style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _adviceTile(IconData icon, String title, String message, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 2),
              Text(message, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}
