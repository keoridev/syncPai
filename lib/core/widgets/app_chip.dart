import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_typography.dart';

/// Компактная матовая плашка-фильтр в стиле Nordic Dark.
/// Заливка #242730 в спокойном состоянии, акцентная при выборе.
class AppChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final IconData? icon;

  const AppChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final backgroundColor = isSelected ? primary : AppColors.surfaceElevated;
    final textColor = isSelected ? AppColors.textPrimary : AppColors.textSecondary;
    final borderColor = isSelected ? Colors.transparent : AppColors.stroke;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppDimensions.borderRadiusSmall,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingMd,
            vertical: AppDimensions.spacingXs + 2,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: AppDimensions.borderRadiusSmall,
            border: Border.all(
              color: borderColor,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: AppDimensions.iconSizeSmall,
                  color: textColor,
                ),
                const SizedBox(width: AppDimensions.spacingXs + 2),
              ],
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: textColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

