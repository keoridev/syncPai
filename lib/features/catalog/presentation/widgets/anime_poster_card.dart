import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';
import '../../../../core/widgets/tv_focusable.dart';
import '../../domain/entities/anime_title.dart';

/// Карточка аниме в стиле Cinematic Dark / Nordic Dark.
/// - Большие скругления постера (18px)
/// - Чистый арт без технических коробок и плашек поверх картинки
/// - Название аккуратно под постером молочно-белым цветом
/// - Метаданные (год, серии, жанры) через точку
/// - Поддержка Android TV / D-pad с плавной подсветкой фокуса
class AnimePosterCard extends StatelessWidget {
  final AnimeTitle title;
  final VoidCallback onTap;
  final double? watchProgress;

  const AnimePosterCard({
    super.key,
    required this.title,
    required this.onTap,
    this.watchProgress,
  });

  static const double cardRadius = 18.0;

  @override
  Widget build(BuildContext context) {
    final posterUrl = title.posterMedium.isNotEmpty
        ? title.posterMedium
        : (title.posterOriginal.isNotEmpty ? title.posterOriginal : title.posterSmall);

    return TvFocusable(
      onPressed: onTap,
      borderRadius: BorderRadius.circular(cardRadius),
      scaleFactor: 1.04,
      glowColor: AppColors.accentPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Чистый постер с большим радиусом (18px)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(cardRadius),
                border: Border.all(
                  color: AppColors.stroke,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (posterUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 360,
                        memCacheHeight: 540,
                        maxWidthDiskCache: 600,
                        maxHeightDiskCache: 900,
                        placeholder: (context, url) =>
                            const ShimmerPlaceholder.card(),
                        errorWidget: (context, url, error) => Container(
                          color: AppColors.surfaceElevated,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.movie_creation_outlined,
                            color: AppColors.textMuted,
                            size: 32,
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
                          size: 32,
                        ),
                      ),

                    // Тончайший виньеточный градиент снизу для глубины (без тяжелых плашек)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.75, 1.0],
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.28),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Минималистичный индикатор онгоинга/серий внизу постера (деликатная точка или лаконичный бейдж)
                    if (title.latestEpisode != null)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            title.episodesBadgeText,
                            style: AppTypography.badge.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
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
                          minHeight: 3.5,
                          backgroundColor: Colors.black.withValues(alpha: 0.6),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppDimensions.spacingSm + 2),

            // Название аккуратно под постером в молочно-белом цвете
            Text(
              title.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                height: 1.25,
              ),
            ),

            const SizedBox(height: 3),

            // Метаданные через точку: Год • Жанры
            Text(
              _buildMetaSubtitle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }

  String _buildMetaSubtitle() {
    final parts = <String>[];
    if (title.year != null) {
      parts.add('${title.year}');
    }
    if (title.genres.isNotEmpty) {
      parts.addAll(title.genres.take(2));
    } else {
      parts.add(title.status);
    }
    return parts.join(' • ');
  }
}
