import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/network/syncpai_poster_cache_manager.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/services/recommendation_engine.dart';

/// Горизонтальная полка рекомендаций («Для тебя» или «Похожее по вайбу»)
/// с причиной подбора и действием «Не интересно».
class ForYouRecommendationsShelf extends StatelessWidget {
  final String title;
  final List<RecommendedAnimePick> picks;
  final ValueChanged<AnimeTitle> onTitleTap;
  final ValueChanged<AnimeTitle>? onDismissPick;

  const ForYouRecommendationsShelf({
    super.key,
    required this.title,
    required this.picks,
    required this.onTitleTap,
    this.onDismissPick,
  });

  @override
  Widget build(BuildContext context) {
    if (picks.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 17, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${picks.length} тайтлов',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: picks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final pick = picks[index];
              final anime = pick.anime;
              final poster = anime.posterMedium.isNotEmpty
                  ? anime.posterMedium
                  : (anime.posterOriginal.isNotEmpty
                      ? anime.posterOriginal
                      : anime.posterSmall);

              return SizedBox(
                key: ValueKey('rec_card_${anime.id}'),
                width: 138,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onTitleTap(anime),
                  onLongPress: () => _showDismissMenu(context, anime),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: poster.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: wrapCorsSafeUrl(poster),
                                      cacheKey: poster,
                                      cacheManager: SyncPaiPosterCacheManager.instance,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        color: const Color(0xFF141824),
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: const Color(0xFF141824),
                                        child: const Icon(
                                          Icons.movie_outlined,
                                          color: Colors.white24,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: const Color(0xFF141824),
                                      child: const Icon(
                                        Icons.movie_outlined,
                                        color: Colors.white24,
                                      ),
                                    ),
                            ),
                            Positioned(
                              left: 6,
                              right: 28,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.78),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.45),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  pick.reasonTag,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: InkWell(
                                key: ValueKey('rec_more_${anime.id}'),
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showDismissMenu(context, anime),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.more_horiz_rounded,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        anime.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showDismissMenu(BuildContext context, AnimeTitle anime) async {
    final dismiss = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF12161F),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                key: ValueKey('rec_not_interested_${anime.id}'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(
                  Icons.visibility_off_outlined,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Не интересно',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  'Скрыть «${anime.displayTitle}» и реже показывать похожие жанры',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
                onTap: () => Navigator.of(ctx).pop(true),
              ),
            ),
          ),
        ),
      ),
    );

    if (dismiss == true) {
      await RecommendationEngine.instance.dismissRecommendation(anime);
      onDismissPick?.call(anime);
    }
  }
}
