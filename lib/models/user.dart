// models/user.dart

// REMOVE this line for now since build_runner isn't working
// part 'user.g.dart';

/// Fixed list of selectable chronic conditions, shown as a multi-select on
/// signup and editable from the profile screen. Deliberately not free text —
/// a closed list keeps the data consistent for anything downstream (e.g.
/// insights/recommendations) that might key off specific condition names.
class ChronicConditions {
  ChronicConditions._();

  static const List<String> options = [
    'Diabetes',
    'Hypertension',
    'Asthma',
    'Heart Disease',
    'Arthritis',
    'Chronic Kidney Disease',
    'Thyroid Disorder',
    'High Cholesterol',
  ];
}

// Keep @HiveType annotations commented out for now
// @HiveType(typeId: 0)
class User {
  // @HiveField(0)
  final String username;
  
  // @HiveField(1)
  final String password;
  
  // @HiveField(2)
  final int age;
  
  // @HiveField(3)
  final String gender;
  
  // @HiveField(4)
  final double height;
  
  // @HiveField(5)
  final double weight;

  // @HiveField(6)
  /// Conditions picked from [ChronicConditions.options]. Empty means "None".
  final List<String> chronicDiseases;
  
  User({
    required this.username,
    required this.password,
    required this.age,
    required this.gender,
    required this.height,
    required this.weight,
    this.chronicDiseases = const [],
  });
  
  // Convert to Map for Hive storage
  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'password': password,
      'age': age,
      'gender': gender,
      'height': height,
      'weight': weight,
      'chronicDiseases': chronicDiseases,
    };
  }
  
  // Create User from Map
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      age: map['age'] ?? 0,
      gender: map['gender'] ?? '',
      height: map['height']?.toDouble() ?? 0.0,
      weight: map['weight']?.toDouble() ?? 0.0,
      chronicDiseases: (map['chronicDiseases'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}