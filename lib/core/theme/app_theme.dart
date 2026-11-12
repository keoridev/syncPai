import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_typography.dart';
import 'theme_preset.dart';

/// Конфигурация темы приложения SyncPai с поддержкой динамических цветовых палитр
abstract final class AppTheme {
  /// Тема по умолчанию: Cinema Dark (Мандарин Сенпай)
  static ThemeData get cinemaDark => fromPreset(ThemePreset.all.first);

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
        onPrimary: AppColors.textPrimary,
        primaryContainer: primary.withValues(alpha: 0.8),
        surface: surf,
        onSurface: AppColors.textPrimary,
        surfaceContainerHighest: surfElevated,
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

      // Input Decoration (Поле поиска, поля ввода кода)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingLg,
          vertical: AppDimensions.spacingMd,
        ),
        hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(
          borderRadius: AppDimensions.borderRadiusMedium,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppDimensions.borderRadiusMedium,
          borderSide: const BorderSide(color: AppColors.stroke, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppDimensions.borderRadiusMedium,
          borderSide: const BorderSide(color: Color(0xFF555B6E), width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppDimensions.borderRadiusMedium,
          borderSide: const BorderSide(color: AppColors.syncError, width: 1.0),
        ),
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
