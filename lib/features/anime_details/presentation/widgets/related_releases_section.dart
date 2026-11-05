import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';
import '../../domain/entities/related_anime_release.dart';

/// Секция «Связанные релизы» (Сезоны, Фильмы, Предыстории и Продолжения)
/// с блоками «В коллекциях» и «Комментарии».
/// В точности повторяет экран из Screenshot 1.
class RelatedReleasesSection extends StatelessWidget {
  final List<RelatedAnimeRelease> releases;
  final ValueChanged<RelatedAnimeRelease>? onReleaseSelected;
  final VoidCallback? onOpenCollections;
  final VoidCallback? onAddToCollection;
  final VoidCallback? onShowAllComments;
  final int collectionsCount;

  const RelatedReleasesSection({
    super.key,
    required this.releases,
    this.onReleaseSelected,
    this.onOpenCollections,
    this.onAddToCollection,
    this.onShowAllComments,
    this.collectionsCount = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (releases.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок раздела «Связанные релизы»
        Text(
          'Связанные релизы',
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16.5,
          ),
        ),
        const SizedBox(height: 14),

        // Список частей / сезонов франшизы
        ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: releases.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final release = releases[index];
            return _buildReleaseItem(context, release);
          },
        ),

        const SizedBox(height: 18),
        Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
        const SizedBox(height: 16),

        // Секция: Комментарии (Показать все)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Комментарии',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Популярные и актуальные',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: onShowAllComments,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Показать все',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReleaseItem(BuildContext context, RelatedAnimeRelease release) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: release.isCurrent ? null : () => onReleaseSelected?.call(release),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Постер релиза (48 x 68 скругление 8)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 68,
                  child: release.posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: release.posterUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const ShimmerPlaceholder.card(),
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.surfaceElevated,
                            child: const Icon(
                              Icons.movie_outlined,
                              color: AppColors.textMuted,
                              size: 22,
                            ),
                          ),
                        )
                      : Container(
                          color: AppColors.surfaceElevated,
                          child: const Icon(
                            Icons.movie_outlined,
                            color: AppColors.textMuted,
                            size: 22,
                          ),
                        ),
                ),
              ),

              const SizedBox(width: 14),

              // 2. Описание: Название, Год • Рейтинг ★ [Сериал]
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      release.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        if (release.year != null && release.year!.isNotEmpty)
                          Text(
                            release.year!,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        if (release.year != null && release.rating != null && release.rating! > 0)
                          const Text(
                            '•',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        if (release.rating != null && release.rating! > 0) ...[
                          Text(
                            '${release.rating}',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: Color(0xFFFFB300),
                          ),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            release.kind,
                            style: AppTypography.caption.copyWith(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 3. Статус: «Вы здесь» с тонкой разделительной чертой для текущего сезона
              if (release.isCurrent) ...[
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 34,
                  color: Colors.white.withValues(alpha: 0.14),
                ),
                const SizedBox(width: 10),
                Text(
                  'Вы\nздесь',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
