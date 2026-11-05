import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/player_quality.dart';

class QualitySelectionSheet extends StatelessWidget {
  final PlayerQuality currentQuality;
  final ValueChanged<PlayerQuality> onSelect;

  const QualitySelectionSheet({
    super.key,
    required this.currentQuality,
    required this.onSelect,
  });

  static Future<void> show(
    BuildContext context, {
    required PlayerQuality currentQuality,
    required ValueChanged<PlayerQuality> onSelect,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLarge)),
      ),
      builder: (_) => QualitySelectionSheet(
        currentQuality: currentQuality,
        onSelect: onSelect,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingXl,
          vertical: AppDimensions.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.strokeMedium,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            Text(
              'Качество видео',
              style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            ...PlayerQuality.values.map((quality) {
              final isSelected = quality == currentQuality;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  quality.label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  onSelect(quality);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

