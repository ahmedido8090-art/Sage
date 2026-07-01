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
// Dark mode went through several revisions before landing here — "Sage
// Dusk" (desaturated near-black) read flat and heavy; "Moss Twilight"
// (lighter mid-tone dim) read muddy and dated. "Sage Noir" is the fix:
// a genuinely black page background with vivid, saturated accents
// instead of muted/dusty ones, so the app feels fresh rather than old.
//   Page bg dark:   #0A0D0B   true black, only a whisper of green
//   Card dark:      #141B17   lifted from bg so cards float without shadow
//   Hero bg dark:   #113A28   saturated emerald — same hue family as the
//                              moss accent, not a grayed-down olive. Sits
//                              lighter than the very first black-hero
//                              attempt, but still reads as the anchor
//                              surface since it's darker than card.
//   Moss dark:      #2EE6A0   vivid mint-emerald, not muted forest green
//   Clay dark:      #FF7A59   punchy coral, not dusty terracotta
//   Amber dark:     #FFC247   clean saturated gold, not muddy ochre
//
// Everything else (mossLight, sage, ink, line, hero tokens) is derived
// from those anchors by lightening/darkening/blending — not invented
// independently — so the palette stays internally coherent.
//
// Typography: Manrope (wordmark, headlines — swapped from Fraunces italic,
// which read too ornate for the brand), Inter (all UI body text),
// IBM Plex Mono (biometric numbers). Fraunces italic is kept only for
// pull-quotes, where an editorial voice still fits.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls light/dark mode app-wide and persists the choice.
///
/// [SageColors]' fields are mutable static fields that get swapped in place
/// when the mode changes. Wrapping the app root in a
/// `ValueListenableBuilder<bool>` on [ThemeController.isDark] forces a full
/// rebuild whenever that happens, so every screen picks up the new colors
/// automatically without threading Theme.of(context) everywhere.
class ThemeController {
  ThemeController._();

  static const _prefsKey = 'sage_dark_mode';

