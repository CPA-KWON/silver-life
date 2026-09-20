import 'package:flutter/material.dart';

/// Warm, high-contrast, large-touch-target theme for senior users:
/// bigger text, taller buttons, and a bottom navigation bar instead of
/// a drawer so screens stay simple to navigate.
final ThemeData seniorFriendlyTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8630A)),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 18),
    bodyMedium: TextStyle(fontSize: 16),
    titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
  ),
  navigationBarTheme: NavigationBarThemeData(
    height: 72,
    labelTextStyle: WidgetStateProperty.all(
      const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  ),
);
