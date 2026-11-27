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
    final Color onPrimary = (isManga || primary.computeLuminance() > 0.5)
        ? const Color(0xFF0D0F12)
        : Colors.white;
    final bg = backgroundColor ?? AppColors.background;
    final surf = surfaceColor ?? AppColors.surface;
    final surfElevated = surfaceElevatedColor ?? AppColors.surfaceElevated;
    final panelBorder = isManga ? const Color(0x2EF8FAFC) : AppColors.stroke;
    final panelBorderWidth = isManga ? 1.5 : 1.0;
    final inkText = isManga ? const Color(0xFFF8FAFC) : AppColors.textPrimary;
    final inkSecondary = isManga ? const Color(0xFF94A3B8) : AppColors.textSecondary;
    final panelRadius = isManga ? BorderRadius.circular(10) : AppDimensions.borderRadiusCard;
    final buttonRadius = isManga ? BorderRadius.circular(10) : AppDimensions.borderRadiusMedium;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      cardColor: surf,
      primaryColor: primary,
      canvasColor: bg,
      dialogTheme: DialogThemeData(
        backgroundColor: surfElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: panelRadius,
          side: BorderSide(color: panelBorder, width: panelBorderWidth),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: inkText,
        iconColor: inkSecondary,
      ),

      // ColorScheme
      colorScheme: ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primary.withValues(alpha: 0.14),
        onPrimaryContainer: primary,
        surface: surf,
        surfaceContainerLowest: bg,
        surfaceContainerLow: surf,
        surfaceContainer: surf,
        surfaceContainerHigh: surfElevated,
        surfaceContainerHighest: surfElevated,
        onSurface: inkText,
        onSurfaceVariant: inkSecondary,
        outline: panelBorder,
        outlineVariant: isManga ? const Color(0x4DF8FAFC) : AppColors.strokeMedium,
        error: AppColors.syncError,
        onError: Colors.white,
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
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isManga ? const Color(0x33F8FAFC) : primary.withValues(alpha: 0.35),
            width: 1.2,
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
                ? const BorderSide(color: Color(0xCCF8FAFC), width: 1.2)
                : BorderSide.none,
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size(0, AppDimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
          shape: RoundedRectangleBorder(
            borderRadius: buttonRadius,
            side: isManga
                ? const BorderSide(color: Color(0xCCF8FAFC), width: 1.2)
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
            color: isManga ? const Color(0x4DF8FAFC) : AppColors.strokeMedium,
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
      dividerTheme: DividerThemeData(
        color: isManga ? const Color(0x26F8FAFC) : AppColors.stroke,
        thickness: 1.0,
        space: 1.0,
      ),

      // Typography
      textTheme: TextTheme(
        displayLarge: AppTypography.displayLarge.copyWith(color: inkText),
        displayMedium: AppTypography.displayMedium.copyWith(color: inkText),
        titleLarge: AppTypography.titleLarge.copyWith(color: inkText),
        titleMedium: AppTypography.titleMedium.copyWith(color: inkText),
        titleSmall: AppTypography.titleSmall.copyWith(color: inkText),
        bodyLarge: AppTypography.bodyLarge.copyWith(color: inkText),
        bodyMedium: AppTypography.bodyMedium.copyWith(color: inkText),
        bodySmall: AppTypography.bodySmall.copyWith(color: inkSecondary),
        labelLarge: AppTypography.labelLarge.copyWith(color: inkText),
        labelMedium: AppTypography.labelMedium.copyWith(color: inkSecondary),
        labelSmall: AppTypography.labelSmall.copyWith(color: inkSecondary),
      ),
    );
  }
}
