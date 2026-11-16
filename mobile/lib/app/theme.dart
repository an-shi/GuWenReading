import 'package:flutter/material.dart';

import '../core/storage/settings_controller.dart';

const paperBackground = Color(0xFFF1E9DB);
const paperSurface = Color(0xFFFBF7EF);
const inkGreen = Color(0xFF1C5A4C);
const inkDark = Color(0xFF101C18);
const brass = Color(0xFF9A6A34);

ThemeData buildTheme(AppSettings settings) {
  final dark = settings.themeMode == 'dark';
  final paper = settings.themeMode == 'paper';
  final brightness = dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: inkGreen,
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFF7FB9A8) : inkGreen,
    secondary: dark ? const Color(0xFFC8A06A) : brass,
    surface: dark ? const Color(0xFF18211D) : (paper ? paperSurface : Colors.white),
    onSurface: dark ? const Color(0xFFE7E2D6) : const Color(0xFF2D2A24),
    error: dark ? const Color(0xFFD17872) : const Color(0xFFA53B35),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF111815) : (paper ? paperBackground : const Color(0xFFF5F6F3)),
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
  );
  final serif = base.textTheme.copyWith(
    displaySmall: base.textTheme.displaySmall?.copyWith(
      fontFamily: 'serif',
      fontWeight: FontWeight.w600,
      letterSpacing: 1,
    ),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      fontFamily: 'serif',
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontFamily: 'serif',
      fontWeight: FontWeight.w600,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
  );
  return base.copyWith(
    textTheme: serif,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: serif.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontSize: 20,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF18211D) : (paper ? paperSurface : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF151F1B) : (paper ? paperSurface : Colors.white),
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      elevation: 0,
      height: 70,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.66)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF22302A) : Colors.white.withValues(alpha: 0.72),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.onSurface.withValues(alpha: 0.08),
      thickness: 1,
    ),
  );
}
