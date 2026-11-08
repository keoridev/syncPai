import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';
import '../../domain/entities/anime_title.dart';

/// Карточка аниме для режима «Целый список» (List view).
/// Оптимизирована для 60-120 FPS через RepaintBoundary и низкое потребление GPU.
class AnimeListTileCard extends StatelessWidget {
  final AnimeTitle title;
  final VoidCallback onTap;
  final double? watchProgress;

  const AnimeListTileCard({
    super.key,
    required this.title,
    required this.onTap,
    this.watchProgress,
  });

  @override
  Widget build(BuildContext context) {
    final posterUrl = title.posterMedium.isNotEmpty
        ? title.posterMedium
        : title.posterSmall;

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppDimensions.borderRadiusCard,
          splashColor: AppColors.strokeMedium,
          highlightColor: AppColors.stroke,
          child: Container(
            height: 146,
            decoration: AppDecorations.cardDecoration,
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                // Левая часть: Постер
                SizedBox(
                  width: 102,
                  height: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (posterUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: wrapCorsSafeUrl(posterUrl),
                          httpHeaders: const {
                            'User-Agent': 'SyncPai-App/1.0',
                            'Referer': 'https://shikimori.io/',
                          },
                          fit: BoxFit.cover,
                          memCacheWidth: 220,
                          memCacheHeight: 330,
                          maxWidthDiskCache: 400,
                          maxHeightDiskCache: 600,
                          fadeInDuration: const Duration(milliseconds: 140),
                          filterQuality: FilterQuality.low,
                          placeholder: (context, url) =>
                              const ShimmerPlaceholder.card(),
                          errorWidget: (context, url, error) => Container(
                            color: AppColors.surfaceElevated,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.movie_creation_outlined,
                              color: AppColors.textMuted,
                              size: 28,
                            ),
                          ),
                        )
                      else
                        Container(
                          color: AppColors.surfaceElevated,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.movie_creation_outlined,
                            color: AppColors.textMuted,
                            size: 28,
                          ),
                        ),

                      // Мягкое затемнение снизу постера
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.5, 1.0],
                              colors: [
                                Colors.transparent,
                                AppColors.surface.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Бейдж серий внизу постера
                      if (title.latestEpisode != null)
                        Positioned(
                          left: AppDimensions.spacingSm,
                          bottom: AppDimensions.spacingSm,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.background.withValues(alpha: 0.88),
                              borderRadius: AppDimensions.borderRadiusSmall,
                              border: Border.all(
                                color: AppColors.strokeMedium,
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              title.episodesBadgeText,
                              style: AppTypography.badge.copyWith(
                                fontSize: 10,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),

                      // Тонкая полоска сохраненного прогресса просмотра
                      if (watchProgress != null && watchProgress! > 0.0 && watchProgress! < 0.98)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            value: watchProgress!,
                            minHeight: 3,
                            backgroundColor: Colors.black.withValues(alpha: 0.6),
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                    ],
                  ),
                ),

                // Правая часть: Подробная информация
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimensions.spacingMd),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Заголовок тайтла
                            Text(
                              title.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.titleSmall.copyWith(
                                color: AppColors.textPrimary,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            // Статус и год
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: title.status == 'Онгоинг'
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  title.status,
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (title.year != null) ...[
                                  const Text(' • ', style: TextStyle(color: AppColors.textMuted)),
                                  Text(
                                    '${title.year}',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                                if (title.season != null) ...[
                                  Text(' • ${title.season}',
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textMuted,
                                      )),
                                ],
                              ],
                            ),
                          ],
                        ),

                        // Краткое описание
                        if (title.description.isNotEmpty)
                          Text(
                            title.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textMuted,
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),

                        // Жанры и быстрая стрелка
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                title.genres.take(3).join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 13,
                              color: AppColors.textMuted,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