  static final ValueNotifier<bool> isDark = ValueNotifier(false);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefsKey) ?? false;
    isDark.value = saved;
    _applyPalette();
  }

  static Future<void> setDark(bool value) async {
    if (isDark.value == value) return;
    isDark.value = value;
    _applyPalette();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  static Future<void> toggle() => setDark(!isDark.value);

  static void _applyPalette() {
    if (isDark.value) {
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
  static const Color _darkMoss = Color(0xFF2EE6A0);

  /// Lighter primary dark. Used for active nav indicators, selected states.
  static const Color _darkMossLight = Color(0xFF5FF0BE);

  /// Muted mid-green dark. Subtler than _darkMoss; suits dividers,
  /// background tints, and the Chronic Care activity tile accent where
  /// full-saturation moss would be too loud.
  static const Color _darkSage = Color(0xFF4F9B83);

  /// Page background dark. #0A0D0B — genuinely black, with only a
  /// whisper of green so it still feels like Sage.
  static const Color _darkLinen = Color(0xFF0A0D0B);

  /// Card surface dark. Lifted from the bg so cards float without
  /// needing shadows. #141B17 — still dark but visibly distinct.
  static const Color _darkCard = Color(0xFF141B17);

  /// Clay accent in dark mode. Punchy coral instead of dusty terracotta.
  static const Color _darkClay = Color(0xFFFF7A59);

  /// Amber accent in dark mode. Clean saturated gold instead of muddy ochre.
  static const Color _darkAmber = Color(0xFFFFC247);

  /// Primary text in dark mode. Near-white with a faint green cast —
  /// easier on the eye than pure white against true black.
  static const Color _darkInk = Color(0xFFF5FBF7);

  /// Secondary text in dark mode. Mid green-grey, lifted enough to stay
  /// legible against the black page.
  static const Color _darkInkSoft = Color(0xFF86998F);

  /// Separator / border in dark mode. Just light enough to register
  /// against true black.
  static const Color _darkLine = Color(0xFF1F2A24);

  /// Hero card panel bg in dark mode. #113A28 — a saturated emerald in
  /// the same hue family as the moss accent (not a grayed-down olive).
  /// Lighter than the very first near-black hero attempt, but still
  /// darker than the card surface so it keeps its identity as the
  /// dashboard's anchor element.
  static const Color _darkHeroBg = Color(0xFF113A28);

  // ── Hero foreground (mode-invariant) ─────────────────────────────────────
  //
  // These are always rendered on top of a dark green hero panel (either
  // _lightHeroBg or _darkHeroBg). Because the panel is always dark, these
  // tokens don't need to flip with the rest of the palette.

  /// The large BPM number. Near-white, green-tinted.
  static const Color _heroNumber = Color(0xFFEEF8F2);

  /// The connection status chip text.
  static const Color _heroLabel = Color(0xFFC0E0CC);

  /// Battery percentage and secondary chip text. More muted.
  static const Color _heroLabelMuted = Color(0xFF88B89E);

  /// "Resting · steady" subtitle line.
  static const Color _heroSubLabel = Color(0xFF78A88E);

  /// The pulse wave line color. Brightened slightly alongside the "Sage
  /// Noir" pass so it doesn't look flat against the more saturated
  /// _darkHeroBg.
  static const Color _heroLine = Color(0xFF5FCB98);

  /// The green dot when band is connected.
  static const Color _heroAccentOk = Color(0xFF68DC98);

  /// The amber dot when band is disconnected.
  static const Color _heroAccentWarn = Color(0xFFFFB040);

  // ── Mutable palette fields (swapped on mode change) ───────────────────────

  static Color moss      = _lightMoss;
  static Color mossLight = _lightMossLight;
  static Color sage      = _lightSage;
  static Color linen     = _lightLinen;
  static Color card      = _lightCard;
  static Color clay      = _lightClay;
  static Color amber     = _lightAmber;
  static Color ink       = _lightInk;
  static Color inkSoft   = _lightInkSoft;
  static Color line      = _lightLine;

  static Color heroBg          = _lightHeroBg;
  static Color heroNumber      = _heroNumber;
  static Color heroLabel       = _heroLabel;
  static Color heroLabelMuted  = _heroLabelMuted;
  static Color heroSubLabel    = _heroSubLabel;
  static Color heroLine        = _heroLine;
  static Color heroAccentOk    = _heroAccentOk;
  static Color heroAccentWarn  = _heroAccentWarn;

  static bool get isDark => ThemeController.isDark.value;

  static void _useLight() {
    moss      = _lightMoss;
    mossLight = _lightMossLight;
    sage      = _lightSage;
    linen     = _lightLinen;
    card      = _lightCard;
    clay      = _lightClay;
    amber     = _lightAmber;
    ink       = _lightInk;
    inkSoft   = _lightInkSoft;
    line      = _lightLine;
    heroBg    = _lightHeroBg;
    // Hero foreground tokens are mode-invariant; reassigning them here
    // is a no-op but makes the symmetry with _useDark explicit.
    heroNumber     = _heroNumber;
    heroLabel      = _heroLabel;
    heroLabelMuted = _heroLabelMuted;
    heroSubLabel   = _heroSubLabel;
    heroLine       = _heroLine;
    heroAccentOk   = _heroAccentOk;
    heroAccentWarn = _heroAccentWarn;
  }

  static void _useDark() {
    moss      = _darkMoss;
    mossLight = _darkMossLight;
    sage      = _darkSage;
    linen     = _darkLinen;
    card      = _darkCard;
    clay      = _darkClay;
    amber     = _darkAmber;
    ink       = _darkInk;
    inkSoft   = _darkInkSoft;
    line      = _darkLine;
    heroBg    = _darkHeroBg;
    heroNumber     = _heroNumber;
    heroLabel      = _heroLabel;
    heroLabelMuted = _heroLabelMuted;
    heroSubLabel   = _heroSubLabel;
    heroLine       = _heroLine;
    heroAccentOk   = _heroAccentOk;
    heroAccentWarn = _heroAccentWarn;
  }
}

/// Type scale for Sage Health.
///
/// Three fonts, three distinct roles:
///   Manrope    — wordmark and section headlines. Swapped from Fraunces
///                italic, which read too ornate for the brand; Manrope's
///                rounded terminals stay calm without going editorial.
///   Fraunces   — pull-quotes only now. Italic + w400 keeps an editorial
///                voice for inspirational copy without touching the
///                wordmark or headlines.
///   Inter      — all UI body text, labels, buttons, navigation.
///                Applied app-wide via [SageTheme]; nothing needs to
///                import it explicitly.
///   IBM Plex Mono — biometric numbers only (BPM, steps, scores, kcal).
///                Makes instrument data read as data, not as labels.
class SageText {
  SageText._();

  /// The "sage" wordmark — Manrope, upright, w700. Swapped from italic
  /// Fraunces, which read too fancy/ornate for the brand's voice.
  static TextStyle wordmark({Color? color}) => GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        fontSize: 22,
        color: color ?? SageColors.moss,
      );

  /// Section headline — Manrope w700, generous line height. Swapped from
  /// Fraunces upright for the same reason as the wordmark.
  static TextStyle headline({Color? color}) => GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        fontSize: 25,
        height: 1.25,
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

  /// Biometric number — IBM Plex Mono. Only for numbers that should
  /// read like instrument readouts: BPM, step count, wellness score,
  /// calorie count, pillar score bars.
  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        color: color ?? SageColors.ink,
        letterSpacing: letterSpacing,
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
        primary:   SageColors.moss,
        secondary: SageColors.clay,
        surface:   SageColors.card,
      ),
      scaffoldBackgroundColor: SageColors.linen,
    );

    final textTheme = GoogleFonts.interTextTheme(
      isDark
          ? base.textTheme.apply(
              bodyColor:    SageColors.ink,
              displayColor: SageColors.ink,
            )
          : base.textTheme,
    ).apply(
      bodyColor:    SageColors.ink,
      displayColor: SageColors.ink,
    );

    return base.copyWith(
      textTheme: textTheme,

      appBarTheme: const AppBarTheme(
        backgroundColor:  Colors.transparent,
        elevation:        0,
        surfaceTintColor: Colors.transparent,
      ),

      iconTheme: IconThemeData(color: SageColors.ink),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SageColors.moss,
          foregroundColor: SageColors.linen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SageColors.moss,
          side: BorderSide(color: SageColors.moss),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SageColors.moss,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled:      true,
        fillColor:   SageColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   BorderSide(color: SageColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   BorderSide(color: SageColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   BorderSide(color: SageColors.moss, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   BorderSide(color: SageColors.clay, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   BorderSide(color: SageColors.clay, width: 1.5),
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
        activeTrackColor:   SageColors.moss,
        inactiveTrackColor: SageColors.line,
        thumbColor:         SageColors.moss,
        overlayColor:       SageColors.moss.withValues(alpha: 0.12),
      ),

      tabBarTheme: 
      TabBarThemeData(
        indicatorColor:   SageColors.moss,
        labelColor:       SageColors.moss,
        unselectedLabelColor: SageColors.inkSoft,
        indicatorSize:    TabBarIndicatorSize.label,
      ),

      chipTheme: ChipThemeData(
        backgroundColor:    SageColors.linen,
        selectedColor:      SageColors.moss.withValues(alpha: 0.15),
        labelStyle:         TextStyle(color: SageColors.ink),
        side:               BorderSide(color: SageColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      dividerTheme: DividerThemeData(
        color:     SageColors.line,
        thickness: 0.5,
        space:     0,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:  SageColors.linen,
        indicatorColor:   SageColors.moss.withValues(alpha: 0.15),
        labelTextStyle:   WidgetStateProperty.all(
          TextStyle(fontSize: 11, color: SageColors.inkSoft),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:  SageColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? SageColors.card : SageColors.ink,
        contentTextStyle: TextStyle(
          color: isDark ? SageColors.ink : SageColors.linen,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      cardColor:    SageColors.card,
      dividerColor: SageColors.line,
    );
  }

  static ThemeData get light => _build(brightness: Brightness.light);
  static ThemeData get dark  => _build(brightness: Brightness.dark);
}