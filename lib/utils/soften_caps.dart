// utils/soften_caps.dart
//
// Sage does not shout. Text written in ALL CAPS is turned into sentence case
// ("WIND-DOWN TIPS" becomes "Wind-down tips"); text that is already normal is
// left exactly as written, so proper nouns survive.
String softenCaps(String text) {
  final isShouting =
      text == text.toUpperCase() && RegExp(r'[A-Z]{2}').hasMatch(text);
  if (!isShouting) return text;
  final lower = text.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}
