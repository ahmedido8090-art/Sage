// services/password_hasher.dart
//
// Salted, iterated HMAC-SHA256 password hashing, stored as
// `v1$<iterations>$<salt>$<hash>` so the parameters can be raised later
// without invalidating existing accounts.
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class PasswordHasher {
  PasswordHasher._();

  static const String _version = 'v1';
  static const int _iterations = 20000;

  /// True when [stored] is a hash produced by [hash], false for legacy
  /// plaintext values written before hashing existed.
  static bool isHashed(String stored) => stored.startsWith('$_version\$');

  static String hash(String password, {List<int>? salt, int? iterations}) {
    final saltBytes = salt ?? _randomBytes(16);
    final rounds = iterations ?? _iterations;
    return [
      _version,
      rounds,
      base64Url.encode(saltBytes),
      base64Url.encode(_derive(password, saltBytes, rounds)),
    ].join('\$');
  }

  static bool verify(String password, String stored) {
    if (!isHashed(stored)) return stored == password;
    final parts = stored.split('\$');
    if (parts.length != 4) return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null) return false;
    try {
      final expected = base64Url.decode(parts[3]);
      final actual = _derive(password, base64Url.decode(parts[2]), rounds);
      return _constantTimeEquals(expected, actual);
    } on FormatException {
      return false;
    }
  }

  static List<int> _derive(String password, List<int> salt, int rounds) {
    final hmac = Hmac(sha256, utf8.encode(password));
    var block = hmac.convert(salt).bytes;
    for (var i = 1; i < rounds; i++) {
      block = hmac.convert(block).bytes;
    }
    return block;
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
