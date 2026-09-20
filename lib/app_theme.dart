import 'package:flutter/material.dart';

/// Brand palette: a navy structural color (app bar, nav bar, headings) reads
/// as trustworthy/professional, while orange is reserved for call-to-action
/// buttons only — keeping the warmth senior users respond to without
/// tinting the whole app orange.
const _navy = Color(0xFF16264D);
const _accentOrange = Color(0xFFE8630A);
const _pageBackground = Color(0xFFF5F6F8);
const _divider = Color(0xFFE2E5EA);
const _textPrimary = Color(0xFF1A1A1A);
const _textMuted = Color(0xFF6B7280);

const _fontFamily = 'Pretendard';

/// High-contrast, large-touch-target theme for senior users, with a
/// deliberate navy/orange brand palette instead of an auto-generated
/// Material seed color: bigger text, taller buttons, and a bottom
/// navigation bar instead of a drawer so screens stay simple to navigate.
final ThemeData seniorFriendlyTheme = ThemeData(
  useMaterial3: true,
  fontFamily: _fontFamily,
  scaffoldBackgroundColor: _pageBackground,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _navy,
    brightness: Brightness.light,
  ).copyWith(
    primary: _navy,
    onPrimary: Colors.white,
    secondary: _accentOrange,
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: _textPrimary,
    outline: _divider,
  ),

  textTheme: const TextTheme(
    titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _textPrimary),
    titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _textPrimary),
    bodyLarge: TextStyle(fontSize: 18, color: _textPrimary),
    bodyMedium: TextStyle(fontSize: 16, color: _textMuted),
    labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  ),

  appBarTheme: const AppBarTheme(
    backgroundColor: _navy,
    foregroundColor: Colors.white,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
  ),

  navigationBarTheme: NavigationBarThemeData(
    height: 72,
    backgroundColor: Colors.white,
    indicatorColor: _navy.withValues(alpha: 0.1),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? _navy : _textMuted,
      );
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return IconThemeData(color: selected ? _navy : _textMuted);
    }),
  ),

  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: _accentOrange,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: _navy,
      side: const BorderSide(color: _navy, width: 1.5),
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
  ),

  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _divider),
    ),
  ),

  chipTheme: ChipThemeData(
    backgroundColor: Colors.white,
    selectedColor: _navy,
    shape: const StadiumBorder(side: BorderSide(color: _divider)),
    labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _textPrimary),
    secondaryLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    labelStyle: const TextStyle(color: _textMuted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _navy, width: 2),
    ),
  ),

  dividerTheme: const DividerThemeData(color: _divider, thickness: 1, space: 1),
);
