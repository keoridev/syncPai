import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/tv_focusable.dart';
import '../../domain/entities/anime_title.dart';

/// Карточка аниме в стиле Cinematic Dark / Nordic Dark.
/// - Большие скругления постера (12px)
/// - Строгие пропорции постера 2:3 без растягивания или искажений
/// - Темный плейсхолдер (#161A22) с иконкой киноленты
/// - Заглушка при ошибке загрузки постера с названием аниме
/// - Название аккуратно под постером молочно-белым цветом (строго 2 строки)
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

  static const double posterRadius = 12.0;

  @override
  Widget build(BuildContext context) {
    final posterUrl = title.posterUrl;
    final fallbackPoster = title.effectiveFallbackPoster;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth <= 360;

    return RepaintBoundary(
      child: TvFocusable(
        onPressed: onTap,
        borderRadius: BorderRadius.circular(posterRadius),
        scaleFactor: 1.04,
        glowColor: AppColors.accentPrimary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Постер с жестко зафиксированными пропорциями 2:3 без растягивания
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(posterRadius),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF161A22),
                        borderRadius: BorderRadius.circular(posterRadius),
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
                                memCacheWidth: 420,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                httpHeaders: const {
                                  'User-Agent':
                                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                                },
                                placeholder: (context, url) => _buildPlaceholder(),
                                errorWidget: (context, primaryUrl, error) {
                                  if (fallbackPoster.isNotEmpty && fallbackPoster != posterUrl) {
                                    return CachedNetworkImage(
                                      imageUrl: wrapCorsSafeUrl(fallbackPoster),
                                      memCacheWidth: 420,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      httpHeaders: const {
                                        'User-Agent':
                                            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                                      },
                                      placeholder: (context, url) => _buildPlaceholder(),
                                      errorWidget: (context, fallbackUrl, error) =>
                                          _buildErrorPlaceholder(),
                                    );
                                  }
                                  return _buildErrorPlaceholder();
                                },
                              ),
                            )
                          else
                            _buildPlaceholder(),

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
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
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
                                      ? (title.latestEpisode != null
                                          ? 'Онгоинг • ${title.episodesBadgeText}'
                                          : 'Онгоинг')
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
              ),
            ),

            const SizedBox(height: 6),

            // 2. Название тайтла прямо под постером молочно-белым текстом (строго до 2 строк)
            SizedBox(
              height: 36,
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

            // 3. Метаданные через точку: Год • Серии • Жанры
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

  /// Стильный тёмный плейсхолдер (#161A22 с иконкой киноленты и деликатным индикатором)
  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF161A22),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_movies_rounded,
            color: AppColors.textMuted.withValues(alpha: 0.5),
            size: 28,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.white.withValues(alpha: 0.25),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Заглушка при ошибке загрузки обложки: аккуратный тёмный блок (#161A22) с названием тайтла
  Widget _buildErrorPlaceholder() {
    return Container(
      color: const Color(0xFF161A22),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.movie_outlined,
              color: AppColors.textMuted.withValues(alpha: 0.8),
              size: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              fontSize: 10.5,
              height: 1.2,
            ),
          ),
          if (title.year != null) ...[
            const SizedBox(height: 4),
            Text(
              '${title.year}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
                fontSize: 9.5,
              ),
            ),
          ],
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
