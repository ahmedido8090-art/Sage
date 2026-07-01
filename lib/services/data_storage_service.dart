// services/data_storage_service.dart - COMPREHENSIVE VERSION
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DataStorageService {
  static final DataStorageService _instance = DataStorageService._internal();
  factory DataStorageService() => _instance;
  DataStorageService._internal();

  static const String _bandDataKey = 'sage_band_data';
  static const String _sleepDataKey = 'sage_sleep_data';
  static const String _weightDataKey = 'sage_weight_data';
  static const String _moodDataKey = 'sage_mood_data';
  static const String _activitySessionsKey = 'sage_activity_sessions';
  static const String _meditationSessionsKey = 'sage_meditation_sessions';
  static const String _breathworkSessionsKey = 'sage_breathwork_sessions';
  static const String _sleepSoundsSessionsKey = 'sage_sleep_sounds_sessions';
  static const String _wellnessActivitiesKey = 'sage_wellness_activities';
  static const String _userStatsKey = 'sage_user_stats';
  static const String _dailyGoalsKey = 'sage_daily_goals';

  // --- USER STATISTICS ---
  Future<void> updateUserStats({
    int? totalMeditationMinutes = 0,
    int? totalBreathworkMinutes = 0,
    int? totalWalkingMinutes = 0,
    int? totalSleepSoundsMinutes = 0,
    int? totalSteps = 0,
    int? totalCalories = 0,
    int? streakDays = 0,
    DateTime? lastActivityDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final stats = await getUserStats();
    
    final updatedStats = {
      'totalMeditationMinutes': (stats['totalMeditationMinutes'] ?? 0) + (totalMeditationMinutes ?? 0),
      'totalBreathworkMinutes': (stats['totalBreathworkMinutes'] ?? 0) + (totalBreathworkMinutes ?? 0),
      'totalWalkingMinutes': (stats['totalWalkingMinutes'] ?? 0) + (totalWalkingMinutes ?? 0),
      'totalSleepSoundsMinutes': (stats['totalSleepSoundsMinutes'] ?? 0) + (totalSleepSoundsMinutes ?? 0),
      'totalSteps': (stats['totalSteps'] ?? 0) + (totalSteps ?? 0),
      'totalCalories': (stats['totalCalories'] ?? 0) + (totalCalories ?? 0),
      'streakDays': streakDays ?? stats['streakDays'] ?? 0,
      'lastActivityDate': lastActivityDate?.millisecondsSinceEpoch ?? stats['lastActivityDate'],
      'totalSessions': (stats['totalSessions'] ?? 0) + 1,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    
    await prefs.setString(_userStatsKey, jsonEncode(updatedStats));
  }

  Future<Map<String, dynamic>> getUserStats() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_userStatsKey);
    
    if (data == null) {
      return {
        'totalMeditationMinutes': 0,
        'totalBreathworkMinutes': 0,
        'totalWalkingMinutes': 0,
        'totalSleepSoundsMinutes': 0,
        'totalSteps': 0,
        'totalCalories': 0,
        'streakDays': 0,
        'totalSessions': 0,
        'lastActivityDate': null,
      };
    }
    
    return jsonDecode(data);
  }

  // --- MEDITATION SESSIONS ---
  Future<void> saveMeditationSession({
    required String poseName,
    required int durationSeconds,
    required int startHeartRate,
    required int endHeartRate,
    required DateTime timestamp,
    String? benefits,
    double? calmScore,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getStringList(_meditationSessionsKey) ?? [];
    
    final session = {
      'type': 'meditation',
      'poseName': poseName,
      'durationSeconds': durationSeconds,
      'startHeartRate': startHeartRate,
      'endHeartRate': endHeartRate,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'benefits': benefits ?? '',
      'calmScore': calmScore ?? calculateCalmScore(startHeartRate, endHeartRate),
      'sessionId': 'med_${timestamp.millisecondsSinceEpoch}',
    };
    
    existingData.add(jsonEncode(session));
    
    // Keep only last 100 meditation sessions
    if (existingData.length > 100) {
      existingData.removeAt(0);
    }
    
    await prefs.setStringList(_meditationSessionsKey, existingData);
    
    // Update user stats
    await updateUserStats(
      totalMeditationMinutes: durationSeconds ~/ 60,
      lastActivityDate: timestamp,
    );
  }

  Future<List<Map<String, dynamic>>> getMeditationSessions({int daysBack = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_meditationSessionsKey) ?? [];
    
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    
    return data.map((entry) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return {
        ...map,
        'timestamp': DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      };
    }).where((entry) => entry['timestamp'] is DateTime && (entry['timestamp'] as DateTime).isAfter(cutoff)).toList();
  }

  // --- BREATHWORK SESSIONS ---
  Future<void> saveBreathworkSession({
    required String technique,
    required int durationSeconds,
    required int startHeartRate,
    required int endHeartRate,
    required int cyclesCompleted,
    required DateTime timestamp,
    String? benefits,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getStringList(_breathworkSessionsKey) ?? [];
    
    final session = {
      'type': 'breathwork',
      'technique': technique,
      'durationSeconds': durationSeconds,
      'startHeartRate': startHeartRate,
      'endHeartRate': endHeartRate,
      'cyclesCompleted': cyclesCompleted,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'benefits': benefits ?? '',
      'heartRateChange': startHeartRate - endHeartRate,
      'sessionId': 'breath_${timestamp.millisecondsSinceEpoch}',
    };
    
    existingData.add(jsonEncode(session));
    
    if (existingData.length > 100) {
      existingData.removeAt(0);
    }
    
    await prefs.setStringList(_breathworkSessionsKey, existingData);
    
    await updateUserStats(
      totalBreathworkMinutes: durationSeconds ~/ 60,
      lastActivityDate: timestamp,
    );
  }

  Future<List<Map<String, dynamic>>> getBreathworkSessions({int daysBack = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_breathworkSessionsKey) ?? [];
    
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    
    return data.map((entry) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return {
        ...map,
        'timestamp': DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      };
    }).where((entry) => entry['timestamp'] is DateTime && (entry['timestamp'] as DateTime).isAfter(cutoff)).toList();
  }

  // --- WALKING/ACTIVITY SESSIONS ---
  Future<void> saveWalkingSession({
    required int steps,
    required double distanceKm,
    required double calories,
    required int durationSeconds,
    required String activityType,
    required DateTime timestamp,
    int? averageHeartRate,
    int? maxHeartRate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getStringList(_activitySessionsKey) ?? [];
    
    final session = {
      'type': 'walking',
      'steps': steps,
      'distanceKm': distanceKm,
      'calories': calories,
      'durationSeconds': durationSeconds,
      'activityType': activityType,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'averageHeartRate': averageHeartRate,
      'maxHeartRate': maxHeartRate,
      'sessionId': 'walk_${timestamp.millisecondsSinceEpoch}',
    };
    
    existingData.add(jsonEncode(session));
    
    if (existingData.length > 100) {
      existingData.removeAt(0);
    }
    
    await prefs.setStringList(_activitySessionsKey, existingData);
    
    await updateUserStats(
      totalWalkingMinutes: durationSeconds ~/ 60,
      totalSteps: steps,
      totalCalories: calories.toInt(),
      lastActivityDate: timestamp,
    );
  }

  // --- SLEEP SOUNDS SESSIONS ---
  Future<void> saveSleepSoundsSession({
    required String soundName,
    required int durationSeconds,
    required DateTime timestamp,
    double? relaxationScore,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getStringList(_sleepSoundsSessionsKey) ?? [];
    
    final session = {
      'type': 'sleep_sounds',
      'soundName': soundName,
      'durationSeconds': durationSeconds,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'relaxationScore': relaxationScore ?? 0,
      'sessionId': 'sleep_${timestamp.millisecondsSinceEpoch}',
    };
    
    existingData.add(jsonEncode(session));
    
    if (existingData.length > 100) {
      existingData.removeAt(0);
    }
    
    await prefs.setStringList(_sleepSoundsSessionsKey, existingData);
    
    await updateUserStats(
      totalSleepSoundsMinutes: durationSeconds ~/ 60,
      lastActivityDate: timestamp,
    );
  }

  Future<List<Map<String, dynamic>>> getSleepSoundsSessions({int daysBack = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_sleepSoundsSessionsKey) ?? [];
    
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    
    return data.map((entry) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return {
        ...map,
        'timestamp': DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      };
    }).where((entry) => entry['timestamp'] is DateTime && (entry['timestamp'] as DateTime).isAfter(cutoff)).toList();
  }

  // --- DAILY GOALS ---
  Future<void> updateDailyGoal({
    required String goalType,
    required double progress,
    required double target,
    required DateTime date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getStringList(_dailyGoalsKey) ?? [];
    
    final goalKey = '${date.year}-${date.month}-${date.day}_$goalType';
    
    // Remove existing entry for same date and goal type
    existingData.removeWhere((e) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      return map['goalKey'] == goalKey;
    });
    
    final goal = {
      'goalKey': goalKey,
      'goalType': goalType,
      'progress': progress,
      'target': target,
      'date': date.millisecondsSinceEpoch,
      'completionRate': (progress / target).clamp(0.0, 1.0),
      'isCompleted': progress >= target,
    };
    
    existingData.add(jsonEncode(goal));
    
    await prefs.setStringList(_dailyGoalsKey, existingData);
  }

  Future<List<Map<String, dynamic>>> getDailyGoals({int daysBack = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_dailyGoalsKey) ?? [];
    
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    
    return data.map((entry) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return {
        ...map,
        'date': DateTime.fromMillisecondsSinceEpoch(map['date']),
      };
    }).where((entry) => entry['date'] is DateTime && (entry['date'] as DateTime).isAfter(cutoff)).toList();
  }

  // --- WELLNESS ACTIVITIES TRACKING ---
  Future<void> trackWellnessActivity({
    required String activityName,
    required int durationMinutes,
    required DateTime timestamp,
    String? category,
    double? moodBefore,
    double? moodAfter,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getStringList(_wellnessActivitiesKey) ?? [];
    
    final activity = {
      'activityName': activityName,
      'durationMinutes': durationMinutes,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'category': category ?? 'general',
      'moodBefore': moodBefore,
      'moodAfter': moodAfter,
      'moodImprovement': (moodAfter ?? 0) - (moodBefore ?? 0),
    };
    
    existingData.add(jsonEncode(activity));
    
    if (existingData.length > 200) {
      existingData.removeAt(0);
    }
    
    await prefs.setStringList(_wellnessActivitiesKey, existingData);
  }

  // --- ANALYTICS & INSIGHTS ---
  Future<Map<String, dynamic>> getActivitySummary({int daysBack = 7}) async {
    final meditationSessions = await getMeditationSessions(daysBack: daysBack);
    final breathworkSessions = await getBreathworkSessions(daysBack: daysBack);
    final walkingSessions = await getActivitySessions(daysBack: daysBack);
    final sleepSoundsSessions = await getSleepSoundsSessions(daysBack: daysBack);
    
    int totalMeditationMinutes = meditationSessions.fold(0, (int sum, session) => sum + ((session['durationSeconds'] as int) ~/ 60));
    int totalBreathworkMinutes = breathworkSessions.fold(0, (int sum, session) => sum + ((session['durationSeconds'] as int) ~/ 60));
    int totalWalkingMinutes = walkingSessions.fold(0, (int sum, session) => sum + ((session['durationSeconds'] as int) ~/ 60));
    int totalSleepMinutes = sleepSoundsSessions.fold(0, (int sum, session) => sum + ((session['durationSeconds'] as int) ~/ 60));
    
    int totalSteps = walkingSessions.fold(0, (sum, session) => sum + (session['steps'] as int));
    double totalCalories = walkingSessions.fold(0.0, (sum, session) => sum + (session['calories'] as double));
    
    return {
      'totalSessions': meditationSessions.length + breathworkSessions.length + walkingSessions.length + sleepSoundsSessions.length,
      'totalMeditationMinutes': totalMeditationMinutes,
      'totalBreathworkMinutes': totalBreathworkMinutes,
      'totalWalkingMinutes': totalWalkingMinutes,
      'totalSleepMinutes': totalSleepMinutes,
      'totalSteps': totalSteps,
      'totalCalories': totalCalories,
      'avgHeartRateChange': calculateAverageHeartRateChange(meditationSessions, breathworkSessions),
      'mostPopularActivity': getMostPopularActivity(meditationSessions, breathworkSessions, walkingSessions, sleepSoundsSessions),
      'streakDays': await calculateStreak(),
    };
  }

  // --- HELPER METHODS ---
  double calculateCalmScore(int startHR, int endHR) {
    final change = startHR - endHR;
    if (change > 15) return 1.0; // Excellent
    if (change > 8) return 0.7;  // Good
    if (change > 0) return 0.4;  // Fair
    return 0.1; // Minimal change
  }

  double calculateAverageHeartRateChange(List meditationSessions, List breathworkSessions) {
    final allSessions = [...meditationSessions, ...breathworkSessions];
    if (allSessions.isEmpty) return 0.0;
    
    double totalChange = allSessions.fold(0.0, (sum, session) {
      final start = session['startHeartRate'] as int;
      final end = session['endHeartRate'] as int;
      return sum + (start - end);
    });
    
    return totalChange / allSessions.length;
  }

  String getMostPopularActivity(List meditationSessions, List breathworkSessions, List walkingSessions, List sleepSoundsSessions) {
    final activities = {
      'Meditation': meditationSessions.length,
      'Breathwork': breathworkSessions.length,
      'Walking': walkingSessions.length,
      'Sleep Sounds': sleepSoundsSessions.length,
    };
    
    return activities.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  Future<int> calculateStreak() async {
    final allSessions = [
      ...await getMeditationSessions(daysBack: 365),
      ...await getBreathworkSessions(daysBack: 365),
      ...await getActivitySessions(daysBack: 365),
      ...await getSleepSoundsSessions(daysBack: 365),
    ];
    
    if (allSessions.isEmpty) return 0;
    
    // Sort by date and get unique days with activity
    final activityDates = allSessions.map((s) => (s['timestamp'] as DateTime).toLocal().toString().split(' ')[0]).toSet().toList();
    activityDates.sort((a, b) => b.compareTo(a));
    
    int streak = 0;
    final today = DateTime.now().toLocal().toString().split(' ')[0];
    DateTime currentDate = DateTime.parse(today);
    
    for (int i = 0; i < 365; i++) {
      final dateStr = currentDate.toString().split(' ')[0];
      if (activityDates.contains(dateStr)) {
        streak++;
        currentDate = currentDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    
    return streak;
  }

  // --- ORIGINAL METHODS (Keep all existing functionality) ---
  
  // --- Band Data Storage (Heart Rate, Steps) ---
  Future<void> saveBandData({
    required int heartRate,
    required int steps,
    required DateTime timestamp,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getStringList(_bandDataKey) ?? [];
    
    final entry = {
      'hr': heartRate.toString(),
      'steps': steps.toString(),
      'time': timestamp.millisecondsSinceEpoch.toString(),
    };
    
    existingData.add(jsonEncode(entry));
    
    // Keep only last 7 days of data (approx 10k entries max)
    if (existingData.length > 10000) {
      existingData.removeAt(0);
    }
    
    await prefs.setStringList(_bandDataKey, existingData);
  }

  Future<List<Map<String, dynamic>>> getBandData({int daysBack = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_bandDataKey) ?? [];
    
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    
    return data.map((entry) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return {
        'hr': int.parse(map['hr']),
        'steps': int.parse(map['steps']),
        'time': DateTime.fromMillisecondsSinceEpoch(int.parse(map['time'])),
      };
    }).where((entry) => entry['time'] is DateTime && (entry['time'] as DateTime).isAfter(cutoff)).toList();
  }

  // --- Sleep Data Storage ---
  Future<void> saveSleepData(double hours, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getStringList(_sleepDataKey) ?? [];
    
    final entry = {
      'hours': hours.toString(),
      'date': date.millisecondsSinceEpoch.toString(),
    };
    
    // Remove any existing entry for same date
    existingData.removeWhere((e) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      final entryDate = DateTime.fromMillisecondsSinceEpoch(int.parse(map['date']));
      return entryDate.year == date.year && 
             entryDate.month == date.month && 
             entryDate.day == date.day;
    });
    
    existingData.add(jsonEncode(entry));
    await prefs.setStringList(_sleepDataKey, existingData);
  }

  Future<List<Map<String, dynamic>>> getSleepData({int daysBack = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_sleepDataKey) ?? [];
    
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    
    return data.map((entry) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return {
        'hours': double.parse(map['hours']),
        'date': DateTime.fromMillisecondsSinceEpoch(int.parse(map['date'])),
      };
    }).where((entry) {
      final d = entry['date'];
      return d is DateTime && d.isAfter(cutoff);
    }).toList();
  }

  // --- Weight Data Storage ---
  Future<void> saveWeightData(double weight, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getStringList(_weightDataKey) ?? [];
    
    final entry = {
      'weight': weight.toString(),
      'date': date.millisecondsSinceEpoch.toString(),
    };
    
    // Remove any existing entry for same date
    existingData.removeWhere((e) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      final entryDate = DateTime.fromMillisecondsSinceEpoch(int.parse(map['date']));
      return entryDate.year == date.year && 
             entryDate.month == date.month && 
             entryDate.day == date.day;
    });
    
    existingData.add(jsonEncode(entry));
    await prefs.setStringList(_weightDataKey, existingData);
  }

  Future<List<Map<String, dynamic>>> getWeightData({int daysBack = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_weightDataKey) ?? [];
    
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    
    return data.map((entry) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return {
        'weight': double.parse(map['weight']),
        'date': DateTime.fromMillisecondsSinceEpoch(int.parse(map['date'])),
      };
    }).where((entry) => entry['date'] is DateTime && (entry['date'] as DateTime).isAfter(cutoff)).toList();
  }

  // --- Mood Data Storage ---
  Future<void> saveMoodData({
    required String emoji,
    required String note,
    DateTime? date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getStringList(_moodDataKey) ?? [];
    
    final entry = {
      'emoji': emoji,
      'note': note,
      'date': (date ?? DateTime.now()).millisecondsSinceEpoch.toString(),
    };
    
    existingData.add(jsonEncode(entry));
    
    // Keep only last 30 days of mood data
    if (existingData.length > 1000) {
      existingData.removeAt(0);
    }
    
    await prefs.setStringList(_moodDataKey, existingData);
  }

  Future<List<Map<String, dynamic>>> getMoodData({int daysBack = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_moodDataKey) ?? [];
    
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    
    return data.map((entry) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return {
        'emoji': map['emoji'],
        'note': map['note'],
        'date': DateTime.fromMillisecondsSinceEpoch(int.parse(map['date'])),
      };
    }).where((entry) => entry['date'] is DateTime && (entry['date'] as DateTime).isAfter(cutoff)).toList();
  }

  // --- Activity Sessions Storage (original) ---
  Future<void> saveActivitySession(Map<String, dynamic> sessionData) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getStringList(_activitySessionsKey) ?? [];
    
    existingData.add(jsonEncode(sessionData));
    
    // Keep only last 100 activity sessions
    if (existingData.length > 100) {
      existingData.removeAt(0);
    }
    
    await prefs.setStringList(_activitySessionsKey, existingData);
  }

  Future<List<Map<String, dynamic>>> getActivitySessions({int daysBack = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_activitySessionsKey) ?? [];
    
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    
    return data.map((entry) {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return {
        ...map,
        'timestamp': DateTime.fromMillisecondsSinceEpoch(int.parse(map['timestamp'])),
      };
    }).where((entry) => entry['timestamp'] is DateTime && (entry['timestamp'] as DateTime).isAfter(cutoff)).toList();
  }

  // --- Clear All Data ---
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bandDataKey);
    await prefs.remove(_sleepDataKey);
    await prefs.remove(_weightDataKey);
    await prefs.remove(_moodDataKey);
    await prefs.remove(_activitySessionsKey);
    await prefs.remove(_meditationSessionsKey);
    await prefs.remove(_breathworkSessionsKey);
    await prefs.remove(_sleepSoundsSessionsKey);
    await prefs.remove(_wellnessActivitiesKey);
    await prefs.remove(_userStatsKey);
    await prefs.remove(_dailyGoalsKey);
  }

  // --- Clear User Data (for debugging) ---
  Future<void> clearAllUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_meditationSessionsKey);
    await prefs.remove(_breathworkSessionsKey);
    await prefs.remove(_activitySessionsKey);
    await prefs.remove(_sleepSoundsSessionsKey);
    await prefs.remove(_wellnessActivitiesKey);
    await prefs.remove(_userStatsKey);
    await prefs.remove(_dailyGoalsKey);
  }
}