import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/achievements_service.dart';
import '../services/bluetooth_service.dart';
import '../services/user_service.dart';
import '../theme/bella_theme.dart';
import '../widgets/smart_recommendations.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late User _currentUser;
  late int _stepGoal;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final userService = UserService();
    if (userService.currentUserObject != null) {
      _currentUser = userService.currentUserObject!;
      _stepGoal = _currentUser.dailyStepGoal;
    } else {
      _currentUser = User(
        username: 'Guest',
        password: '',
        age: 25,
        gender: 'N/A',
        height: 170,
        weight: 70,
        dailyStepGoal: 6000,
      );
      _stepGoal = 6000;
    }
  }

  void _editStepGoal() {
    final controller = TextEditingController(text: _stepGoal.toString());

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set Daily Step Goal'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Target Steps',
            hintText: 'e.g., 8000',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newGoal = int.tryParse(controller.text);
              if (newGoal != null && newGoal > 0) {
                setState(() {
                  _stepGoal = newGoal;
                  final updatedUser = User(
                    username: _currentUser.username,
                    password: _currentUser.password,
                    age: _currentUser.age,
                    gender: _currentUser.gender,
                    height: _currentUser.height,
                    weight: _currentUser.weight,
                    dailyStepGoal: newGoal,
                    chronicDiseases: _currentUser.chronicDiseases,
                    waterGoal: _currentUser.waterGoal,
                    caloriesGoal: _currentUser.caloriesGoal,
                  );
                  _currentUser = updatedUser;
                  UserService().updateUserDetails(
                    _currentUser.username,
                    updatedUser,
                  );
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BellaColors.appGradient),
        child: StreamBuilder(
          stream: BluetoothService.instance.dataStream,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final currentSteps = data?.steps ?? 0;
            final currentHr = data?.heartRate ?? 0;
            final currentCals = data?.calories ?? 0.0;

            final achievements = AchievementsService()
                .getAchievements(currentSteps, currentCals);

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 8),
                const Text(
                  'Your Insights',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: BellaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Progress, habits, and recommendations tailored to your current rhythm.',
                  style: TextStyle(
                    color: BellaColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _editStepGoal,
                  child: _buildGoalProgress(currentSteps),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Personal Analytics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: BellaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildAnalyticsGrid(currentSteps, currentHr, currentCals),
                const SizedBox(height: 24),
                const Text(
                  'Personalized Health Tips',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: BellaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                SmartRecommendations(
                  heartRate: currentHr,
                  steps: currentSteps,
                  bmi: _currentUser.bmi,
                  stepGoal: _stepGoal,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Achievements',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: BellaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildAchievementsGrid(achievements),
                const SizedBox(height: 40),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGoalProgress(int currentSteps) {
    final goal = _stepGoal > 0 ? _stepGoal : 1;
    final progress = (currentSteps / goal).clamp(0.0, 1.0);
    final percentage = (progress * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BellaColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BellaColors.divider),
        boxShadow: [
          BoxShadow(
            color: BellaColors.primary.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Daily Goal Progress',
                style: TextStyle(
                  color: BellaColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.edit,
                color: BellaColors.primary.withOpacity(0.85),
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 120,
                width: 120,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 12,
                  backgroundColor: BellaColors.surfaceSoft,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    BellaColors.secondary,
                  ),
                ),
              ),
              Column(
                children: [
                  Text(
                    '$percentage%',
                    style: const TextStyle(
                      color: BellaColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Completed',
                    style: TextStyle(
                        color: BellaColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '$currentSteps / $_stepGoal steps',
            style: const TextStyle(
              color: BellaColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsGrid(int steps, int hr, double cals) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Steps',
            '$steps',
            Icons.directions_walk,
            BellaColors.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Calories',
            '${cals.toInt()}',
            Icons.local_fire_department,
            BellaColors.danger,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Avg BPM',
            '$hr',
            Icons.favorite,
            BellaColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: BellaColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BellaColors.divider),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: BellaColors.textPrimary,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: BellaColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsGrid(List achievements) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: achievements.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.74,
      ),
      itemBuilder: (_, index) {
        final item = achievements[index];
        final displayColor =
            item.isUnlocked ? item.color : BellaColors.textMuted;
        final bgColor =
            item.isUnlocked ? BellaColors.surface : BellaColors.surfaceAlt;
        final opacity = item.isUnlocked ? 1.0 : 0.58;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: BellaColors.divider),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: displayColor.withOpacity(0.12),
                ),
                child: Icon(
                  item.icon,
                  color: displayColor.withOpacity(opacity),
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  item.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: item.isUnlocked
                        ? BellaColors.textPrimary
                        : BellaColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 6,
                        backgroundColor: BellaColors.surfaceSoft,
                        valueColor: AlwaysStoppedAnimation(
                          item.isUnlocked
                              ? displayColor
                              : BellaColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(item.progress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 10,
                        color: BellaColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
