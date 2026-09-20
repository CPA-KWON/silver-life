import 'package:flutter/material.dart';

/// Brand palette. Unlike the earlier pastel palettes, [_primary] is dark
/// enough (~5.2:1 contrast) for white text/icons to sit directly on it, so
/// it drives both structural chrome (app bar) and CTAs (buttons). [_accent]
/// and [_highlight] are lighter and still need dark ink text on top of them.
const _primary = Color(0xFF2563EB);
const _dark = Color(0xFF0B1220);
const _surface = Color(0xFFF5F8FF);
const _accent = Color(0xFF60A5FA);
const _highlight = Color(0xFFE0EAFF);

const _divider = Color(0xFFE2E5EA);
const _textPrimary = _dark;
const _textMuted = Color(0xFF6B7280);
// The bottom nav bar is dark, so its own muted/inactive tone needs to read
// on _dark instead of on white like _textMuted does.
const _textMutedOnDark = Color(0xFF9AA9C4);

const _fontFamily = 'Pretendard';

/// High-contrast, large-touch-target theme for senior users, with a
/// deliberate blue brand palette instead of an auto-generated Material seed
/// color: bigger text, taller buttons, and a bottom navigation bar instead
/// of a drawer so screens stay simple to navigate.
final ThemeData seniorFriendlyTheme = ThemeData(
  useMaterial3: true,
  fontFamily: _fontFamily,
  scaffoldBackgroundColor: _surface,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: _primary,
    onPrimary: Colors.white,
    secondary: _accent,
    onSecondary: _textPrimary,
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
    backgroundColor: _dark,
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
    backgroundColor: _dark,
    indicatorColor: _accent.withValues(alpha: 0.2),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? _accent : _textMutedOnDark,
      );
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return IconThemeData(color: selected ? _accent : _textMutedOnDark);
    }),
  ),

  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: _primary,
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
      foregroundColor: _primary,
      side: const BorderSide(color: _primary, width: 1.5),
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
    backgroundColor: _highlight,
    selectedColor: _primary,
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
      borderSide: const BorderSide(color: _primary, width: 2),
    ),
  ),

  dividerTheme: const DividerThemeData(color: _divider, thickness: 1, space: 1),
);
