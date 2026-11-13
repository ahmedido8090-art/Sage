// theme/app_theme.dart
//
// A5 — Sage Spring palette, "Sage Noir" dark mode
//
// Anchors (chosen by the user):
//   Primary green:  #1E7A50   vivid leaf, warm and fresh
//   Page bg light:  #F4F9F4   green-tinted near-white, not warm-paper
//   Clay accent:    #E8714A   warm coral-orange, replaces the old #E2734B
//   Amber accent:   #E8A832   golden amber, slightly richer than old #EAAE49
//
// Dark mode is the same system in a different light, not an inverted copy:
// identical hues, shapes, type and spacing, with surfaces layered by lightness
// instead of shadow (page < card < raised) and accents lifted just enough to
// stay vivid and pass WCAG AA on every surface. The numbers are checked by
// test/theme/contrast_test.dart.
//   Page dark:      #101713   deep green-black, never pure black
//   Card dark:      #18221D   one step up
//   Raised dark:    #202D26   sheets, dialogs, snackbars
//   Hero bg dark:   #1A5239   emerald panel, lighter than the card so the
//                              dashboard anchor reads as the top layer
//   Moss dark:      #4CCB8D   the light-mode green, lifted
//   Clay dark:      #F28D6E   the light-mode coral, lifted
//   Amber dark:     #F4BF5A   the light-mode amber, lifted
//
// Everything else (mossLight, sage, ink, line, hero tokens) is derived
// from those anchors by lightening/darkening/blending — not invented
// independently — so the palette stays internally coherent.
//
// Typography: one humanist family, Nunito, whose rounded terminals read as
// friendly rather than corporate. Weight and size carry the hierarchy
// (wordmark and headlines w800/w700, body w400, labels w600). Numbers use
// Nunito's tabular figures so columns still align. Fraunces italic stays for
// pull-quotes, where a warm editorial voice fits.
import 'package:flutter/material.dart' as fm
    show TextTheme; // ignore: deprecated_member_use
import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tokens.dart';

/// Controls light/dark mode app-wide and persists the choice.
///
/// [SageColors]' fields are mutable static fields that get swapped in place
/// when the mode changes. Screens read them directly instead of through
/// `Theme.of(context)`, so after swapping the palette every live element is
/// marked for rebuild. That repaints the whole app in one frame while keeping
/// the navigator stack and each screen's state, which recreating the
/// `MaterialApp` would throw away.
class ThemeController {
  ThemeController._();

  static const _prefsKey = 'sage_dark_mode';

  static final ValueNotifier<bool> isDark = ValueNotifier(false);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefsKey) ?? false;
    _applyPalette(saved);
    isDark.value = saved;
  }

  static Future<void> setDark(bool value) async {
    if (isDark.value == value) return;
    _applyPalette(value);
    _rebuildLiveElements();
    isDark.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  static Future<void> toggle() => setDark(!isDark.value);

  static void _rebuildLiveElements() {
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }

  static void _applyPalette(bool dark) {
    if (dark) {
      SageColors._useDark();
    } else {
      SageColors._useLight();
    }
  }
}

/// Sage Spring color palette — A2.
///
/// Two groups of tokens:
///
/// 1. Palette tokens (moss, mossLight, sage, linen, card, clay, amber,
///    ink, inkSoft, line) — these flip between light and dark values
///    when the mode changes. Every screen reads these and gets the
///    correct value automatically.
///
/// 2. Hero card tokens (heroBg, heroNumber, heroLabel, …) — the hero
///    card sits on a dark green panel regardless of app-wide theme, so
///    its foreground tokens (number, label, wave) are mode-invariant.
///    Only heroBg changes between light and dark.
class SageColors {
  SageColors._();

  // ── Light palette ─────────────────────────────────────────────────────────

  /// Primary green. Vivid leaf — fresh and energetic, not dark-forest.
  static const Color _lightMoss = Color(0xFF1E7A50);

  /// Lighter primary — used for hover states, softer icon backgrounds.
  static const Color _lightMossLight = Color(0xFF4F9776);

  /// Muted mid-green — used for progress bars, chips, gentle highlights.
  static const Color _lightSage = Color(0xFF70AA8C);

