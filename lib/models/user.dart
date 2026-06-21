// models/user.dart
class User {
  final String username;
  final String password;
  final int age;
  final String gender;
  final double height; // cm
  final double weight; // kg
  final int dailyStepGoal;
  final List<String> chronicDiseases;
  final int waterGoal;
  final int caloriesGoal;

  User({
    required this.username,
    required this.password,
    required this.age,
    required this.gender,
    required this.height,
    required this.weight,
    this.dailyStepGoal = 6000,
    this.chronicDiseases = const [],
    this.waterGoal = 2500,
    this.caloriesGoal = 2000,
  });

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'password': password,
      'age': age,
      'gender': gender,
      'height': height,
      'weight': weight,
      'dailyStepGoal': dailyStepGoal,
      'chronicDiseases': chronicDiseases.join(','),
      'waterGoal': waterGoal,
      'caloriesGoal': caloriesGoal,
    };
  }

  factory User.fromMap(Map<dynamic, dynamic> map) {
    final chronicStr = map['chronicDiseases'] ?? '';
    final chronicList = chronicStr.isEmpty ? <String>[] : chronicStr.split(',');
    return User(
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      age: map['age'] ?? 0,
      gender: map['gender'] ?? '',
      height: map['height']?.toDouble() ?? 0.0,
      weight: map['weight']?.toDouble() ?? 0.0,
      dailyStepGoal: map['dailyStepGoal'] ?? 6000,
      chronicDiseases: chronicList,
      waterGoal: map['waterGoal'] ?? 2500,
      caloriesGoal: map['caloriesGoal'] ?? 2000,
    );
  }

  double get bmi {
    if (height <= 0) return 0.0;
    final heightInMeters = height / 100;
    return weight / (heightInMeters * heightInMeters);
  }

  bool hasChronicDisease(String disease) {
    return chronicDiseases.contains(disease);
  }
}
