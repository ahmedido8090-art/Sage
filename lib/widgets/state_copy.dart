// widgets/state_copy.dart
//
// Sage's words for the in-between moments: nothing here yet, something
// hiccuped, you did it. Warm and a little playful when stakes are low,
// calm and plain when they are not (errors, permissions). Never guilt,
// never blame. Each topic has a few variants and the choice rotates by day,
// so a returning user does not read the same line every time.
import 'package:flutter/widgets.dart';

enum StateTopic {
  water,
  food,
  sleep,
  checkin,
  readings,
  sessions,
  insights,
  achievements,
  bands,
  notifications,
  generic,
}

class StateText {
  final String title;
  final String message;
  const StateText(this.title, this.message);
}

class StateCopy {
  StateCopy._();

  static const Map<StateTopic, List<StateText>> _empty = {
    StateTopic.water: [
      StateText('A glass waiting to be filled', 'Log your first sip and Sage will keep count for you.'),
      StateText('Nothing sipped yet', 'No rush. Tap a size below whenever you have some water.'),
      StateText('Fresh page, cool water', 'Your day\'s hydration starts here, one gulp at a time.'),
    ],
    StateTopic.food: [
      StateText('Your plate is a blank canvas', 'Add a meal to see how the day is shaping up.'),
      StateText('No meals logged yet', 'A quick note is enough. Sage does the sums.'),
      StateText('Hungry for some data', 'Log what you ate and Sage will spot the patterns.'),
    ],
    StateTopic.sleep: [
      StateText('No nights logged yet', 'Add last night\'s sleep and Sage will start finding your rhythm.'),
      StateText('Sweet dreams start with a log', 'Tell Sage when you slept and how it felt.'),
      StateText('Your sleep story begins here', 'One night is all it takes to get going.'),
    ],
    StateTopic.checkin: [
      StateText('No check-ins yet', 'Take ten seconds to notice how you feel. There are no wrong answers.'),
      StateText('How are you, really?', 'Your first check-in is just a few taps away.'),
      StateText('A quiet moment for yourself', 'Check in and Sage will remember how you\'ve been.'),
    ],
    StateTopic.readings: [
      StateText('No readings yet', 'Add your first one and Sage will chart it over time.'),
      StateText('Ready when you are', 'Log a reading whenever you take one. Trends show up after a few.'),
      StateText('A calm place for your numbers', 'Add a reading to get started.'),
    ],
    StateTopic.sessions: [
      StateText('Nothing here yet', 'Try a short breathing session or a stroll. Even five minutes counts.'),
      StateText('Your first session is waiting', 'Pick something gentle and give it a go.'),
      StateText('Let\'s get you started', 'A few calm minutes is a lovely first step.'),
    ],
    StateTopic.insights: [
      StateText('Sage is still getting to know you', 'Log a few things and your trends will bloom here.'),
      StateText('Not enough to chart yet', 'A couple of days of logging and the picture fills in.'),
      StateText('Your story is just beginning', 'Check in, log some water, take a walk. Sage handles the rest.'),
    ],
    StateTopic.achievements: [
      StateText('Your first one is close', 'Complete a session or check-in to unlock something.'),
      StateText('Nothing unlocked yet', 'Small steps count. The first badge is a short session away.'),
      StateText('Badges are on their way', 'Keep going gently and they\'ll start appearing.'),
    ],
    StateTopic.bands: [
      StateText('No bands nearby', 'Switch your band on and bring it close, then scan again.'),
      StateText('Still looking', 'Make sure your band is awake and Bluetooth is on.'),
      StateText('Nobody answered', 'Check that your band is charged and nearby, then rescan.'),
    ],
    StateTopic.notifications: [
      StateText('Nothing planned yet', 'Turn on a category and Sage will line up friendly nudges.'),
      StateText('All quiet for now', 'Tomorrow\'s nudges will show up here.'),
      StateText('Your reminders will appear here', 'Pick what you\'d like Sage to nudge you about.'),
    ],
    StateTopic.generic: [
      StateText('Nothing here yet', 'Once there is something to show, it will appear here.'),
      StateText('A clean slate', 'Add something to get started.'),
      StateText('All clear', 'Nothing to see just yet.'),
    ],
  };

  static const List<StateText> _success = [
    StateText('Done', 'Nicely done.'),
    StateText('All set', 'That\'s saved.'),
    StateText('Lovely', 'Got it.'),
    StateText('There we go', 'Saved and sorted.'),
  ];

  /// An empty-state line for [topic]. [variant] picks one explicitly; by
  /// default the choice rotates daily.
  static StateText empty(StateTopic topic, {int? variant}) {
    final list = _empty[topic]!;
    final index = variant ?? _dayIndex();
    return list[index % list.length];
  }

  static StateText success({int? variant}) =>
      _success[(variant ?? DateTime.now().millisecond) % _success.length];

  /// Variants available for [topic] (used by tests).
  static int count(StateTopic topic) => _empty[topic]!.length;

  static Iterable<StateText> all() sync* {
    for (final list in _empty.values) {
      yield* list;
    }
    yield* _success;
  }

  static int _dayIndex() {
    final now = DateTime.now();
    return now.difference(DateTime(now.year)).inDays;
  }

  /// Convenience for widgets: stable for the life of a build.
  static StateText of(BuildContext _, StateTopic topic, {int? variant}) =>
      empty(topic, variant: variant);
}
