import 'package:flutter/material.dart';

class Achievement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final int requiredSteps;
  final int requiredCalories;
  bool isUnlocked;
  double progress;

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.requiredSteps = 0,
    this.requiredCalories = 0,
    this.isUnlocked = false,
    this.progress = 0.0,
  });
}

class AchievementsService {
  static final AchievementsService _instance = AchievementsService._internal();
  factory AchievementsService() => _instance;
  AchievementsService._internal();

  final List<Achievement> _allAchievements = [
    Achievement(
      id: '1',
      title: 'First Steps',
      description: 'Take your first 100 steps today.',
      icon: Icons.directions_walk,
      color: Colors.blueAccent,
      requiredSteps: 100,
    ),
    Achievement(
      id: '2',
      title: 'Warming Up',
      description: 'Burn 50 calories.',
      icon: Icons.local_fire_department,
      color: Colors.orange,
      requiredCalories: 50,
    ),
    Achievement(
      id: '3',
      title: 'On the Move',
      description: 'Reach 1,000 steps.',
      icon: Icons.run_circle_outlined,
      color: Colors.purple,
      requiredSteps: 1000,
    ),
    Achievement(
      id: '4',
      title: 'Halfway There',
      description: 'Reach 3,000 steps.',
      icon: Icons.flag,
      color: Colors.teal,
      requiredSteps: 3000,
    ),
    Achievement(
      id: '5',
      title: 'Goal Crusher',
      description: 'Hit the daily goal of 6,000 steps!',
      icon: Icons.emoji_events,
      color: Colors.amber,
      requiredSteps: 6000,
    ),
    Achievement(
      id: '6',
      title: 'Calorie Burner',
      description: 'Burn 300 calories in a session.',
      icon: Icons.whatshot,
      color: Colors.redAccent,
      requiredCalories: 300,
    ),
  ];

  List<Achievement> getAchievements(int currentSteps, double currentCalories) {
    for (var achievement in _allAchievements) {
      bool stepsMet = currentSteps >= achievement.requiredSteps;
      bool calsMet = currentCalories >= achievement.requiredCalories;

      if (achievement.requiredSteps > 0 && stepsMet) {
        achievement.isUnlocked = true;
      } else if (achievement.requiredCalories > 0 && calsMet) {
        achievement.isUnlocked = true;
      }

      if (achievement.requiredSteps > 0) {
        achievement.progress =
            (currentSteps / achievement.requiredSteps).clamp(0.0, 1.0);
      } else if (achievement.requiredCalories > 0) {
        achievement.progress =
            (currentCalories / achievement.requiredCalories).clamp(0.0, 1.0);
      }
    }
    return _allAchievements;
  }
}
