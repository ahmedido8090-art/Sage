// services/user_service.dart (Updated)
import 'package:hive/hive.dart';
import '../models/user.dart';

class UserService {
  // Singleton pattern
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final Box _credentialsBox = Hive.box('users');
  final Box _userDetailsBox = Hive.box('userDetails');

  String? currentUser;
  User? currentUserObject;

  // Register new user - returns success message or error
  String register(User user) {
    if (_credentialsBox.containsKey(user.username)) {
      return "Username already exists";
    }

    _credentialsBox.put(user.username, user.password);
    _userDetailsBox.put(user.username, user.toMap());

    return "Registration successful!";
  }

  // Authenticate user - returns error message or null if successful
  String? authenticate(String username, String password) {
    final storedPassword = _credentialsBox.get(username);

    if (storedPassword == null) {
      return "Username not found. Please sign up first.";
    }

    if (storedPassword != password) {
      return "Incorrect password";
    }

    final userMap = _userDetailsBox.get(username);
    if (userMap != null && userMap is Map) {
      currentUserObject = User.fromMap(Map<String, dynamic>.from(userMap));
    } else {
      currentUserObject = User(
        username: username,
        password: password,
        age: 25,
        gender: 'Not specified',
        height: 170.0,
        weight: 70.0,
      );
    }

    currentUser = username;

    return null;
  }

  // Get user details
  User? getUserDetails(String username) {
    final userMap = _userDetailsBox.get(username);
    if (userMap != null && userMap is Map) {
      return User.fromMap(Map<String, dynamic>.from(userMap));
    }
    return null;
  }

  // Update user details
  void updateUserDetails(String username, User updatedUser) {
    _userDetailsBox.put(username, updatedUser.toMap());
    if (currentUser == username) {
      currentUserObject = updatedUser;
    }
  }

  // Update password
  void updatePassword(String username, String newPassword) {
    _credentialsBox.put(username, newPassword);

    // Update password in user details
    final userMap = _userDetailsBox.get(username);
    if (userMap != null && userMap is Map) {
      final updatedMap = Map<String, dynamic>.from(userMap);
      updatedMap['password'] = newPassword;
      _userDetailsBox.put(username, updatedMap);

      if (currentUser == username && currentUserObject != null) {
        currentUserObject = User.fromMap(updatedMap);
      }
    }
  }

  // Check if user exists
  bool userExists(String username) {
    return _credentialsBox.containsKey(username);
  }

  // Get all registered users (for debugging)
  List<User> getAllUsers() {
    final List<User> users = [];
    for (final key in _userDetailsBox.keys) {
      final userMap = _userDetailsBox.get(key);
      if (userMap != null && userMap is Map) {
        users.add(User.fromMap(Map<String, dynamic>.from(userMap)));
      }
    }
    return users;
  }

  // Logout
  void logout() {
    currentUser = null;
    currentUserObject = null;
  }
}
