import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant {
  primary,
  secondaryFrosted,
  outline,
}

/// Фирменные кнопки приложения SyncPai.
/// Поддерживают акцентный терракотовый моно-стиль и матовый полупрозрачный (frosted glass).
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool isLoading;
  final double? width;
  final Color? backgroundColor;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.width,
    this.backgroundColor,
  });

  const AppButton.frosted({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.width,
    this.backgroundColor,
  }) : variant = AppButtonVariant.secondaryFrosted;

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = AppDimensions.buttonHeight;

    final effectiveColor = backgroundColor ?? Theme.of(context).colorScheme.primary;
    final onEffectiveColor = AppColors.onColor(effectiveColor);
    final effectiveTextColor = variant == AppButtonVariant.primary
        ? onEffectiveColor
        : AppColors.textPrimary;

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(effectiveTextColor),
            ),
          ),
          const SizedBox(width: AppDimensions.spacingSm),
        ] else if (icon != null) ...[
          Icon(icon, size: AppDimensions.iconSizeMedium, color: effectiveTextColor),
          const SizedBox(width: AppDimensions.spacingSm),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(color: effectiveTextColor),
          ),
        ),
      ],
    );

    Widget button;

    switch (variant) {
      case AppButtonVariant.primary:
        button = ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: effectiveColor,
            foregroundColor: onEffectiveColor,
            elevation: 0,
            minimumSize: Size(width ?? 0, effectiveHeight),
            shape: const RoundedRectangleBorder(
              borderRadius: AppDimensions.borderRadiusMedium,
            ),
          ),
          child: child,
        );
        break;

      case AppButtonVariant.secondaryFrosted:
        button = Material(
          color: Colors.transparent,
          borderRadius: AppDimensions.borderRadiusMedium,
          child: InkWell(
            onTap: isLoading ? null : onPressed,
            borderRadius: AppDimensions.borderRadiusMedium,
            splashColor: AppColors.strokeMedium,
            highlightColor: AppColors.stroke,
            child: Container(
              height: effectiveHeight,
              width: width,
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingLg),
              decoration: BoxDecoration(
                color: AppColors.frostedWhite,
                borderRadius: AppDimensions.borderRadiusMedium,
                border: Border.all(
                  color: AppColors.strokeMedium,
                  width: 1.0,
                ),
              ),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
        break;

      case AppButtonVariant.outline:
        button = OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: Size(width ?? 0, effectiveHeight),
            side: const BorderSide(color: AppColors.strokeMedium, width: 1.0),
            shape: const RoundedRectangleBorder(
              borderRadius: AppDimensions.borderRadiusMedium,
            ),
          ),
          child: child,
        );
        break;
    }

    return button;
  }
}

