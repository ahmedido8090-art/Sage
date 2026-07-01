// services/wellness_quote_service.dart
import '../models/health_data.dart';
import '../models/bella_data.dart';

/// Emotional state bucket used to pick a contextually appropriate quote.
enum _QuoteBucket { highStress, lowEnergy, poorSleep, thriving, coasting }

class WellnessQuoteService {
  // ── Quote pool ─────────────────────────────────────────────────────────────
  // Each quote carries a bucket tag so the selector can weight toward the
  // right emotional register. A null bucket = general / works anywhere.

  static final List<_TaggedQuote> _pool = [
    // highStress — calming, parasympathetic, grounding
    _TaggedQuote(
      quote: Quote(
        text: 'Breathing in, I calm my body. Breathing out, I smile.',
        author: 'Thich Nhat Hanh',
        category: 'Mindfulness',
      ),
      bucket: _QuoteBucket.highStress,
    ),
    _TaggedQuote(
      quote: Quote(
        text: 'Calm mind brings inner strength and self-confidence.',
        author: 'Dalai Lama',
        category: 'Mental Health',
      ),
      bucket: _QuoteBucket.highStress,
    ),
    _TaggedQuote(
      quote: Quote(
        text:
            'Almost everything will work again if you unplug it for a few minutes — including you.',
        author: 'Anne Lamott',
        category: 'Rest',
      ),
      bucket: _QuoteBucket.highStress,
    ),
    _TaggedQuote(
      quote: Quote(
        text:
            'You don\'t have to see the whole staircase, just take the first step.',
        author: 'Martin Luther King Jr.',
        category: 'Mindfulness',
      ),
      bucket: _QuoteBucket.highStress,
    ),

    // lowEnergy — gentle encouragement, not aggressive motivation
    _TaggedQuote(
      quote: Quote(
        text:
            'Rest when you\'re weary. Refresh and renew yourself, your body, your mind, your spirit.',
        author: 'Ralph Marston',
        category: 'Rest',
      ),
      bucket: _QuoteBucket.lowEnergy,
    ),
    _TaggedQuote(
      quote: Quote(
        text: 'Even the smallest step forward is still a step forward.',
        author: 'Unknown',
        category: 'Motivation',
      ),
      bucket: _QuoteBucket.lowEnergy,
    ),
    _TaggedQuote(
      quote: Quote(
        text: 'Take care of your body. It\'s the only place you have to live.',
        author: 'Jim Rohn',
        category: 'Physical Health',
      ),
      bucket: _QuoteBucket.lowEnergy,
    ),
    _TaggedQuote(
      quote: Quote(
        text:
            'Your body can stand almost anything. It\'s your mind you have to convince.',
        author: 'Unknown',
        category: 'Motivation',
      ),
      bucket: _QuoteBucket.lowEnergy,
    ),

    // poorSleep — restorative, sleep-positive, patience
    _TaggedQuote(
      quote: Quote(
        text:
            'Sleep is the golden chain that ties health and our bodies together.',
        author: 'Thomas Dekker',
        category: 'Sleep',
      ),
      bucket: _QuoteBucket.poorSleep,
    ),
    _TaggedQuote(
      quote: Quote(
        text:
            'A good laugh and a long sleep are the two best cures for anything.',
        author: 'Irish Proverb',
        category: 'Sleep',
      ),
      bucket: _QuoteBucket.poorSleep,
    ),
    _TaggedQuote(
      quote: Quote(
        text: 'The night is for rest. Tomorrow is for everything else.',
        author: 'Unknown',
        category: 'Sleep',
      ),
      bucket: _QuoteBucket.poorSleep,
    ),
    _TaggedQuote(
      quote: Quote(
        text:
            'Each night, when I go to sleep, I die. And the next morning, I am reborn.',
        author: 'Mahatma Gandhi',
        category: 'Sleep',
      ),
      bucket: _QuoteBucket.poorSleep,
    ),

    // thriving — celebratory, momentum, holistic
    _TaggedQuote(
      quote: Quote(
        text:
            'Health is a state of complete harmony of the body, mind and spirit.',
        author: 'B.K.S. Iyengar',
        category: 'Holistic Health',
      ),
      bucket: _QuoteBucket.thriving,
    ),
    _TaggedQuote(
      quote: Quote(
        text: 'The part can never be well unless the whole is well.',
        author: 'Plato',
        category: 'Holistic Health',
      ),
      bucket: _QuoteBucket.thriving,
    ),
    _TaggedQuote(
      quote: Quote(
        text:
            'Walking is the best possible exercise. Habituate yourself to walk very far.',
        author: 'Thomas Jefferson',
        category: 'Exercise',
      ),
      bucket: _QuoteBucket.thriving,
    ),
    _TaggedQuote(
      quote: Quote(
        text:
            'Movement is a medicine for creating change in a person\'s physical, emotional, and mental states.',
        author: 'Carol Welch',
        category: 'Exercise',
      ),
      bucket: _QuoteBucket.thriving,
    ),

    // coasting — general, mindset, balanced
    _TaggedQuote(
      quote: Quote(
        text: 'The mind is everything. What you think you become.',
        author: 'Buddha',
        category: 'Mindset',
      ),
      bucket: _QuoteBucket.coasting,
    ),
    _TaggedQuote(
      quote: Quote(
        text:
            'To keep the body in good health is a duty, otherwise we shall not be able to keep our mind strong and clear.',
        author: 'Buddha',
        category: 'Physical Health',
      ),
      bucket: _QuoteBucket.coasting,
    ),
    _TaggedQuote(
      quote: Quote(
        text:
            'An apple a day keeps the doctor away — but a walk, some water, and good sleep keep everything away.',
        author: 'Unknown',
        category: 'Holistic Health',
      ),
      bucket: _QuoteBucket.coasting,
    ),
    _TaggedQuote(
      quote: Quote(
        text:
            'Small daily improvements are the key to staggering long-term results.',
        author: 'Unknown',
        category: 'Mindset',
      ),
      bucket: _QuoteBucket.coasting,
    ),
  ];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns a quote matched to the user's current wellbeing state.
  /// Falls back to a random quote if no Bella data is available.
  ///
  /// [totalActivityMinutesToday] is the sum of walking + meditation minutes
  /// logged today. A high value is treated as a strong positive signal and
  /// pushes the bucket toward [_QuoteBucket.thriving] regardless of check-in
  /// scores, because the activity itself is the clearest sign of a good day.
  static Quote getQuoteForState({
    CheckinEntry? lastCheckin,
    SleepEntry? lastSleep,
    double? avgSleepQuality,
    int totalActivityMinutesToday = 0,
  }) {
    final bucket = _resolveBucket(
      lastCheckin: lastCheckin,
      lastSleep: lastSleep,
      avgSleepQuality: avgSleepQuality,
      totalActivityMinutesToday: totalActivityMinutesToday,
    );
    return _pickFromBucket(bucket);
  }

