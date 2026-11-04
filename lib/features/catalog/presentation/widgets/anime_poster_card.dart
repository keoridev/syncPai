import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';
import '../../domain/entities/anime_title.dart';

/// Карточка аниме в стиле Cinema Dark / Nordic Dark.
/// Постер занимает главное место с мягким затемнением внизу и аккуратным бейджем серии.
class AnimePosterCard extends StatelessWidget {
  final AnimeTitle title;
  final VoidCallback onTap;

  const AnimePosterCard({
    super.key,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final posterUrl = title.posterMedium.isNotEmpty
        ? title.posterMedium
        : title.posterSmall;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppDimensions.borderRadiusCard,
        splashColor: AppColors.strokeMedium,
        highlightColor: AppColors.stroke,
        child: Container(
          decoration: AppDecorations.cardDecoration,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Контейнер постера с градиентом
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Изображение постера
                    if (posterUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const ShimmerPlaceholder.card(),
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

                    // Мягкое затемнение постера снизу
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.4, 0.75, 1.0],
                            colors: [
                              Colors.transparent,
                              AppColors.surface.withValues(alpha: 0.4),
                              AppColors.surface,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Бейдж последней серии в нижнем левом углу постера
                    Positioned(
                      left: AppDimensions.spacingSm,
                      bottom: AppDimensions.spacingSm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.spacingSm,
                          vertical: AppDimensions.spacing2xs + 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background.withValues(alpha: 0.82),
                          borderRadius: AppDimensions.borderRadiusSmall,
                          border: Border.all(
                            color: AppColors.strokeMedium,
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          title.episodesBadgeText,
                          style: AppTypography.badge.copyWith(
                            fontSize: 10.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),

                    // Год / Сезон в верхнем правом углу
                    if (title.year != null)
                      Positioned(
                        top: AppDimensions.spacingSm,
                        right: AppDimensions.spacingSm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimensions.spacingXs + 3,
                            vertical: AppDimensions.spacing2xs,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background.withValues(alpha: 0.75),
                            borderRadius: AppDimensions.borderRadiusSmall,
                          ),
                          child: Text(
                            '${title.year}',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Подпись тайтла и жанры
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.spacingMd,
                  AppDimensions.spacingSm,
                  AppDimensions.spacingMd,
                  AppDimensions.spacingMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.textPrimary,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacing2xs),
                    Text(
                      title.genres.isNotEmpty
                          ? title.genres.take(2).join(' • ')
                          : title.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

