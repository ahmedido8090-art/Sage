// services/user_service.dart
//
// Accounts and the signed-in session. Credentials (password hashes) live in
// the `users` box, profile data in `userDetails`, and the "keep me logged in"
// marker in `session`.
import 'package:hive/hive.dart';
import '../models/user.dart';
import 'password_hasher.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final Box _credentialsBox = Hive.box('users');
  final Box _userDetailsBox = Hive.box('userDetails');
  final Box _sessionBox = Hive.box('session');

  /// Username of the signed-in account, or null.
  String? currentUser;
  User? currentUserObject;

  static const String registrationSuccess = 'Registration successful!';

  /// Registers [user] with [password]. Returns [registrationSuccess] or an
  /// error message.
  String register(User user, String password) {
    if (_credentialsBox.containsKey(user.username)) {
      return 'Username already exists';
    }
    _credentialsBox.put(user.username, PasswordHasher.hash(password));
    _userDetailsBox.put(user.username, user.toMap());
    return registrationSuccess;
  }

  /// Signs in. Returns an error message, or null on success.
  String? authenticate(String username, String password) {
    final stored = _credentialsBox.get(username);
    if (stored is! String) return 'Username not found. Please sign up first.';
    if (!PasswordHasher.verify(password, stored)) return 'Incorrect password';

    // A legacy plaintext password is upgraded the first time it is used.
    if (!PasswordHasher.isHashed(stored)) {
      _credentialsBox.put(username, PasswordHasher.hash(password));
    }

    currentUserObject = getUserDetails(username) ??
        User(
          username: username,
          age: 25,
          gender: 'Not specified',
          height: 170.0,
          weight: 70.0,
        );
    currentUser = username;
    return null;
  }

  /// Whether [password] is correct for [username]. Used to confirm a password
  /// change.
  bool verifyPassword(String username, String password) {
    final stored = _credentialsBox.get(username);
    return stored is String && PasswordHasher.verify(password, stored);
  }

  User? getUserDetails(String username) {
    final userMap = _userDetailsBox.get(username);
    if (userMap is Map) {
      return User.fromMap(Map<String, dynamic>.from(userMap));
    }
    return null;
  }

  void updateUserDetails(String username, User updatedUser) {
    _userDetailsBox.put(username, updatedUser.toMap());
    if (currentUser == username) {
      currentUserObject = updatedUser;
    }
  }

  void updatePassword(String username, String newPassword) {
    _credentialsBox.put(username, PasswordHasher.hash(newPassword));
  }

  bool userExists(String username) => _credentialsBox.containsKey(username);

  void logout() {
    currentUser = null;
    currentUserObject = null;
    clearPersistedSession();
  }

  // ── "Keep me logged in" ─────────────────────────────────────────────────

  /// Remembers this username across app restarts. Called from the login
  /// screen only when "Keep me logged in" is checked.
  void persistSession(String username) {
    _sessionBox.put('rememberedUser', username);
  }

  /// Forgets any remembered session. Called on login with "Keep me logged in"
  /// unchecked and on every explicit logout.
  void clearPersistedSession() {
    _sessionBox.delete('rememberedUser');
  }

  /// Restores a remembered session, if any. Call once at startup, before
  /// deciding between the login screen and the dashboard.
  Future<void> restoreSession() async {
    final remembered = _sessionBox.get('rememberedUser');
    if (remembered is! String) return;
    final details = getUserDetails(remembered);
    if (details != null) {
      currentUserObject = details;
      currentUser = remembered;
    }
  }

  /// One-time upgrade of accounts created before passwords were hashed:
  /// hashes any plaintext credential and strips the password copy that used
  /// to be stored inside the profile map. Safe to run on every start.
  Future<void> migrateLegacyCredentials() async {
    for (final key in _credentialsBox.keys.toList()) {
      final stored = _credentialsBox.get(key);
      if (stored is String && !PasswordHasher.isHashed(stored)) {
        await _credentialsBox.put(key, PasswordHasher.hash(stored));
      }
    }
    for (final key in _userDetailsBox.keys.toList()) {
      final map = _userDetailsBox.get(key);
      if (map is Map && map.containsKey('password')) {
        final cleaned = Map<dynamic, dynamic>.from(map)..remove('password');
        await _userDetailsBox.put(key, cleaned);
      }
    }
  }
}
