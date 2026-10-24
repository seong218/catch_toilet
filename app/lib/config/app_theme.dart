import 'package:flutter/material.dart';

class AppTheme {
  static const ink = Color(0xFF163B36);
  static const green = Color(0xFF136F59);
  static const canvas = Color(0xFFF5F7F3);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: green,
      surface: const Color(0xFFFEFFFC),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: ink,
          height: 1.25,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.3,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE1E8DF)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: const Color(0xFFDDEFE2),
      ),
    );
  }
}
