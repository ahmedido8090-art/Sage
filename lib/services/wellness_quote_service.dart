// services/wellness_quote_service.dart
import '../models/health_data.dart';

class WellnessQuoteService {
  static final List<Quote> wellnessQuotes = [
    Quote(
      text: "Breathing in, I calm my body. Breathing out, I smile.",
      author: "Thich Nhat Hanh",
      category: "Mindfulness",
    ),
    Quote(
      text: "The mind is everything. What you think you become.",
      author: "Buddha",
      category: "Mindset",
    ),
    Quote(
      text: "Walking is the best possible exercise. Habituate yourself to walk very far.",
      author: "Thomas Jefferson",
      category: "Exercise",
    ),
    Quote(
      text: "Sleep is the golden chain that ties health and our bodies together.",
      author: "Thomas Dekker",
      category: "Sleep",
    ),
    Quote(
      text: "Calm mind brings inner strength and self-confidence.",
      author: "Dalai Lama",
      category: "Mental Health",
    ),
    Quote(
      text: "Your body can stand almost anything. It's your mind you have to convince.",
      author: "Unknown",
      category: "Motivation",
    ),
    Quote(
      text: "Movement is a medicine for creating change in a person's physical, emotional, and mental states.",
      author: "Carol Welch",
      category: "Exercise",
    ),
    Quote(
      text: "The part can never be well unless the whole is well.",
      author: "Plato",
      category: "Holistic Health",
    ),
    Quote(
      text: "Health is a state of complete harmony of the body, mind and spirit.",
      author: "B.K.S. Iyengar",
      category: "Holistic Health",
    ),
    Quote(
      text: "To keep the body in good health is a duty... otherwise we shall not be able to keep our mind strong and clear.",
      author: "Buddha",
      category: "Physical Health",
    ),
  ];

  static Quote getRandomQuote() {
    return wellnessQuotes[(DateTime.now().millisecondsSinceEpoch % wellnessQuotes.length).toInt()];
  }

  static Quote getQuoteByCategory(String category) {
    final filtered = wellnessQuotes.where((q) => q.category == category).toList();
    if (filtered.isNotEmpty) {
      return filtered[(DateTime.now().millisecondsSinceEpoch % filtered.length).toInt()];
    }
    return getRandomQuote();
  }
}