  /// Page background. Green-tinted near-white — clean but not clinical.
  static const Color _lightLinen = Color(0xFFF4F9F4);

  /// Card surface. Pure white for maximum contrast against the tinted bg.
  static const Color _lightCard = Color(0xFFFFFFFF);

  /// Raised surface in light mode: same white as cards; elevation there
  /// comes from a soft shadow instead of a lighter layer.
  static const Color _lightCardRaised = Color(0xFFFFFFFF);

  /// Warm coral-orange accent. Replaces the old clay; slightly brighter
  /// and more vibrant so it reads as a real second color, not a wash.
  static const Color _lightClay = Color(0xFFE8714A);

  /// Golden amber accent. Third accent for sleep/warmth contexts.
  static const Color _lightAmber = Color(0xFFE8A832);

  /// Primary text. Deep green-tinted near-black — warmer than pure #000.
  static const Color _lightInk = Color(0xFF141C18);

  /// Secondary / muted text. Green-grey, legible on white and on linen.
  static const Color _lightInkSoft = Color(0xFF607668);

  /// Hairline separator / border. Subtle green tint, light enough to be
  /// invisible on white cards but visible as structure against linen bg.
  static const Color _lightLine = Color(0xFFD8EBDE);

  /// Hero card panel background in light mode. Using the primary green
  /// directly gives the hero its identity without needing a special shade.
  static const Color _lightHeroBg = Color(0xFF1E7A50);

  // ── Dark palette — "Sage Noir" ───────────────────────────────────────────
  //
  // True black page background with vivid, saturated accents instead of
  // muted/dusty ones — fixes the "old and boring" feel of earlier passes.

  /// Primary green in dark mode. Vivid mint-emerald — the color that
  /// sets the "fresh" tone for the whole dark palette.
  static const Color _darkMoss = Color(0xFF4CCB8D);

  /// Lighter primary dark. Used for active nav indicators, selected states.
  static const Color _darkMossLight = Color(0xFF7DDDB0);

  /// Muted mid-green dark. Subtler than _darkMoss; suits dividers,
  /// background tints, and the Chronic Care activity tile accent where
  /// full-saturation moss would be too loud.
  static const Color _darkSage = Color(0xFF62B493);

  /// Page background dark. #0A0D0B — genuinely black, with only a
  /// whisper of green so it still feels like Sage.
  static const Color _darkLinen = Color(0xFF101713);

  /// Raised surface dark (sheets, dialogs, snackbars) — the third layer.
  static const Color _darkCardRaised = Color(0xFF202D26);

  /// Card surface dark. Lifted from the bg so cards float without
  /// needing shadows. #141B17 — still dark but visibly distinct.
  static const Color _darkCard = Color(0xFF18221D);

  /// Clay accent in dark mode. Punchy coral instead of dusty terracotta.
  static const Color _darkClay = Color(0xFFF28D6E);

  /// Amber accent in dark mode. Clean saturated gold instead of muddy ochre.
  static const Color _darkAmber = Color(0xFFF4BF5A);

  /// Primary text in dark mode. Near-white with a faint green cast —
  /// easier on the eye than pure white against true black.
  static const Color _darkInk = Color(0xFFE9F3EC);

  /// Secondary text in dark mode. Mid green-grey, lifted enough to stay
  /// legible against the black page.
  static const Color _darkInkSoft = Color(0xFFA3B8AC);

  /// Separator / border in dark mode. Just light enough to register
  /// against true black.
  static const Color _darkLine = Color(0xFF2D3B34);

  /// Hero card panel bg in dark mode. #113A28 — a saturated emerald in
  /// the same hue family as the moss accent (not a grayed-down olive).
  /// Lighter than the very first near-black hero attempt, but still
  /// darker than the card surface so it keeps its identity as the
  /// dashboard's anchor element.
  static const Color _darkHeroBg = Color(0xFF1A5239);

  // ── Hero foreground ─────────────────────────────────────────────────────
  //
  // Rendered on the hero panel, which is a different green in each mode, so
  // the text tiers are tuned per mode to keep AA contrast on their panel.

