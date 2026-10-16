import 'package:flutter/material.dart';

/// Brand palette shared by the theme and by widgets that need a raw color.
/// [primary] is dark enough (~6:1) for white text to sit directly on it; the
/// gradient pair is only for large hero areas, never for text-bearing controls.
abstract final class AppColors {
  static const primary = Color(0xFF4F46E5);
  static const gradientStart = Color(0xFF5A67F2);
  static const gradientEnd = Color(0xFF7C6CF6);

  /// Lavender wash for chip/icon backgrounds and the selected nav pill.
  static const tint = Color(0xFFEEF0FE);
  static const background = Color(0xFFF7F8FC);
  static const surface = Color(0xFFFFFFFF);

  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const border = Color(0xFFE6E8F0);

  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF15803D);

  /// Very soft indigo-tinted shadow for white cards.
  static const cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x144F46E5), blurRadius: 16, offset: Offset(0, 4)),
  ];
}

const _fontFamily = 'Pretendard';

/// Builds one text role; keeps every role on Pretendard with explicit color.
TextStyle _style(
  double size,
  FontWeight weight,
  Color color, {
  double? height,
}) => TextStyle(
  fontFamily: _fontFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

const _textPrimary = AppColors.textPrimary;
const _textSecondary = AppColors.textSecondary;

final TextTheme _textTheme = TextTheme(
  displayLarge: _style(34, FontWeight.w700, _textPrimary, height: 1.25),
  displayMedium: _style(30, FontWeight.w700, _textPrimary, height: 1.25),
  displaySmall: _style(28, FontWeight.w700, _textPrimary, height: 1.3),
  headlineLarge: _style(28, FontWeight.w700, _textPrimary, height: 1.3),
  headlineMedium: _style(26, FontWeight.w700, _textPrimary, height: 1.3),
  headlineSmall: _style(24, FontWeight.w700, _textPrimary, height: 1.3),
  titleLarge: _style(26, FontWeight.w700, _textPrimary, height: 1.3),
  titleMedium: _style(21, FontWeight.w600, _textPrimary, height: 1.35),
  titleSmall: _style(19, FontWeight.w600, _textPrimary, height: 1.35),
  bodyLarge: _style(19, FontWeight.w400, _textPrimary, height: 1.4),
  bodyMedium: _style(17, FontWeight.w500, _textSecondary, height: 1.4),
  bodySmall: _style(15, FontWeight.w500, _textSecondary, height: 1.4),
  labelLarge: _style(19, FontWeight.w600, _textPrimary, height: 1.3),
  labelMedium: _style(16, FontWeight.w600, _textPrimary, height: 1.3),
  labelSmall: _style(15, FontWeight.w600, _textPrimary, height: 1.3),
);

final RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(14),
);

OutlineInputBorder _inputBorder(Color color, double width) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );

