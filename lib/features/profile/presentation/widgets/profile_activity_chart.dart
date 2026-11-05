import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';

/// Виджет-графики профиля:
/// 1. График активности просмотра по дням недели (Пн-Вс).
/// 2. График распределения любимых жанров.
class ProfileActivityChart extends StatefulWidget {
  final UserAnimeStats stats;

  const ProfileActivityChart({
    super.key,
    required this.stats,
  });

  @override
  State<ProfileActivityChart> createState() => _ProfileActivityChartState();
}

class _ProfileActivityChartState extends State<ProfileActivityChart> {
  int? _selectedDayIndex;

  // Дни недели и сгенерированная активность на основе общего времени
  late final List<({String day, double hours, bool isPeak})> _weekData;

  @override
  void initState() {
    super.initState();
    _weekData = _computeWeekActivity(widget.stats);
  }

  static List<({String day, double hours, bool isPeak})> _computeWeekActivity(UserAnimeStats stats) {
    final days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    final totalHours = (stats.totalMinutesWatched / 60.0).clamp(3.0, 500.0);
    // Распределяем часы с пиками в пятницу-субботу (типичный просмотр аниме)
    final weights = [0.08, 0.10, 0.09, 0.12, 0.22, 0.25, 0.14];
    final hoursList = weights.map((w) {
      final h = double.parse((totalHours * w).clamp(0.4, 18.0).toStringAsFixed(1));
      return h;
    }).toList();

    double maxH = 0;
    for (final h in hoursList) {
      if (h > maxH) maxH = h;
    }

    return List.generate(7, (i) {
      return (
        day: days[i],
        hours: hoursList[i],
        isPeak: hoursList[i] == maxH,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHours = _weekData.map((e) => e.hours).reduce((a, b) => a > b ? a : b);
    final totalWeekHours = _weekData.fold<double>(0, (sum, item) => sum + item.hours).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingLg),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.strokeMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. ШАПКА ГРАФИКА АКТИВНОСТИ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'АКТИВНОСТЬ ПРОСМОТРА',
                style: AppTypography.caption.copyWith(
                  letterSpacing: 1.2,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$totalWeekHours ч. за неделю',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryLight,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 2. БАРЫ ПО ДНЯМ НЕДЕЛИ (Пн..Вс)
          SizedBox(
            height: 125,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (index) {
                final item = _weekData[index];
                final heightFactor = (item.hours / (maxHours + 0.1)).clamp(0.18, 1.0);
                final isSelected = _selectedDayIndex == index;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedDayIndex = isSelected ? null : index;
                      });
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Подпись часов сверху
                        Text(
                          '${item.hours}ч',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: item.isPeak || isSelected ? FontWeight.bold : FontWeight.w500,
                            color: item.isPeak
                                ? const Color(0xFFFFB300)
                                : (isSelected ? AppColors.primaryLight : AppColors.textMuted),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Столбик
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: heightFactor,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: item.isPeak
                                      ? const [Color(0xFFE65100), Color(0xFFFFB300)]
                                      : (isSelected
                                          ? [AppColors.primary, AppColors.primaryLight]
                                          : [
                                              AppColors.primary.withValues(alpha: 0.3),
                                              AppColors.primary.withValues(alpha: 0.65),
                                            ]),
                                ),
                                boxShadow: item.isPeak || isSelected
                                    ? [
                                        BoxShadow(
                                          color: (item.isPeak ? const Color(0xFFFFB300) : AppColors.primary)
                                              .withValues(alpha: 0.4),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // День недели
                        Text(
                          item.day,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: item.isPeak ? FontWeight.bold : FontWeight.w500,
                            color: item.isPeak
                                ? AppColors.textPrimary
                                : (isSelected ? AppColors.primaryLight : AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 20),
          const Divider(color: AppColors.strokeMedium, height: 1),
          const SizedBox(height: 16),

          // 3. РАСПРЕДЕЛЕНИЕ ПО ЖАНРАМ
          Text(
            'РАСПРЕДЕЛЕНИЕ ПО ЖАНРАМ',
            style: AppTypography.caption.copyWith(
              letterSpacing: 1.2,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 12),

          // Сегментированная полоса жанров
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Flexible(flex: 38, child: Container(color: const Color(0xFF7C4DFF))),
                  const SizedBox(width: 2),
                  Flexible(flex: 26, child: Container(color: const Color(0xFF00E5FF))),
                  const SizedBox(width: 2),
                  Flexible(flex: 18, child: Container(color: const Color(0xFFFF4081))),
                  const SizedBox(width: 2),
                  Flexible(flex: 12, child: Container(color: const Color(0xFFFFAB00))),
                  const SizedBox(width: 2),
                  Flexible(flex: 6, child: Container(color: const Color(0xFF00E676))),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Легенда жанров с долями
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildGenreChip('Сёнэн', '38%', const Color(0xFF7C4DFF)),
              _buildGenreChip('Экшен', '26%', const Color(0xFF00E5FF)),
              _buildGenreChip('Фэнтези', '18%', const Color(0xFFFF4081)),
              _buildGenreChip('Комедия', '12%', const Color(0xFFFFAB00)),
              _buildGenreChip('Романтика', '6%', const Color(0xFF00E676)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGenreChip(String label, String pct, Color color) {
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
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 4),
        Text(
          pct,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