  /// Legacy random pick — kept so existing call sites compile unchanged.
  static Quote getRandomQuote() => _pickFromBucket(_QuoteBucket.coasting);

  static Quote getQuoteByCategory(String category) {
    final filtered = _pool
        .where((t) => t.quote.category == category)
        .map((t) => t.quote)
        .toList();
    if (filtered.isNotEmpty) {
      return filtered[_pseudoRandom(filtered.length)];
    }
    return getRandomQuote();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  static _QuoteBucket _resolveBucket({
    CheckinEntry? lastCheckin,
    SleepEntry? lastSleep,
    double? avgSleepQuality,
    int totalActivityMinutesToday = 0,
  }) {
    // Use recent check-in if it's from today or yesterday
    final now = DateTime.now();
    final checkinRecent =
        lastCheckin != null && now.difference(lastCheckin.time).inHours <= 28;

    final stress = checkinRecent ? lastCheckin.stress : 3;
    final energy = checkinRecent ? lastCheckin.energy : 3;
    final mood = checkinRecent ? lastCheckin.mood : 3;

    final sleepQuality = lastSleep?.quality;
    final poorSleepNight = sleepQuality != null && sleepQuality <= 2;
    final poorSleepAvg = (avgSleepQuality ?? 3.0) < 2.5;

    // Activity is the strongest positive signal: >=30 min logged today
    // means the user is already moving well, so lift toward thriving
    // before checking negative signals — except when stress is critically high.
    if (totalActivityMinutesToday >= 30 && stress < 4) {
      return _QuoteBucket.thriving;
    }

    // Priority order: most urgent signal wins
    if (stress >= 4) return _QuoteBucket.highStress;
    if (energy <= 2 && mood <= 2) return _QuoteBucket.lowEnergy;
    if (poorSleepNight || poorSleepAvg) return _QuoteBucket.poorSleep;
    if (energy <= 2) return _QuoteBucket.lowEnergy;

    // Any meaningful activity today also lifts the bucket.
    if (totalActivityMinutesToday >= 10) return _QuoteBucket.thriving;

    // Thriving: good check-in AND/OR decent sleep
    final goodCheckin =
        checkinRecent && mood >= 4 && energy >= 4 && stress <= 2;
    final goodSleep = sleepQuality != null && sleepQuality >= 4;
    if (goodCheckin && goodSleep) return _QuoteBucket.thriving;
    if (goodCheckin || goodSleep) return _QuoteBucket.thriving;

    return _QuoteBucket.coasting;
  }

  static Quote _pickFromBucket(_QuoteBucket bucket) {
    final candidates = _pool.where((t) => t.bucket == bucket).toList();
    if (candidates.isEmpty) {
      // Fallback — should never happen
      return _pool[_pseudoRandom(_pool.length)].quote;
    }
    return candidates[_pseudoRandom(candidates.length)].quote;
  }

  /// Pseudo-random index stable within the current minute — so the quote
  /// doesn't flicker on every rebuild but does rotate across sessions.
  static int _pseudoRandom(int length) {
    final seed = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    return seed % length;
  }
}

class _TaggedQuote {
  final Quote quote;
  final _QuoteBucket bucket;
  const _TaggedQuote({required this.quote, required this.bucket});
}
