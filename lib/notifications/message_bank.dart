// notifications/message_bank.dart
//
// Sage's voice: warm, a little playful, never pushy. Every message is an
// invitation, not a reprimand; none mention what the user failed to do.
// Copy rotates through a shuffled order per category, so the same line never
// shows twice in a row and a full cycle passes before any repeats.
//
// Placeholders: {name} is the user's first name or a friendly fallback,
// {n} the current streak in days (streak messages only).
import 'dart:math';
import 'notification_category.dart';

class NotificationMessage {
  final String title;
  final String body;
  const NotificationMessage(this.title, this.body);
}

class MessageBank {
  MessageBank._();

  static const Map<NotificationCategory, List<NotificationMessage>> messages = {
    NotificationCategory.hydration: [
      NotificationMessage('Water break?',
          'Your future self just did a little happy dance. A glass is calling.'),
      NotificationMessage('Sip sip hooray',
          'Tiny sips add up. Grab some water when it suits you, {name}.'),
      NotificationMessage('Plants like it, you will too',
          'Time to top up. Even a few gulps count.'),
      NotificationMessage(
          'Hydration station', 'Your cells sent a polite request for water.'),
      NotificationMessage('A glass with your name on it',
          'Cool, clear and ready whenever you are.'),
      NotificationMessage('Fresh start for your afternoon',
          'A drink of water can make the next hour feel lighter.'),
      NotificationMessage('Hey {name}, glass half... drunk?',
          'Finish it off, or pour a fresh one. Either is a win.'),
      NotificationMessage('Refill time',
          'Water is the easiest self-care there is. Go on, treat yourself.'),
      NotificationMessage(
          'Quick quench', 'Take a few sips and carry on being wonderful.'),
      NotificationMessage(
          'Splash of calm', 'Pause, sip, breathe. That is the whole task.'),
    ],
    NotificationCategory.movement: [
      NotificationMessage('Stretch o\'clock',
          'Roll your shoulders, reach up high, shake out your hands.'),
      NotificationMessage('Feet are feeling left out',
          'A short stroll would make them very happy, {name}.'),
      NotificationMessage('Tiny walk, big mood',
          'Even five minutes outside can clear your head.'),
      NotificationMessage('Wiggle break',
          'Stand up, stretch, let your body say hello to the day.'),
      NotificationMessage('Let\'s get the steps in',
          'Fancy a loop around the block? The fresh air is free.'),
      NotificationMessage('Your body says thanks in advance',
          'A little movement now, a lot of good later.'),
      NotificationMessage('Pause and pop up',
          'Stand, stretch, sway. Your chair will understand.'),
      NotificationMessage('Move a little',
          'Dance in the kitchen, climb the stairs, stroll to the corner.'),
      NotificationMessage('Fresh air is calling',
          'Slip on your shoes and see where five minutes takes you.'),
    ],
    NotificationCategory.sleep: [
      NotificationMessage('Time to slow things down',
          'Dim the lights and let the day soften around you.'),
      NotificationMessage('Wind-down o\'clock',
          'Screens down, shoulders soft. Tomorrow-you will be grateful.'),
      NotificationMessage('Cozy mode: on',
          'Maybe some calm sounds or a few slow breaths, {name}?'),
      NotificationMessage('The day did its job',
          'Ease out of it. Your bed has been patiently waiting.'),
      NotificationMessage('Sleepy-time sneak peek',
          'Start your wind-down now and drift off more easily later.'),
      NotificationMessage('Gentle reminder to rest',
          'A warm drink, low light, one deep breath. Lovely.'),
      NotificationMessage('Let\'s land this day softly',
          'Sage has some soothing sounds whenever you want them.'),
      NotificationMessage('Evening exhale',
          'Breathe in for four, out for six. Repeat until sleepy.'),
      NotificationMessage('Pillow time is near',
          'Set the room, set the mood, set yourself down.'),
    ],
    NotificationCategory.checkin: [
      NotificationMessage('How was today, {name}?',
          'Take ten seconds to notice how you feel. No wrong answers.'),
      NotificationMessage('Mood check',
          'Mood, energy, stress: a quick tap each and you are done.'),
      NotificationMessage(
          'Your daily hello to yourself', 'Pop in and log how the day felt.'),
      NotificationMessage('Quick pulse check',
          'A small check-in helps Sage understand your week.'),
      NotificationMessage('Pause for a moment',
          'How are you really doing today? Sage is listening.'),
      NotificationMessage('Tiny reflection',
          'Name one thing that went well, then log your mood.'),
      NotificationMessage('Let\'s see how you\'re feeling',
          'It takes under a minute and it adds up over time.'),
      NotificationMessage('Evening check-in',
          'Mood, energy, stress. Then you can put the day down.'),
    ],
    NotificationCategory.streak: [
      NotificationMessage('{n} days and counting',
          'You are on a roll, {name}. One small thing today keeps it alive.'),
      NotificationMessage('Look at you go',
          'That is {n} days in a row. A short session would keep the glow.'),
      NotificationMessage('Streak sparkle',
          '{n} days of showing up for yourself. Want to make it {n}+1?'),
      NotificationMessage('Keep the flame cozy',
          'Your {n}-day streak would love a little visit today.'),
      NotificationMessage('Momentum looks good on you',
          'A quick breathwork or a short walk keeps the rhythm going.'),
      NotificationMessage(
          '{n} in a row', 'Not bad at all, {name}. Even five minutes counts.'),
      NotificationMessage('Roll call for your habit',
          'Your {n}-day streak is cheering from the sidelines.'),
    ],
  };

