import 'package:flutter/material.dart';

import 'app_motion.dart';

class AppColors {
  AppColors._();

  static const primary = Color(0xFF1A73E8); // bleu Denkma
  static const secondary = Color(0xFFFF6B00); // orange accent
  static const success = Color(0xFF2E7D32); // vert livré
  static const warning = Color(0xFFF57C00); // orange en transit
  static const error = Color(0xFFC62828); // rouge échec
  static const purple = Color(0xFF6A1B9A); // violet out_for_delivery
  static const background = Color(0xFFF5F5F5);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
  static const divider = Color(0xFFE0E0E0);
}

class AppTheme {
  AppTheme._();

  static WidgetStateProperty<Color?> _overlay(Color color) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return color.withValues(alpha: 0.2);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return color.withValues(alpha: 0.1);
      }
      return null;
    });
  }

  static final _elevatedButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    minimumSize: const Size(double.infinity, 48),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    textStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  ).copyWith(
    animationDuration: AppMotion.fast,
    overlayColor: _overlay(Colors.white),
    elevation: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return 0;
      if (states.contains(WidgetState.pressed)) return 0;
      return 2;
    }),
  );

  static final _filledButtonStyle = FilledButton.styleFrom(
    minimumSize: const Size(48, 48),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    textStyle: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
  ).copyWith(
    animationDuration: AppMotion.fast,
    overlayColor: _overlay(Colors.white),
  );

  static final _outlinedButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: AppColors.primary,
    minimumSize: const Size(double.infinity, 48),
    side: const BorderSide(color: AppColors.primary),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ).copyWith(
    animationDuration: AppMotion.fast,
    overlayColor: _overlay(AppColors.primary),
  );

  static final _textButtonStyle = TextButton.styleFrom(
    foregroundColor: AppColors.primary,
    minimumSize: const Size(44, 44),
  ).copyWith(
    animationDuration: AppMotion.fast,
    overlayColor: _overlay(AppColors.primary),
  );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        splashFactory: InkRipple.splashFactory,
        splashColor: AppColors.primary.withValues(alpha: 0.14),
        highlightColor: AppColors.primary.withValues(alpha: 0.08),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          error: AppColors.error,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: DenkmaPageTransitionsBuilder(),
            TargetPlatform.iOS: DenkmaPageTransitionsBuilder(),
            TargetPlatform.macOS: DenkmaPageTransitionsBuilder(),
            TargetPlatform.windows: DenkmaPageTransitionsBuilder(),
            TargetPlatform.linux: DenkmaPageTransitionsBuilder(),
          },
        ),
        elevatedButtonTheme:
            ElevatedButtonThemeData(style: _elevatedButtonStyle),
        filledButtonTheme: FilledButtonThemeData(style: _filledButtonStyle),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: _outlinedButtonStyle,
        ),
        textButtonTheme: TextButtonThemeData(style: _textButtonStyle),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            animationDuration: AppMotion.fast,
            overlayColor: _overlay(AppColors.primary),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          thickness: 1,
        ),
      );
}
