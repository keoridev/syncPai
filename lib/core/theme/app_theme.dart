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
      isManga: preset.id == 'manga',
    );
  }

  /// Гибкий фабричный конструктор темы под любой акцентный цвет
  static ThemeData createTheme({
    Color? primaryColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? surfaceElevatedColor,
    bool isManga = false,
  }) {
    final primary = primaryColor ?? AppColors.primary;
    final onPrimary = isManga
        ? const Color(0xFFFFFFFF)
        : AppColors.onColor(primary);
    final bg = backgroundColor ?? AppColors.background;
    final surf = surfaceColor ?? AppColors.surface;
    final surfElevated = surfaceElevatedColor ?? AppColors.surfaceElevated;
    final panelBorder = isManga ? const Color(0xFF111111) : AppColors.stroke;
    final panelBorderWidth = isManga ? 2.0 : 1.0;
    final inkText = isManga ? const Color(0xFF111111) : AppColors.textPrimary;
    final inkSecondary = isManga ? const Color(0xFF475569) : AppColors.textSecondary;
    final panelRadius = isManga ? BorderRadius.circular(6) : AppDimensions.borderRadiusCard;
    final buttonRadius = isManga ? BorderRadius.circular(6) : AppDimensions.borderRadiusMedium;

    return ThemeData(
      useMaterial3: true,
      brightness: isManga ? Brightness.light : Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: primary,
      canvasColor: bg,

      // ColorScheme
      colorScheme: isManga
          ? ColorScheme.light(
              primary: primary,
              onPrimary: Colors.white,
              primaryContainer: const Color(0xFF111111).withValues(alpha: 0.08),
              onPrimaryContainer: const Color(0xFF111111),
              surface: surf,
              surfaceContainerLowest: bg,
              surfaceContainerLow: surf,
              surfaceContainer: surf,
              surfaceContainerHigh: surfElevated,
              surfaceContainerHighest: surfElevated,
              onSurface: inkText,
              onSurfaceVariant: inkSecondary,
              outline: const Color(0xFF111111),
              outlineVariant: const Color(0xFF111111),
              error: AppColors.syncError,
              onError: Colors.white,
            )
          : ColorScheme.dark(
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
        titleTextStyle: AppTypography.titleLarge.copyWith(color: inkText),
        iconTheme: IconThemeData(color: inkText, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isManga ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: bg,
          systemNavigationBarIconBrightness: isManga ? Brightness.dark : Brightness.light,
        ),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isManga ? const Color(0xFF111111) : surfElevated,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: isManga ? BorderRadius.circular(6) : BorderRadius.circular(14),
          side: BorderSide(
            color: isManga ? const Color(0xFF111111) : primary.withValues(alpha: 0.35),
            width: isManga ? 2.0 : 1.2,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // Card
      cardTheme: CardThemeData(
        color: surf,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: panelRadius,
          side: BorderSide(color: panelBorder, width: panelBorderWidth),
        ),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size(0, AppDimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
          shape: RoundedRectangleBorder(
            borderRadius: buttonRadius,
            side: isManga
                ? const BorderSide(color: Color(0xFF111111), width: 2.0)
                : BorderSide.none,
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: inkText,
          minimumSize: const Size(0, AppDimensions.buttonHeight),
          side: BorderSide(
            color: isManga ? const Color(0xFF111111) : AppColors.strokeMedium,
            width: panelBorderWidth,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
          shape: RoundedRectangleBorder(
            borderRadius: buttonRadius,
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