  static const Color _lightHeroNumber = Color(0xFFEEF8F2);
  static const Color _lightHeroLabel = Color(0xFFEDF7F1);
  static const Color _lightHeroLabelMuted = Color(0xFFE3F2E9);
  static const Color _lightHeroSubLabel = Color(0xFFE1F2E8);

  static const Color _darkHeroNumber = Color(0xFFF1FAF4);
  static const Color _darkHeroLabel = Color(0xFFCFE8D8);
  static const Color _darkHeroLabelMuted = Color(0xFFA9CDB8);
  static const Color _darkHeroSubLabel = Color(0xFF9CC3AB);

  /// The pulse wave line color.
  static const Color _heroLine = Color(0xFF5FCB98);

  /// The green dot when band is connected.
  static const Color _heroAccentOk = Color(0xFF68DC98);

  /// The amber dot when band is disconnected.
  static const Color _heroAccentWarn = Color(0xFFFFB040);

  /// Text/icons on a solid accent fill: white on the light-mode accents,
  /// deep ink on the lifted dark-mode accents.
  static const Color _lightOnAccent = Color(0xFFFFFFFF);
  static const Color _darkOnAccent = Color(0xFF0B1410);

  // ── Mutable palette fields (swapped on mode change) ───────────────────────

  static Color moss = _lightMoss;
  static Color mossLight = _lightMossLight;
  static Color sage = _lightSage;
  static Color linen = _lightLinen;
  static Color card = _lightCard;
  static Color cardRaised = _lightCardRaised;
  static Color onAccent = _lightOnAccent;
  static Color clay = _lightClay;
  static Color amber = _lightAmber;
  static Color ink = _lightInk;
  static Color inkSoft = _lightInkSoft;
  static Color line = _lightLine;

  static Color heroBg = _lightHeroBg;
  static Color heroNumber = _lightHeroNumber;
  static Color heroLabel = _lightHeroLabel;
  static Color heroLabelMuted = _lightHeroLabelMuted;
  static Color heroSubLabel = _lightHeroSubLabel;
  static Color heroLine = _heroLine;
  static Color heroAccentOk = _heroAccentOk;
  static Color heroAccentWarn = _heroAccentWarn;

  static bool get isDark => ThemeController.isDark.value;

  /// Surface for bars that sit above the page (bottom navigation): the page
  /// color in light mode, the card layer in dark mode.
  static Color get chrome => isDark ? card : linen;

  /// A fixed accent [color] made readable on the current card surface. In
  /// light mode it is returned unchanged. In dark mode its lightness is
  /// raised, keeping hue and saturation, until it reaches [minContrast]
  /// against [card] (deep tones like #145A32 would otherwise disappear).
  static Color legible(Color color, {double minContrast = 4.5}) {
    if (!isDark) return color;
    var hsl = HSLColor.fromColor(color);
    for (var i = 0;
        i < 40 && _contrast(hsl.toColor(), card) < minContrast;
        i++) {
      final next = (hsl.lightness + 0.02).clamp(0.0, 0.9);
      if (next == hsl.lightness) break;
      hsl = hsl.withLightness(next);
    }
    return hsl.toColor();
  }

