import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_typography.dart';
import 'theme_preset.dart';

/// Конфигурация темы приложения SyncPai с поддержкой динамических цветовых палитр
abstract final class AppTheme {
  /// Тема по умолчанию: Cinema Dark (Мандарин Сенпай)
  static ThemeData get cinemaDark => ThemePreset.all.any((p) => p.id == 'sunset_orange')
      ? fromPreset(ThemePreset.all.firstWhere((p) => p.id == 'sunset_orange'))
      : createTheme();

  /// Генерация темы на основе выбранного пресета
  static ThemeData fromPreset(ThemePreset preset) {
    return createTheme(
      primaryColor: preset.primaryColor,
      backgroundColor: preset.backgroundColor,
      surfaceColor: preset.surfaceColor,
      surfaceElevatedColor: preset.surfaceElevatedColor,
    );
  }

  /// Гибкий фабричный конструктор темы под любой акцентный цвет
  static ThemeData createTheme({
    Color? primaryColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? surfaceElevatedColor,
  }) {
    final primary = primaryColor ?? AppColors.primary;
    final onPrimary = AppColors.onColor(primary);
    final bg = backgroundColor ?? AppColors.background;
    final surf = surfaceColor ?? AppColors.surface;
    final surfElevated = surfaceElevatedColor ?? AppColors.surfaceElevated;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: primary,
      canvasColor: bg,

      // ColorScheme
      colorScheme: ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primary.withValues(alpha: 0.16),
        onPrimaryContainer: primary,
        surface: surf,
        surfaceContainerLowest: bg,
        surfaceContainerLow: surf,
        surfaceContainer: surf,
        surfaceContainerHigh: surfElevated,
        surfaceContainerHighest: surfElevated,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        outline: AppColors.stroke,
        outlineVariant: AppColors.strokeMedium,
        error: AppColors.syncError,
        onError: AppColors.textPrimary,
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.titleLarge,
        iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: bg,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfElevated,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: primary.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
      ),

      // Card
      cardTheme: CardThemeData(
        color: surf,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppDimensions.borderRadiusCard,
          side: const BorderSide(color: AppColors.stroke, width: 1.0),
        ),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          minimumSize: const Size(0, AppDimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
          shape: const RoundedRectangleBorder(
            borderRadius: AppDimensions.borderRadiusMedium,
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(0, AppDimensions.buttonHeight),
          side: const BorderSide(color: AppColors.strokeMedium, width: 1.0),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
          shape: const RoundedRectangleBorder(
            borderRadius: AppDimensions.borderRadiusMedium,
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      // Input Decoration (Глобально без двойных внутренних рамок и фоновой заливки)
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        filled: false,
        isDense: true,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
      ),

      // Text Selection Theme (нейтральный серый/белый курсор и выделение)
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Colors.white70,
        selectionColor: Color(0x40FFFFFF),
        selectionHandleColor: Colors.white70,
      ),

      // BottomSheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surf,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusExtraLarge)),
        ),
      ),

      // Progress Indicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: surfElevated,
        circularTrackColor: surfElevated,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.stroke,
        thickness: 1.0,
        space: 1.0,
      ),

      // Typography
      textTheme: TextTheme(
        displayLarge: AppTypography.displayLarge,
        displayMedium: AppTypography.displayMedium,
        titleLarge: AppTypography.titleLarge,
        titleMedium: AppTypography.titleMedium,
        titleSmall: AppTypography.titleSmall,
        bodyLarge: AppTypography.bodyLarge,
        bodyMedium: AppTypography.bodyMedium,
        bodySmall: AppTypography.bodySmall,
        labelLarge: AppTypography.labelLarge,
        labelMedium: AppTypography.labelMedium,
        labelSmall: AppTypography.labelSmall,
      ),
    );
  }
}
