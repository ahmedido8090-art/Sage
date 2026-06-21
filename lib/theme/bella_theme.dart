import 'package:flutter/material.dart';

class BellaColors {
  static const Color background = Color(0xFF0F0F17);
  static const Color surface = Color(0xFF171926);
  static const Color surfaceAlt = Color(0xFF1E2233);
  static const Color surfaceSoft = Color(0xFF262B3F);

  static const Color primary = Color(0xFFA78BFA);
  static const Color primaryDeep = Color(0xFF8B5CF6);
  static const Color secondary = Color(0xFF60A5FA);
  static const Color accent = Color(0xFF2DD4BF);

  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFB7185);

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFFB6BED3);
  static const Color textMuted = Color(0xFF8891A9);
  static const Color divider = Color(0xFF2B3146);

  static const Color cardGlow = Color(0x332DD4BF);

  static const LinearGradient appGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF121321), Color(0xFF181A2D), Color(0xFF0F0F17)],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF60A5FA), Color(0xFF2DD4BF)],
  );
}

class BellaTheme {
  static ThemeData get darkTheme {
    final colorScheme = const ColorScheme.dark(
      primary: BellaColors.primary,
      secondary: BellaColors.secondary,
      surface: BellaColors.surface,
      error: BellaColors.danger,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: BellaColors.textPrimary,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: BellaColors.background,
      fontFamily: 'Roboto',
      dividerColor: BellaColors.divider,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: BellaColors.textPrimary,
        titleTextStyle: TextStyle(
          color: BellaColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: BellaColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: BellaColors.divider),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BellaColors.surfaceAlt,
        labelStyle: const TextStyle(color: BellaColors.textSecondary),
        hintStyle: const TextStyle(color: BellaColors.textMuted),
        prefixIconColor: BellaColors.primary,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: BellaColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: BellaColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: BellaColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: BellaColors.danger, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: BellaColors.divider),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BellaColors.surfaceSoft,
        contentTextStyle: const TextStyle(color: BellaColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BellaColors.primaryDeep,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BellaColors.textPrimary,
          side: const BorderSide(color: BellaColors.divider),
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: BellaColors.surface,
        indicatorColor: BellaColors.primary.withOpacity(0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color:
                selected ? BellaColors.textPrimary : BellaColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? BellaColors.primary : BellaColors.textSecondary,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: BellaColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          color: BellaColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: BellaColors.textSecondary,
          fontSize: 14,
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: BellaColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 30,
        ),
        headlineMedium: TextStyle(
          color: BellaColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 24,
        ),
        titleLarge: TextStyle(
          color: BellaColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
        titleMedium: TextStyle(
          color: BellaColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        bodyLarge: TextStyle(color: BellaColors.textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: BellaColors.textSecondary, fontSize: 14),
        bodySmall: TextStyle(color: BellaColors.textMuted, fontSize: 12),
      ),
    );
  }
}
