import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/catalog_settings.dart';
import '../cubit/catalog_cubit.dart';

class CatalogSettingsSheet extends StatelessWidget {
  final CatalogCubit cubit;
  final CatalogViewMode currentViewMode;
  final CatalogGridDensity currentGridDensity;

  const CatalogSettingsSheet({
    super.key,
    required this.cubit,
    required this.currentViewMode,
    required this.currentGridDensity,
  });

  static Future<void> show(
    BuildContext context, {
    required CatalogCubit cubit,
    required CatalogViewMode currentViewMode,
    required CatalogGridDensity currentGridDensity,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusLarge),
        ),
      ),
      builder: (_) => CatalogSettingsSheet(
        cubit: cubit,
        currentViewMode: currentViewMode,
        currentGridDensity: currentGridDensity,
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
            // Полоска-ручка вверху шторки
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

            Row(
              children: [
                Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: AppDimensions.spacingSm),
                Text(
                  'Настройки каталога',
                  style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingLg),

            // Секция 1: Режим отображения
            Text('Формат вывода', style: AppTypography.labelLarge),
            const SizedBox(height: AppDimensions.spacingSm),
            Row(
              children: [
                Expanded(
                  child: _buildOptionTile(
                    label: 'Сетка',
                    subtitle: 'Несколько рядом',
                    icon: Icons.grid_view_rounded,
                    isSelected: currentViewMode == CatalogViewMode.grid,
                    onTap: () {
                      cubit.setViewMode(CatalogViewMode.grid);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingMd),
                Expanded(
                  child: _buildOptionTile(
                    label: 'Список',
                    subtitle: 'Целый список',
                    icon: Icons.view_agenda_rounded,
                    isSelected: currentViewMode == CatalogViewMode.list,
                    onTap: () {
                      cubit.setViewMode(CatalogViewMode.list);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppDimensions.spacingXl),

            // Секция 2: Плотность сетки (если выбрана сетка)
            if (currentViewMode == CatalogViewMode.grid) ...[
              Text('Колонок в сетке', style: AppTypography.labelLarge),
              const SizedBox(height: AppDimensions.spacingSm),
              Row(
                children: [
                  Expanded(
                    child: _buildOptionTile(
                      label: '2 в ряд',
                      subtitle: 'Крупные постеры',
                      icon: Icons.view_column_rounded,
                      isSelected: currentGridDensity == CatalogGridDensity.standard,
                      onTap: () {
                        cubit.setGridDensity(CatalogGridDensity.standard);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingMd),
                  Expanded(
                    child: _buildOptionTile(
                      label: '3 в ряд',
                      subtitle: 'Компактный вид',
                      icon: Icons.view_module_rounded,
                      isSelected: currentGridDensity == CatalogGridDensity.compact,
                      onTap: () {
                        cubit.setGridDensity(CatalogGridDensity.compact);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingLg),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppDimensions.borderRadiusMedium,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingMd,
            vertical: AppDimensions.spacingMd,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surfaceElevated : AppColors.surface,
            borderRadius: AppDimensions.borderRadiusMedium,
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.stroke,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingSm),
              Text(
                label,
                style: AppTypography.titleSmall.copyWith(
                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

