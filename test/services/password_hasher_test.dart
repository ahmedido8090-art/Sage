import 'package:flutter_test/flutter_test.dart';
import 'package:sage/services/password_hasher.dart';

void main() {
  test('a hash verifies the right password and rejects others', () {
    final stored = PasswordHasher.hash('correct horse');
    expect(PasswordHasher.isHashed(stored), isTrue);
    expect(PasswordHasher.verify('correct horse', stored), isTrue);
    expect(PasswordHasher.verify('wrong', stored), isFalse);
  });

  test('the same password hashes differently each time (random salt)', () {
    expect(PasswordHasher.hash('pw'), isNot(PasswordHasher.hash('pw')));
  });

  test('the hash does not contain the password', () {
    expect(PasswordHasher.hash('hunter2hunter2'), isNot(contains('hunter2')));
  });

  test('legacy plaintext values still verify and are reported as unhashed', () {
    expect(PasswordHasher.isHashed('plain'), isFalse);
    expect(PasswordHasher.verify('plain', 'plain'), isTrue);
    expect(PasswordHasher.verify('nope', 'plain'), isFalse);
  });

  test('malformed hashes fail closed', () {
    expect(PasswordHasher.verify('x', 'v1\$abc'), isFalse);
    expect(PasswordHasher.verify('x', 'v1\$notanumber\$AAAA\$AAAA'), isFalse);
  });
}