/// Large-text, large-touch-target theme for senior users, styled after the
/// indigo/violet presentation deck: lavender surfaces, rounded white cards and
/// light top/bottom bars. Pretendard everywhere.
final ThemeData seniorFriendlyTheme = ThemeData(
  useMaterial3: true,
  fontFamily: _fontFamily,
  visualDensity: VisualDensity.standard,
  materialTapTargetSize: MaterialTapTargetSize.padded,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.gradientEnd,
        onSecondary: Colors.white,
        primaryContainer: AppColors.tint,
        onPrimaryContainer: AppColors.primary,
        secondaryContainer: AppColors.tint,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        outline: AppColors.border,
        outlineVariant: AppColors.border,
        error: AppColors.danger,
        surfaceTint: Colors.transparent,
      ),
  textTheme: _textTheme,
  primaryTextTheme: _textTheme.apply(
    bodyColor: Colors.white,
    displayColor: Colors.white,
  ),

  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.surface,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
    scrolledUnderElevation: 0.5,
    shadowColor: AppColors.border,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    toolbarHeight: 64,
    titleTextStyle: _style(24, FontWeight.w700, _textPrimary),
    iconTheme: const IconThemeData(size: 28, color: AppColors.textPrimary),
  ),

  navigationBarTheme: NavigationBarThemeData(
    height: 84,
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    indicatorColor: AppColors.tint,
    indicatorShape: const StadiumBorder(),
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return _style(
        15,
        selected ? FontWeight.w700 : FontWeight.w500,
        selected ? AppColors.primary : AppColors.textSecondary,
      );
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return IconThemeData(
        size: 28,
        color: selected ? AppColors.primary : AppColors.textSecondary,
      );
    }),
  ),

  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.border,
      disabledForegroundColor: AppColors.textSecondary,
      minimumSize: const Size.fromHeight(60),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: _buttonShape,
      textStyle: _style(19, FontWeight.w600, Colors.white),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.border,
      disabledForegroundColor: AppColors.textSecondary,
      minimumSize: const Size.fromHeight(60),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: _buttonShape,
      textStyle: _style(19, FontWeight.w600, Colors.white),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.primary, width: 1.5),
      minimumSize: const Size.fromHeight(60),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: _buttonShape,
      textStyle: _style(19, FontWeight.w600, AppColors.primary),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      minimumSize: const Size(56, 56),
      textStyle: _style(18, FontWeight.w600, AppColors.primary),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(56, 56), iconSize: 28),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    elevation: 2,
    highlightElevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    extendedTextStyle: _style(19, FontWeight.w600, Colors.white),
    sizeConstraints: const BoxConstraints.tightFor(width: 60, height: 60),
    extendedSizeConstraints: const BoxConstraints.tightFor(height: 60),
  ),

  /// Margin stays zero so screens not yet restyled keep their layout.
  cardTheme: CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.border),
    ),
  ),

  listTileTheme: ListTileThemeData(
    minVerticalPadding: 12,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    titleTextStyle: _style(19, FontWeight.w600, _textPrimary),
    subtitleTextStyle: _style(17, FontWeight.w500, _textSecondary),
    iconColor: AppColors.primary,
    minLeadingWidth: 40,
  ),

  chipTheme: ChipThemeData(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    backgroundColor: AppColors.surface,
    selectedColor: AppColors.primary,
    side: const BorderSide(color: AppColors.border),
    shape: const StadiumBorder(),
    labelStyle: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 17,
      fontWeight: FontWeight.w500,
      color: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.textPrimary,
      ),
    ),
    secondaryLabelStyle: _style(17, FontWeight.w600, Colors.white),
    checkmarkColor: Colors.white,
    showCheckmark: true,
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    border: _inputBorder(AppColors.border, 1.2),
    enabledBorder: _inputBorder(AppColors.border, 1.2),
    focusedBorder: _inputBorder(AppColors.primary, 2),
    errorBorder: _inputBorder(AppColors.danger, 1.2),
    focusedErrorBorder: _inputBorder(AppColors.danger, 2),
    labelStyle: _style(17, FontWeight.w500, _textSecondary),
    hintStyle: _style(17, FontWeight.w500, _textSecondary),
    floatingLabelStyle: _style(16, FontWeight.w600, AppColors.primary),
    prefixIconColor: AppColors.textSecondary,
    errorStyle: _style(15, FontWeight.w500, AppColors.danger),
  ),

  dialogTheme: DialogThemeData(
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    titleTextStyle: _style(22, FontWeight.w700, _textPrimary),
    contentTextStyle: _style(18, FontWeight.w400, _textPrimary, height: 1.4),
  ),

  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: AppColors.textPrimary,
    contentTextStyle: _style(17, FontWeight.w500, Colors.white),
    actionTextColor: const Color(0xFFC7CBFF),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),

  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
  ),

  dividerTheme: const DividerThemeData(
    color: AppColors.border,
    thickness: 1,
    space: 1,
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: AppColors.primary,
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: _style(18, FontWeight.w500, _textPrimary),
  ),
  dropdownMenuTheme: DropdownMenuThemeData(
    textStyle: _style(18, FontWeight.w500, _textPrimary),
  ),
  menuTheme: MenuThemeData(
    style: MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  ),
);
