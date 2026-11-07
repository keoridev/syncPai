import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/related_anime_release.dart';

/// Виджет-график динамики рейтингов сезонов франшизы.
/// Наглядно отображает взлеты и динамику популярности тайтла по частям.
class FranchiseProgressionChart extends StatelessWidget {
  final List<RelatedAnimeRelease> releases;
  final ValueChanged<RelatedAnimeRelease>? onReleaseSelected;

  const FranchiseProgressionChart({
    super.key,
    required this.releases,
    this.onReleaseSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (releases.length < 2) {
      return const SizedBox.shrink();
    }

    // Ищем максимальную и минимальную оценку для масштабирования баров
    double maxRating = 10.0;
    double minRating = 5.0;
    for (final r in releases) {
      if (r.rating != null) {
        if (r.rating! > maxRating) maxRating = r.rating!;
        if (r.rating! < minRating) minRating = r.rating!;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.strokeMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Динамика сезонов',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Рейтинг',
                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Горизонтальный ряд колонок по сезонам
          SizedBox(
            height: 125,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: releases.map((release) {
                final rawRating = release.rating;
                // Нормализация к 10-балльной шкале (если оценка в 5-звездочной шкале, переводим в 10-балльную)
                final double score10 = rawRating != null
                    ? ((rawRating <= 5.0 && rawRating > 0) ? rawRating * 2 : rawRating)
                    : 8.0;
                // Высота столбца пересчитывается строго относительно максимального значения (10.0)
                final double heightFactor = (score10 / 10.0).clamp(0.2, 1.0);

                return Expanded(
                  child: GestureDetector(
                    onTap: release.isCurrent ? null : () => onReleaseSelected?.call(release),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Оценка сверху бара
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              score10.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: release.isCurrent ? FontWeight.bold : FontWeight.w600,
                                color: release.isCurrent
                                    ? AppColors.primaryLight
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const Icon(
                              Icons.star_rounded,
                              size: 11,
                              color: Color(0xFFFFB300),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Вертикальный бар с градиентом
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: heightFactor,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: release.isCurrent
                                      ? [AppColors.primary, AppColors.primaryLight]
                                      : [
                                          AppColors.primary.withValues(alpha: 0.35),
                                          AppColors.primaryLight.withValues(alpha: 0.7),
                                        ],
                                ),
                                border: Border.all(
                                  color: release.isCurrent
                                      ? Colors.white
                                      : AppColors.primaryLight.withValues(alpha: 0.4),
                                  width: release.isCurrent ? 1.5 : 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: release.isCurrent
                                        ? AppColors.primary.withValues(alpha: 0.45)
                                        : AppColors.primary.withValues(alpha: 0.15),
                                    blurRadius: release.isCurrent ? 8 : 4,
                                    spreadRadius: release.isCurrent ? 1 : 0,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Название сезона и метка "Вы здесь"
                        Text(
                          _shortSeasonName(release.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: release.isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: release.isCurrent
                                ? AppColors.primaryLight
                                : AppColors.textSecondary,
                          ),
                        ),
                        if (release.year != null)
                          Text(
                            release.year!.replaceAll(' год', ''),
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  static String _shortSeasonName(String fullTitle) {
    if (fullTitle.toLowerCase().contains('фильм')) return 'Фильм';
    final match = RegExp(r'(\d+)\s*(?:сезон|th|nd|rd)?', caseSensitive: false).firstMatch(fullTitle);
    if (match != null) {
      return 'Сезон ${match.group(1)}';
    }
    return fullTitle.length > 8 ? '${fullTitle.substring(0, 7)}…' : fullTitle;
  }
}
