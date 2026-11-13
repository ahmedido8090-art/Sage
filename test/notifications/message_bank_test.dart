import 'package:flutter_test/flutter_test.dart';
import 'package:sage/notifications/message_bank.dart';
import 'package:sage/notifications/notification_category.dart';

void main() {
  // Words that read as pressure or blame. Sage invites; it never scolds.
  const guiltWords = [
    'lazy',
    'fail',
    'failed',
    'disappoint',
    'you missed',
    'you forgot',
    'you haven\'t',
    'you have not',
    'should have',
    'behind',
    'slacking',
    'give up',
    'broke your',
    'lost your',
    'shame',
    'guilt',
    'ashamed',
    'don\'t forget',
    'must',
    'neglect',
  ];

  group('copy', () {
    for (final category in NotificationCategory.values) {
      final pool = MessageBank.messages[category]!;

      test('${category.id}: enough variety for rotation', () {
        expect(pool.length, greaterThanOrEqualTo(7));
        expect(pool.map((m) => m.title).toSet().length, pool.length,
            reason: 'duplicate titles');
      });

      test('${category.id}: short enough for a notification', () {
        for (final m in pool) {
          expect(m.title.length, lessThanOrEqualTo(40), reason: m.title);
          expect(m.body.length, lessThanOrEqualTo(110), reason: m.body);
          expect(m.title.trim(), isNotEmpty);
          expect(m.body.trim(), isNotEmpty);
        }
      });

      test('${category.id}: warm, never guilt-tripping', () {
        for (final m in pool) {
          final text = '${m.title} ${m.body}'.toLowerCase();
          for (final w in guiltWords) {
            expect(text.contains(w), isFalse, reason: '"$w" in "$text"');
          }
        }
      });

      test('${category.id}: placeholders are known ones only', () {
        final known = RegExp(r'\{(name|n)\}');
        final any = RegExp(r'\{[^}]*\}');
        for (final m in pool) {
          for (final hit in any.allMatches('${m.title} ${m.body}')) {
            expect(known.hasMatch(hit.group(0)!), isTrue, reason: hit.group(0));
          }
        }
      });
    }

    test('only streak messages use {n}, and generic streak lines never do', () {
      for (final category in NotificationCategory.values) {
        if (category == NotificationCategory.streak) continue;
        for (final m in MessageBank.messages[category]!) {
          expect(MessageBank.needsStreak(m), isFalse, reason: m.title);
        }
      }
      for (final m in MessageBank.streakGeneric) {
        expect(MessageBank.needsStreak(m), isFalse, reason: m.title);
      }
    });

    test('fill() replaces name and streak', () {
      const m = NotificationMessage('{n} days', 'Hi {name}');
      final filled = MessageBank.fill(m, name: 'Ana', streak: 4);
      expect(filled.title, '4 days');
      expect(filled.body, 'Hi Ana');
    });
  });

  group('rotation', () {
    for (final category in NotificationCategory.values) {
      test('${category.id}: never the same line twice in a row', () {
        final n = MessageBank.messages[category]!.length;
        NotificationMessage? previous;
        for (var cursor = 0; cursor < n * 6; cursor++) {
          final m = MessageBank.pick(category, cursor);
          if (previous != null) {
            expect(m.title, isNot(previous.title), reason: 'cursor $cursor');
          }
          previous = m;
        }
      });

      test('${category.id}: every line is used once per full pass', () {
        final pool = MessageBank.messages[category]!;
        for (var cycle = 0; cycle < 4; cycle++) {
          final seen = {
            for (var i = 0; i < pool.length; i++)
              MessageBank.pick(category, cycle * pool.length + i).title,
          };
          expect(seen.length, pool.length, reason: 'cycle $cycle');
        }
      });
    }

    test('passes are reshuffled, not the same order repeated', () {
      const c = NotificationCategory.hydration;
      final n = MessageBank.messages[c]!.length;
      final first = [for (var i = 0; i < n; i++) MessageBank.pick(c, i).title];
      final second = [
        for (var i = 0; i < n; i++) MessageBank.pick(c, n + i).title
      ];
      expect(first, isNot(second));
    });
  });
}
