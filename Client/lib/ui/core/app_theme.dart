import 'package:flutter/material.dart';

/// 菠萝乐园统一设计令牌。
abstract final class AppColors {
  static const cream = Color(0xFFFFF8EA);
  static const paper = Color(0xFFFFFDF7);
  static const teal = Color(0xFF2A9D8F);
  static const tealDark = Color(0xFF176B63);
  static const coral = Color(0xFFF47C68);
  static const sunshine = Color(0xFFF4C95D);
  static const sky = Color(0xFF66B7D9);
  static const mintMist = Color(0xFFE4F5E9);
  static const peachMist = Color(0xFFFFE8DC);
  static const skyMist = Color(0xFFE4F3FA);
  static const lavender = Color(0xFF766DC4);
  static const ink = Color(0xFF24364B);
  static const mutedInk = Color(0xFF657488);
  static const player = Color(0xFF10263A);
}

abstract final class AppTheme {
  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: AppColors.teal,
      onPrimary: Colors.white,
      secondary: AppColors.coral,
      onSecondary: Colors.white,
      tertiary: AppColors.sunshine,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      error: Color(0xFFBA4A4A),
      onError: Colors.white,
    );

    final baseTextTheme = Typography.material2021(platform: TargetPlatform.android).black;
    final textTheme = baseTextTheme.copyWith(
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.2,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: AppColors.ink, height: 1.45),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: AppColors.mutedInk, height: 1.4),
      labelLarge: baseTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.cream,
      textTheme: textTheme,
      fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'Noto Sans CJK SC'],
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(120, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
