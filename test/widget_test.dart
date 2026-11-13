import 'package:flutter_test/flutter_test.dart';
import 'package:sage/models/user.dart';

void main() {
  User user({List<String> diseases = const []}) => User(
        username: 'sage',
        password: 'pw',
        age: 30,
        gender: 'F',
        height: 170,
        weight: 70,
        chronicDiseases: diseases,
      );

  test('User computes BMI from height and weight', () {
    expect(user().bmi, closeTo(24.22, 0.01));
  });

  test('User round-trips goals and conditions through a map', () {
    final restored = User.fromMap(user(diseases: ['Asthma']).toMap());
    expect(restored.hasChronicDisease('Asthma'), isTrue);
    expect(restored.hasChronicDisease('Diabetes'), isFalse);
    expect(restored.waterGoal, 2500);
    expect(restored.caloriesGoal, 2000);
    expect(restored.dailyStepGoal, 8000);
  });
}
