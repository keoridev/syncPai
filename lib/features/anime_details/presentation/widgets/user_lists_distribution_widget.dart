import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/user_lists_stats.dart';

/// Виджет «В списках у людей» со статусным сегментированным баром и счетчиками.
/// В точности воспроизводит дизайн из официального Anixart / Shikimori.
class UserListsDistributionWidget extends StatelessWidget {
  final UserListsStats stats;
  final bool showCard;

  const UserListsDistributionWidget({
    super.key,
    required this.stats,
    this.showCard = false,
  });

  // Аутентичная палитра Anixart
  static const Color colorWatching = Color(0xFF68B684); // Зеленый: Смотрю
  static const Color colorPlanned = Color(0xFFAB72B4);  // Сиреневый: В планах
  static const Color colorOnHold = Color(0xFFEAA139);   // Оранжевый: Отложено
  static const Color colorDropped = Color(0xFFE05B5B);  // Коралловый: Брошено

  @override
  Widget build(BuildContext context) {
    final total = stats.total > 0 ? stats.total : 1;

    // Доли сегментов в баре
    final watchingFlex = (stats.watching / total * 100).clamp(1.0, 100.0).round();
    final plannedFlex = (stats.planned / total * 100).clamp(1.0, 100.0).round();
    final onHoldFlex = (stats.onHold / total * 100).clamp(1.0, 100.0).round();
    final droppedFlex = (stats.dropped / total * 100).clamp(1.0, 100.0).round();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'В списках у людей',
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16.5,
          ),
        ),
        const SizedBox(height: 12),

        // Сегментированный горизонтальный индикатор со скруглением
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 15,
            child: Row(
              children: [
                // 1. Смотрю (зеленый)
                Flexible(
                  flex: watchingFlex,
                  child: Container(color: colorWatching),
                ),
                const SizedBox(width: 2),
                // 2. В планах (фиолетовый)
                Flexible(
                  flex: plannedFlex,
                  child: Container(color: colorPlanned),
                ),
                const SizedBox(width: 2),
                // 3. Отложено (янтарный)
                Flexible(
                  flex: onHoldFlex,
                  child: Container(color: colorOnHold),
                ),
                const SizedBox(width: 2),
                // 4. Брошено (красный)
                Flexible(
                  flex: droppedFlex,
                  child: Container(color: colorDropped),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Легенда: 2 строки x 2 колонки (Скриншот 1)
        Row(
          children: [
            Expanded(
              child: _buildLegendItem(
                color: colorWatching,
                label: 'Смотрю',
                count: stats.watching,
              ),
            ),
            Expanded(
              child: _buildLegendItem(
                color: colorOnHold,
                label: 'Отложено',
                count: stats.onHold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildLegendItem(
                color: colorPlanned,
                label: 'В планах',
                count: stats.planned,
              ),
            ),
            Expanded(
              child: _buildLegendItem(
                color: colorDropped,
                label: 'Брошено',
                count: stats.dropped,
              ),
            ),
          ],
        ),
      ],
    );

    if (showCard) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.strokeMedium),
        ),
        child: content,
      );
    }

    return content;
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required int count,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }
}