  /// Text/icon color for an arbitrary accent [fill]. Light mode keeps white;
  /// dark mode picks whichever of white or deep ink contrasts more.
  static Color onFill(Color fill) {
    if (!isDark) return _lightOnAccent;
    return _contrast(_darkOnAccent, fill) >= _contrast(_lightOnAccent, fill)
        ? _darkOnAccent
        : _lightOnAccent;
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Drop-shadow color at [alpha] (the value used in light mode). Dark
  /// surfaces separate mostly by layer, so their shadows only double up to
  /// stay perceptible against the darker page, never a heavy glow.
  static Color shadow(double alpha) => const Color(0xFF000000)
      .withValues(alpha: isDark ? (alpha * 2).clamp(0.0, 0.3) : alpha);

  static void _useLight() {
    moss = _lightMoss;
    mossLight = _lightMossLight;
    sage = _lightSage;
    linen = _lightLinen;
    card = _lightCard;
    cardRaised = _lightCardRaised;
    onAccent = _lightOnAccent;
    clay = _lightClay;
    amber = _lightAmber;
    ink = _lightInk;
    inkSoft = _lightInkSoft;
    line = _lightLine;
    heroBg = _lightHeroBg;
    heroNumber = _lightHeroNumber;
    heroLabel = _lightHeroLabel;
    heroLabelMuted = _lightHeroLabelMuted;
    heroSubLabel = _lightHeroSubLabel;
    heroLine = _heroLine;
    heroAccentOk = _heroAccentOk;
    heroAccentWarn = _heroAccentWarn;
  }

  static void _useDark() {
    moss = _darkMoss;
    mossLight = _darkMossLight;
    sage = _darkSage;
    linen = _darkLinen;
    card = _darkCard;
    cardRaised = _darkCardRaised;
    onAccent = _darkOnAccent;
    clay = _darkClay;
    amber = _darkAmber;
    ink = _darkInk;
    inkSoft = _darkInkSoft;
    line = _darkLine;
    heroBg = _darkHeroBg;
    heroNumber = _darkHeroNumber;
    heroLabel = _darkHeroLabel;
    heroLabelMuted = _darkHeroLabelMuted;
    heroSubLabel = _darkHeroSubLabel;
    heroLine = _heroLine;
    heroAccentOk = _heroAccentOk;
    heroAccentWarn = _heroAccentWarn;
  }
}

/// Type scale for Sage Health. All Nunito except the pull-quote.
class SageText {
  SageText._();

  /// The "sage" wordmark.
  static TextStyle wordmark({Color? color}) => GoogleFonts.nunito(
        fontWeight: FontWeight.w800,
        fontSize: 24,
        letterSpacing: -0.2,
        color: color ?? SageColors.moss,
      );

  /// Screen and hero headline.
  static TextStyle headline({Color? color}) => GoogleFonts.nunito(
        fontWeight: FontWeight.w800,
        fontSize: 26,
        height: 1.2,
        letterSpacing: -0.2,
        color: color ?? SageColors.ink,
      );

  /// Card and section title, one step below [headline].
  static TextStyle title({Color? color}) => GoogleFonts.nunito(
        fontWeight: FontWeight.w700,
        fontSize: 18,
        height: 1.3,
        color: color ?? SageColors.ink,
      );

  /// Default reading text. A touch of extra line height gives it air.
  static TextStyle body({Color? color}) => GoogleFonts.nunito(
        fontSize: 15,
        height: 1.5,
        color: color ?? SageColors.ink,
      );

  /// Secondary and helper text.
  static TextStyle caption({Color? color}) => GoogleFonts.nunito(
        fontSize: 13,
        height: 1.45,
        color: color ?? SageColors.inkSoft,
      );