  /// Variants whose text needs a real streak count.
  static bool needsStreak(NotificationMessage m) =>
      m.title.contains('{n}') || m.body.contains('{n}');

  /// Streak lines for future days, written without a specific count since the
  /// streak is not known yet when they are scheduled.
  static const List<NotificationMessage> streakGeneric = [
    NotificationMessage('Keep the good rhythm',
        'One small session today and your streak stays happy.'),
    NotificationMessage('A little something today?',
        'Breathe, walk or meditate for a few minutes. Streaks love company.'),
    NotificationMessage('Momentum check',
        'You have been showing up lately. A tiny session keeps it going.'),
    NotificationMessage(
        'Streak sparkle', 'Five calm minutes today would keep your run alive.'),
    NotificationMessage('Your habit says hi',
        'It would love a quick visit before the day ends.'),
  ];

  /// Order in which [count] items are visited: a full shuffle seeded by
  /// [seed], so every item appears once before any repeats.
  static List<int> shuffledOrder(int count, int seed) {
    final order = List<int>.generate(count, (i) => i);
    final rng = Random(seed);
    for (var i = count - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = order[i];
      order[i] = order[j];
      order[j] = tmp;
    }
    return order;
  }

  /// Visiting order for one full pass ([cycle]) through a pool of [length].
  /// Each pass is reshuffled, and a pass never starts on the item the
  /// previous pass ended on, so there is no immediate repeat at the seam.
  static List<int> orderForCycle(int length, int baseSeed, int cycle) {
    final order = shuffledOrder(length, baseSeed + cycle);
    if (cycle == 0 || length < 2) return order;
    final previous = orderForCycle(length, baseSeed, cycle - 1);
    if (order.first == previous.last) {
      return [...order.skip(1), order.first];
    }
    return order;
  }

  /// The message at position [cursor] of this category's rotation.
  static NotificationMessage pick(
    NotificationCategory category,
    int cursor, {
    List<NotificationMessage>? pool,
    int seedSalt = 0,
  }) {
    final list = pool ?? messages[category]!;
    final order = orderForCycle(
        list.length, category.index * 1009 + seedSalt, cursor ~/ list.length);
    return list[order[cursor % list.length]];
  }

  /// Fills {name} and {n}.
  static NotificationMessage fill(NotificationMessage m,
      {required String name, int? streak}) {
    String sub(String s) => s
        .replaceAll('{name}', name)
        .replaceAll('{n}', (streak ?? 0).toString());
    return NotificationMessage(sub(m.title), sub(m.body));
  }
}
