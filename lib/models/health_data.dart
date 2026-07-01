// models/health_data.dart (Updated)
import 'package:flutter/material.dart';

class HealthData {
  final int heartRate;
  final int steps;
  final bool isConnected;
  final double calories;
  final int sleepHours;
  final int spo2;
  final double temperature;
  final int batteryLevel;

  HealthData({
    required this.heartRate,
    required this.steps,
    required this.isConnected,
    required this.calories,
    required this.sleepHours,
    this.spo2 = 98,
    this.temperature = 36.7,
    this.batteryLevel = 78,
  });
}

class Quote {
  final String text;
  final String author;
  final String category;

  Quote({
    required this.text,
    required this.author,
    this.category = "General",
  });
}

class WellnessActivity {
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String benefits;
  final String instructions;
  final bool bmiFriendly; // Suitable for all BMI ranges
  final bool beginnerFriendly;

  WellnessActivity({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.benefits,
    required this.instructions,
    this.bmiFriendly = true,
    this.beginnerFriendly = true,
  });
}