  /// Short labels on controls and tiles.
  static TextStyle label({Color? color, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.nunito(
        fontSize: 14,
        fontWeight: weight,
        color: color ?? SageColors.ink,
      );

  /// Pull-quote / inspirational copy — italic Fraunces w400.
  static TextStyle quote({Color? color}) => GoogleFonts.fraunces(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        fontSize: 16.5,
        height: 1.5,
        color: color ?? SageColors.ink,
      );

  /// Numbers (BPM, steps, scores, kcal): rounded, with tabular figures so a
  /// changing value does not jiggle its neighbours.
  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) =>
      GoogleFonts.nunito(
        fontSize: size,
        fontWeight: weight,
        color: color ?? SageColors.ink,
        letterSpacing: letterSpacing,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

class SageTheme {
  SageTheme._();

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: SageColors.moss,
        brightness: brightness,
        primary: SageColors.moss,
        secondary: SageColors.clay,
        surface: SageColors.card,
      ),
      scaffoldBackgroundColor: SageColors.linen,
    );

    // google_fonts builds a package:flutter TextTheme; copy its styles into
    // the material_ui TextTheme that [ThemeData] expects.
    final styled = GoogleFonts.nunitoTextTheme(
      fm.TextTheme(
        displayLarge: base.textTheme.displayLarge,
        displayMedium: base.textTheme.displayMedium,
        displaySmall: base.textTheme.displaySmall,
        headlineLarge: base.textTheme.headlineLarge,
        headlineMedium: base.textTheme.headlineMedium,
        headlineSmall: base.textTheme.headlineSmall,
        titleLarge: base.textTheme.titleLarge,
        titleMedium: base.textTheme.titleMedium,
        titleSmall: base.textTheme.titleSmall,
        bodyLarge: base.textTheme.bodyLarge,
        bodyMedium: base.textTheme.bodyMedium,
        bodySmall: base.textTheme.bodySmall,
        labelLarge: base.textTheme.labelLarge,
        labelMedium: base.textTheme.labelMedium,
        labelSmall: base.textTheme.labelSmall,
      ),
    );
    final textTheme = TextTheme(
      displayLarge: styled.displayLarge,
      displayMedium: styled.displayMedium,
      displaySmall: styled.displaySmall,
      headlineLarge: styled.headlineLarge,
      headlineMedium: styled.headlineMedium,
      headlineSmall: styled.headlineSmall,
      titleLarge: styled.titleLarge,
      titleMedium: styled.titleMedium,
      titleSmall: styled.titleSmall,
      bodyLarge: styled.bodyLarge,
      bodyMedium: styled.bodyMedium,
      bodySmall: styled.bodySmall,
      labelLarge: styled.labelLarge,
      labelMedium: styled.labelMedium,
      labelSmall: styled.labelSmall,
    ).apply(
      bodyColor: SageColors.ink,
      displayColor: SageColors.ink,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: SageColors.ink,
        centerTitle: false,
        titleTextStyle: SageText.headline().copyWith(fontSize: 22),
        iconTheme: IconThemeData(color: SageColors.ink),
      ),
      iconTheme: IconThemeData(color: SageColors.ink),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SageColors.moss,
          foregroundColor: SageColors.onAccent,
          minimumSize: const Size(64, 52),
          textStyle: GoogleFonts.nunito(
              fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SageRadius.control + 4),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SageColors.moss,
          minimumSize: const Size(64, 52),
          textStyle: GoogleFonts.nunito(
              fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.2),
          side: BorderSide(color: SageColors.moss),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SageRadius.control + 4),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SageColors.moss,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SageColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SageRadius.control),
          borderSide: BorderSide(color: SageColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SageRadius.control),
          borderSide: BorderSide(color: SageColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SageRadius.control),
          borderSide: BorderSide(color: SageColors.moss, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SageRadius.control),
          borderSide: BorderSide(color: SageColors.clay, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SageRadius.control),
          borderSide: BorderSide(color: SageColors.clay, width: 1.5),
        ),
        hintStyle: TextStyle(color: SageColors.inkSoft),
        labelStyle: TextStyle(color: SageColors.inkSoft),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return SageColors.moss;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(SageColors.linen),
        side: BorderSide(color: SageColors.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return SageColors.linen;
          return SageColors.inkSoft;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return SageColors.moss;
          return SageColors.line;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: SageColors.moss,
        inactiveTrackColor: SageColors.line,
        thumbColor: SageColors.moss,
        overlayColor: SageColors.moss.withValues(alpha: 0.12),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: SageColors.moss,
        labelColor: SageColors.moss,
        unselectedLabelColor: SageColors.inkSoft,
        indicatorSize: TabBarIndicatorSize.label,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: SageColors.linen,
        selectedColor: SageColors.moss.withValues(alpha: 0.15),
        labelStyle: TextStyle(color: SageColors.ink),
        side: BorderSide(color: SageColors.line),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SageRadius.pill)),
      ),
      dividerTheme: DividerThemeData(
        color: SageColors.line,
        thickness: 0.5,
        space: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SageColors.chrome,
        indicatorColor: SageColors.moss.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(fontSize: 11, color: SageColors.inkSoft),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: SageColors.cardRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: SageRadius.card),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: SageColors.cardRaised,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: SageColors.cardRaised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? SageColors.cardRaised : SageColors.ink,
        contentTextStyle: TextStyle(
          color: isDark ? SageColors.ink : SageColors.linen,
        ),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SageRadius.control)),
        behavior: SnackBarBehavior.floating,
      ),
      cardColor: SageColors.card,
      dividerColor: SageColors.line,
    );
  }

  static ThemeData get light => _build(brightness: Brightness.light);
  static ThemeData get dark => _build(brightness: Brightness.dark);
}
