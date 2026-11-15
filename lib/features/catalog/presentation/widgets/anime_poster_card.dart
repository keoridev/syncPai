import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/tv_focusable.dart';
import '../../domain/entities/anime_title.dart';

/// Единая карточка аниме (`UnifiedAnimeCard` / `AnimePosterCard`) для Каталога и Моих списков.
/// - Скругления постера `BorderRadius.circular(16)`
/// - Единые пропорции постера (`aspectRatio: 0.68` / `2:3`) без растягивания
/// - `CachedNetworkImage(memCacheWidth: 420, fit: BoxFit.cover)`
/// - Мягкий нижний градиентный скрим, бейдж рейтинга (`★ 8.5`) и компактный стеклянный пилл серий/статуса
/// - Строго 2 строки названия (`maxLines: 2, overflow: TextOverflow.ellipsis`) и единая типографика метаданных
class UnifiedAnimeCard extends StatelessWidget {
  final AnimeTitle title;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double? watchProgress;
  final double? rating;
  final String? statusBadgeText;
  final Color? statusColor;
  final IconData? statusIcon;
  final String? subtitleOverride;
  final bool isSelectionMode;
  final bool isSelected;
  final String? heroTagPrefix;

  const UnifiedAnimeCard({
    super.key,
    required this.title,
    required this.onTap,
    this.onLongPress,
    this.watchProgress,
    this.rating,
    this.statusBadgeText,
    this.statusColor,
    this.statusIcon,
    this.subtitleOverride,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.heroTagPrefix,
  });

  static const double posterRadius = 16.0;
  static const double posterAspectRatio = 0.68;

  @override
  Widget build(BuildContext context) {
    final posterUrl = title.posterUrl;
    final fallbackPoster = title.effectiveFallbackPoster;
    final scheme = Theme.of(context).colorScheme;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth <= 360;
    final effectiveBadgeText = statusBadgeText ?? _defaultTopLeftBadgeText();
    final hasRating = rating != null && rating! > 0;

    return RepaintBoundary(
      child: GestureDetector(
        onLongPress: onLongPress,
        child: TvFocusable(
          onPressed: onTap,
          borderRadius: BorderRadius.circular(posterRadius),
          scaleFactor: 1.04,
          glowColor: AppColors.accentPrimary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Постер с фиксированными пропорциями (0.68 / 2:3) и скруглением 16px
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: posterAspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(posterRadius),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF161A22),
                          borderRadius: BorderRadius.circular(posterRadius),
                          border: Border.all(
                            color: isSelected
                                ? scheme.primary
                                : AppColors.stroke,
                            width: isSelected ? 2.0 : 1.0,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (posterUrl.isNotEmpty)
                              Hero(
                                tag: '${heroTagPrefix ?? 'anime-poster'}-${title.id}',
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

                            // Мягкий виньеточный градиент снизу для глубины
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: const [0.68, 1.0],
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.42),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Верхний левый стеклянный пилл (серии / год / прогресс списка)
                            if (effectiveBadgeText.isNotEmpty)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: statusColor != null
                                          ? statusColor!.withValues(alpha: 0.45)
                                          : Colors.white.withValues(alpha: 0.15),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (statusIcon != null) ...[
                                        Icon(
                                          statusIcon,
                                          size: 10,
                                          color: statusColor ?? Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                      ] else if (statusColor != null) ...[
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        effectiveBadgeText,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Верхний правый пилл оценки (★ 8.5) или чекбокс пакетного выбора
                            if (isSelectionMode)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? scheme.primary
                                        : Colors.black.withValues(alpha: 0.65),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? scheme.primary : Colors.white54,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Icon(Icons.check_rounded, size: 15, color: scheme.onPrimary)
                                      : null,
                                ),
                              )
                            else if (hasRating)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.amber.withValues(alpha: 0.35),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    '★ ${rating!.toStringAsFixed(1)}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFFFD54F),
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
                                  value: watchProgress!.clamp(0.0, 1.0),
                                  minHeight: 3.5,
                                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    statusColor ?? AppColors.primary,
                                  ),
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

              // 2. Название тайтла под постером (строго до 2 строк)
              SizedBox(
                height: 34,
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

              // 3. Метаданные через точку: Год • Жанры (или прогресс серий)
              Text(
                subtitleOverride ?? _buildMetaSubtitle(),
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
      ),
    );
  }

  String _defaultTopLeftBadgeText() {
    if (title.latestEpisode == null && title.year == null) return '';
    if (title.status == 'Онгоинг') {
      return title.latestEpisode != null
          ? 'Онгоинг • ${title.episodesBadgeText}'
          : 'Онгоинг';
    }
    return title.year != null ? '${title.year}' : title.episodesBadgeText;
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

/// Обратно совместимый алиас `UnifiedAnimeCard` для существующих импортов и тестов
class AnimePosterCard extends UnifiedAnimeCard {
  static const double posterRadius = UnifiedAnimeCard.posterRadius;

  const AnimePosterCard({
    super.key,
    required super.title,
    required super.onTap,
    super.onLongPress,
    super.watchProgress,
    super.rating,
    super.statusBadgeText,
    super.statusColor,
    super.statusIcon,
    super.subtitleOverride,
    super.isSelectionMode,
    super.isSelected,
    super.heroTagPrefix,
  });
}
