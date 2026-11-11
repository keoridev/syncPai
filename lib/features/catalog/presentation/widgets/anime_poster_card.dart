import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/tv_focusable.dart';
import '../../domain/entities/anime_title.dart';

/// Карточка аниме в стиле Cinematic Dark / Nordic Dark.
/// - Большие скругления постера (18px)
/// - Чистый арт без технических коробок и плашек поверх картинки
/// - Название аккуратно под постером молочно-белым цветом
/// - Метаданные (год, серии, жанры) через точку
/// - Высокая частота обновления (60-120 FPS): изоляция слоев через RepaintBoundary
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

  static const double cardRadius = 16.0;

  @override
  Widget build(BuildContext context) {
    final posterUrl = title.posterUrl;
    final fallbackPoster = title.effectiveFallbackPoster;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth <= 360;

    return RepaintBoundary(
      child: TvFocusable(
        onPressed: onTap,
        borderRadius: BorderRadius.circular(cardRadius),
        scaleFactor: 1.04,
        glowColor: AppColors.accentPrimary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Строгий аспект 2:3 для постера
            Expanded(
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(cardRadius),
                    border: Border.all(
                      color: AppColors.stroke,
                      width: 1.0,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (posterUrl.isNotEmpty)
                      Hero(
                        tag: 'anime-poster-${title.id}',
                        child: CachedNetworkImage(
                          imageUrl: wrapCorsSafeUrl(posterUrl),
                          memCacheWidth: 400,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          httpHeaders: const {
                            'User-Agent':
                                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                          },
                          placeholder: (context, url) => Container(
                            color: AppColors.surfaceElevated,
                            child: const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (context, primaryUrl, error) {
                            if (fallbackPoster.isNotEmpty &&
                                fallbackPoster != posterUrl) {
                              return CachedNetworkImage(
                                imageUrl: wrapCorsSafeUrl(fallbackPoster),
                                memCacheWidth: 400,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                httpHeaders: const {
                                  'User-Agent':
                                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                                },
                                placeholder: (context, url) => Container(
                                  color: AppColors.surfaceElevated,
                                  child: const Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                      ),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, fallbackUrl, error) =>
                                    _buildImagePlaceholder(),
                              );
                            }
                            return _buildImagePlaceholder();
                          },
                        ),
                      )
                    else
                      _buildImagePlaceholder(),

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

            // Полупрозрачный бейдж года / онгоинга поверх постера
            if (title.latestEpisode != null || title.year != null)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    title.status == 'Онгоинг'
                        ? (title.latestEpisode != null ? 'Онгоинг • ${title.episodesBadgeText}' : 'Онгоинг')
                        : (title.year != null ? '${title.year}' : title.episodesBadgeText),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // Тонкая полоска сохраненного прогресса просмотра
            if (watchProgress != null &&
                watchProgress! > 0.0 &&
                watchProgress! < 0.98)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: watchProgress!,
                  minHeight: 3.5,
                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
          ],
        ),
      ),
    ),
  ),

    const SizedBox(height: 6),

    // Название тайтла прямо под постером молочно-белым текстом (строго до 2 строк с фиксированной высотой)
    SizedBox(
      height: 38,
      child: Text(
        title.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.start,
        style: AppTypography.bodySmall.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: isNarrow ? 11.5 : 12.5,
          height: 1.25,
          color: AppColors.textPrimary,
          letterSpacing: -0.1,
        ),
      ),
    ),

    const SizedBox(height: 2),

    // Метаданные через точку: Год • Серии • Жанры
    Text(
      _buildMetaSubtitle(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption.copyWith(
        fontSize: 10.5,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
        letterSpacing: 0.1,
      ),
    ),
  ],
),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: AppColors.surfaceElevated,
      alignment: Alignment.center,
      child: const Icon(
        Icons.movie_creation_outlined,
        color: AppColors.textMuted,
        size: 32,
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
