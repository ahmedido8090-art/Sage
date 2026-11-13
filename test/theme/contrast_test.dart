// Locks the palette to WCAG AA in both modes, so a future color tweak that
// makes text unreadable fails here instead of on a user's phone.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sage/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void _expectAa(String label, Color fg, Color bg, {double min = 4.5}) {
  final ratio = _contrast(fg, bg);
  expect(ratio, greaterThanOrEqualTo(min),
      reason: '$label contrast ${ratio.toStringAsFixed(2)} < $min');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    test('$mode: text on surfaces meets AA', () async {
      await ThemeController.setDark(dark);
      for (final (name, surface) in [
        ('page', SageColors.linen),
        ('card', SageColors.card),
        ('raised', SageColors.cardRaised),
      ]) {
        _expectAa('ink on $name', SageColors.ink, surface);
        // Light mode's secondary text sits at 4.5-4.6 on the page tint.
        _expectAa('inkSoft on $name', SageColors.inkSoft, surface);
        _expectAa('moss on $name', SageColors.moss, surface);
      }
    });

    test('$mode: hero panel text meets AA', () async {
      await ThemeController.setDark(dark);
      _expectAa('hero number', SageColors.heroNumber, SageColors.heroBg);
      _expectAa('hero label', SageColors.heroLabel, SageColors.heroBg);
      _expectAa('hero muted', SageColors.heroLabelMuted, SageColors.heroBg,
          min: 4.5);
      _expectAa('hero sub', SageColors.heroSubLabel, SageColors.heroBg,
          min: 4.5);
    });
  }

  test('dark: accents and fills are legible on every layer', () async {
    await ThemeController.setDark(true);
    for (final surface in [
      SageColors.linen,
      SageColors.card,
      SageColors.cardRaised
    ]) {
      _expectAa('clay', SageColors.clay, surface);
      _expectAa('amber', SageColors.amber, surface);
      _expectAa('sage', SageColors.sage, surface, min: 3);
    }
    _expectAa('text on moss fill', SageColors.onAccent, SageColors.moss);
    _expectAa('text on clay fill', SageColors.onAccent, SageColors.clay);
  });

  test('dark: surfaces are layered and never pure black', () async {
    await ThemeController.setDark(true);
    expect(SageColors.linen.computeLuminance(), greaterThan(0.005));
    expect(SageColors.card.computeLuminance(),
        greaterThan(SageColors.linen.computeLuminance()));
    expect(SageColors.cardRaised.computeLuminance(),
        greaterThan(SageColors.card.computeLuminance()));
  });

  test('legible() rescues deep fixed colors in dark and leaves light alone',
      () async {
    const deepGreen = Color(0xFF145A32);
    await ThemeController.setDark(false);
    expect(SageColors.legible(deepGreen), deepGreen);

    await ThemeController.setDark(true);
    final lifted = SageColors.legible(deepGreen);
    _expectAa('lifted deep green', lifted, SageColors.card);
    expect(HSLColor.fromColor(lifted).hue,
        closeTo(HSLColor.fromColor(deepGreen).hue, 6));
  });

  test('onFill() picks the more readable of white and deep ink in dark',
      () async {
    await ThemeController.setDark(true);
    for (final fill in const [
      Color(0xFF6E756D),
      Color(0xFFE2734B),
      Color(0xFFEAAE49)
    ]) {
      expect(_contrast(SageColors.onFill(fill), fill), greaterThan(3.5));
    }
    await ThemeController.setDark(false);
    expect(SageColors.onFill(const Color(0xFFE2734B)), const Color(0xFFFFFFFF));
  });
}
