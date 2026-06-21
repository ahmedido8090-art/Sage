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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _loadGoalsAndRecommendations();
    await _loadTodayData();
  }

  Future<void> _loadGoalsAndRecommendations() async {
    final user = _userService.currentUserObject;
    if (user != null) {
      setState(() {
        _userWaterGoal = user.waterGoal;
        _userCaloriesGoal = user.caloriesGoal;
      });
    }
    await _updateRecommendations();
  }

  Future<void> _updateRecommendations() async {
    final user = _userService.currentUserObject;
    if (user == null) return;

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

    // Chronic disease advice
    List<String> chronicAdviceList = [];
    if (user.hasChronicDisease('Hypertension')) {
      chronicAdviceList
          .add('❤️ Hypertension: Limit sodium, stay hydrated, monitor BP.');
    }
    if (user.hasChronicDisease('Diabetes')) {
      chronicAdviceList.add(
          '🩸 Diabetes: Spread carbs evenly, choose low-GI foods, monitor glucose.');
    }
    if (user.hasChronicDisease('Asthma')) {
      chronicAdviceList.add(
          '🌬️ Asthma: Maintain healthy weight, avoid triggers, practice breathing exercises.');
    }
    if (user.hasChronicDisease('Anemia')) {
      chronicAdviceList.add(
          '🩸 Anemia: Eat iron-rich foods (spinach, red meat) with vitamin C.');
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

    // Suggested goals (BMR + activity + BMI + chronic adjustments)
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
    if (user.hasChronicDisease('Diabetes')) recommendedWater += 500;
    if (user.hasChronicDisease('Hypertension')) recommendedWater += 400;
    recommendedWater = recommendedWater.clamp(1800, 4000);

    setState(() {
      _suggestedWaterGoal = recommendedWater;
      _suggestedCalorieGoal = recommendedCal;
    });
  }

  Future<void> _loadTodayData() async {
    final today = await _storage.getTodayNutrition(userId: '');
    setState(() {
      _todayWater = today['water']!;
      _todayCalories = today['calories']!;
      _todayMeals = today['meals']!;
    });
    await _updateRecommendations();
  }

  Future<void> _saveLog() async {
    final hasWater = _waterController.text.isNotEmpty;
    final hasCalories = _caloriesController.text.isNotEmpty;
    final hasMeals = _mealsController.text.isNotEmpty;
    if (!hasWater && !hasCalories && !hasMeals) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log at least one item')));
      return;
    }
    setState(() => _isSaving = true);
    await _storage.saveNutritionLog(
      waterMl: hasWater ? int.tryParse(_waterController.text) : null,
      calories: hasCalories ? int.tryParse(_caloriesController.text) : null,
      meals: hasMeals ? int.tryParse(_mealsController.text) : null,
      timestamp: DateTime.now(),
      userId: '',
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
            decoration: const InputDecoration(labelText: 'Daily water (ml)')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final newGoal = int.tryParse(controller.text);
              if (newGoal != null && newGoal >= 500)
                Navigator.pop(ctx, newGoal);
              else
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(const SnackBar(content: Text('≥500 ml')));
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
            decoration:
                const InputDecoration(labelText: 'Daily calories (kcal)')),
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
                          prefixIcon: Icon(Icons.water_drop)),
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
                          prefixIcon: Icon(Icons.restaurant)),
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
                          prefixIcon: Icon(Icons.fastfood)),
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
                            : const Text('ADD TO TODAY')),
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
          border: Border.all(color: BellaColors.divider)),
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
                      onEdit: _editWaterGoal)),
              const SizedBox(width: 12),
              Expanded(
                  child: _progressTile(
                      icon: Icons.restaurant,
                      label: 'Calories',
                      value: '$_todayCalories / $_userCaloriesGoal kcal',
                      percent: calPercent,
                      color: BellaColors.warning,
                      onEdit: _editCalorieGoal)),
            ],
          ),
          const SizedBox(height: 12),
          _progressTile(
              icon: Icons.fastfood,
              label: 'Meals',
              value: '$_todayMeals meals today',
              percent: _todayMeals / 4.0,
              color: BellaColors.success,
              onEdit: null),
        ],
      ),
    );
  }

  Widget _progressTile(
      {required IconData icon,
      required String label,
      required String value,
      required double percent,
      required Color color,
      VoidCallback? onEdit}) {
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
                  constraints: const BoxConstraints()),
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
                minHeight: 6)),
      ],
    );
  }

  Widget _buildRecommendationsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: BellaColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BellaColors.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.auto_awesome, color: BellaColors.primary, size: 20),
            SizedBox(width: 8),
            Text('Personalized AI Recommendations',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
          ]),
          const SizedBox(height: 12),
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
                borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Suggested daily goals:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      OutlinedButton(
                          onPressed: _applySuggestedGoals,
                          child: const Text('Apply'),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(70, 30),
                              padding: EdgeInsets.zero))
                    ]),
                const SizedBox(height: 6),
                Text('💧 $_suggestedWaterGoal ml water',
                    style: const TextStyle(fontSize: 14)),
                Text('🍽️ $_suggestedCalorieGoal kcal',
                    style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
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
            child: Icon(icon, size: 18, color: color)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(message, style: const TextStyle(fontSize: 13))
        ])),
      ],
    );
  }
}
