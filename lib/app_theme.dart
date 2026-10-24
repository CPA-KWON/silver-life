import 'package:flutter/material.dart';

/// Brand palette shared by the theme and by widgets that need a raw color.
/// [primary] is dark enough (~6:1) for white text to sit directly on it.
abstract final class AppColors {
  static const primary = Color(0xFF086FA9);

  /// Approved blue mockup. Text-bearing hero content uses the darker top.
  static const gradientStart = Color(0xFF087BBC);
  static const gradientEnd = Color(0xFF9BCBE7);
  static const heroCircle = Color(0xFF176A9E);
  static const heroTrack = Color(0xFF508AB1);
  static const heroProgress = Color(0xFFADFFE2);
  static const navigation = Color(0xFF111D29);
  static const navigationMuted = Color(0xFFCDD7E0);

  /// Quiet blue surfaces for categories and icons.
  static const tint = Color(0xFFE7F2FA);
  static const blueTint = Color(0xFFE7F2FA);
  static const blueText = Color(0xFF086FA9);
  static const mintTint = Color(0xFFE8F7F1);
  static const mintText = Color(0xFF0F7A55);
  static const neutralTint = Color(0xFFEEF3F7);

  static const background = Color(0xFFF0F5F9);
  static const surface = Color(0xFFFFFFFF);

  static const textPrimary = Color(0xFF152B3E);
  static const scheduleText = Color(0xFF435C70);
  static const textSecondary = Color(0xFF52677A);

  /// Icons and chevrons only; too light for text.
  static const textTertiary = Color(0xFF9CA3AF);
  static const border = Color(0xFFD9E5EE);
  static const segmentTrack = Color(0xFFE3ECF3);
  static const navBorder = Color(0xFFD9E5EE);
  static const divider = Color(0xFFE8EFF5);

  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF15803D);

  /// Attendance streak rewards (7/14/30일) and the point badge coin.
  static const rewardTint = Color(0xFFFFF1CC);
  static const rewardText = Color(0xFF8A4B00);
  static const dangerTint = Color(0xFFFDECEC);

  /// Soft blue shadow for elevated controls only.
  static const cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x14086FA9), blurRadius: 16, offset: Offset(0, 4)),
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
  displayLarge: _style(32, FontWeight.w700, _textPrimary, height: 1.25),
  displayMedium: _style(30, FontWeight.w700, _textPrimary, height: 1.25),
  displaySmall: _style(28, FontWeight.w700, _textPrimary, height: 1.3),
  headlineLarge: _style(28, FontWeight.w700, _textPrimary, height: 1.3),
  headlineMedium: _style(26, FontWeight.w700, _textPrimary, height: 1.3),
  headlineSmall: _style(24, FontWeight.w700, _textPrimary, height: 1.3),
  titleLarge: _style(22, FontWeight.w600, _textPrimary, height: 1.3),
  titleMedium: _style(22, FontWeight.w600, _textPrimary, height: 1.35),
  titleSmall: _style(22, FontWeight.w600, _textPrimary, height: 1.35),
  bodyLarge: _style(18, FontWeight.w400, _textPrimary, height: 1.4),
  bodyMedium: _style(18, FontWeight.w500, _textSecondary, height: 1.4),
  bodySmall: _style(18, FontWeight.w500, _textSecondary, height: 1.4),
  labelLarge: _style(18, FontWeight.w600, _textPrimary, height: 1.3),
  labelMedium: _style(18, FontWeight.w600, _textPrimary, height: 1.3),
  labelSmall: _style(18, FontWeight.w600, _textPrimary, height: 1.3),
);

final RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(24),
);

OutlineInputBorder _inputBorder(Color color, double width) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: color, width: width),
    );

/// Blue mockup applied across existing screens; retain senior-sized type and
/// touch targets instead of copying the reference's small labels.
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
        secondary: AppColors.primary,
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
    scrolledUnderElevation: 0,
    shadowColor: AppColors.border,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    toolbarHeight: 64,
    titleTextStyle: _style(22, FontWeight.w600, _textPrimary),
    iconTheme: const IconThemeData(size: 24, color: AppColors.textPrimary),
  ),

  navigationBarTheme: NavigationBarThemeData(
    height: 104,
    backgroundColor: AppColors.navigation,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    indicatorColor: AppColors.navigation,
    indicatorShape: const StadiumBorder(),
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return _style(
        18,
        selected ? FontWeight.w600 : FontWeight.w500,
        selected ? Colors.white : AppColors.navigationMuted,
        height: 1.2,
      );
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      return IconThemeData(
        size: 24,
        color: selected ? Colors.white : AppColors.navigationMuted,
      );
    }),
  ),

  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.neutralTint,
      disabledForegroundColor: AppColors.textSecondary,
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: _buttonShape,
      textStyle: _style(18, FontWeight.w600, Colors.white),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.neutralTint,
      disabledForegroundColor: AppColors.textSecondary,
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: _buttonShape,
      textStyle: _style(18, FontWeight.w600, Colors.white),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.primary, width: 1.5),
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: _buttonShape,
      textStyle: _style(18, FontWeight.w600, AppColors.primary),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      minimumSize: const Size(48, 56),
      textStyle: _style(18, FontWeight.w600, AppColors.primary),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(48, 56), iconSize: 24),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    elevation: 2,
    highlightElevation: 4,
    shape: const StadiumBorder(),
    extendedTextStyle: _style(18, FontWeight.w600, Colors.white),
    sizeConstraints: const BoxConstraints.tightFor(width: 56, height: 56),
    extendedSizeConstraints: const BoxConstraints.tightFor(height: 56),
  ),

  /// Margin stays zero so screens not yet restyled keep their layout.
  cardTheme: CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
  ),

  listTileTheme: ListTileThemeData(
    minVerticalPadding: 10,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    titleTextStyle: _style(22, FontWeight.w600, _textPrimary),
    subtitleTextStyle: _style(18, FontWeight.w400, _textSecondary),
    iconColor: AppColors.primary,
    minLeadingWidth: 40,
  ),

  chipTheme: ChipThemeData(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    backgroundColor: AppColors.surface,
    selectedColor: AppColors.primary,
    side: BorderSide.none,
    shape: const StadiumBorder(),
    labelStyle: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 18,
      fontWeight: FontWeight.w500,
      color: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.textPrimary,
      ),
    ),
    secondaryLabelStyle: _style(18, FontWeight.w600, Colors.white),
    checkmarkColor: Colors.white,
    showCheckmark: true,
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: _inputBorder(AppColors.border, 1),
    enabledBorder: _inputBorder(AppColors.border, 1),
    focusedBorder: _inputBorder(AppColors.primary, 2),
    errorBorder: _inputBorder(AppColors.danger, 1),
    focusedErrorBorder: _inputBorder(AppColors.danger, 2),
    labelStyle: _style(18, FontWeight.w500, _textSecondary),
    hintStyle: _style(18, FontWeight.w500, _textSecondary),
    floatingLabelStyle: _style(18, FontWeight.w600, AppColors.primary),
    prefixIconColor: AppColors.textSecondary,
    errorStyle: _style(18, FontWeight.w500, AppColors.danger),
  ),

  dialogTheme: DialogThemeData(
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    titleTextStyle: _style(22, FontWeight.w600, _textPrimary),
    contentTextStyle: _style(18, FontWeight.w400, _textPrimary, height: 1.4),
  ),

  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: AppColors.textPrimary,
    contentTextStyle: _style(18, FontWeight.w500, Colors.white),
    actionTextColor: AppColors.heroProgress,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),

  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
  ),

  dividerTheme: const DividerThemeData(
    color: AppColors.divider,
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
