import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/network/syncpai_poster_cache_manager.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/services/recommendation_engine.dart';
import 'anime_poster_card.dart';

/// Горизонтальная полка рекомендаций («Для тебя» или «Похожее по вайбу»)
/// с фиксированной геометрией карточек, бейджем в верхнем левом углу
/// и действием «Не интересно».
class ForYouRecommendationsShelf extends StatelessWidget {
  final String title;
  final List<RecommendedAnimePick> picks;
  final ValueChanged<AnimeTitle> onTitleTap;
  final ValueChanged<AnimeTitle>? onDismissPick;
  final bool showBottomDivider;
  final Map<int, AnimeListStatus> userAnimeListsMap;

  const ForYouRecommendationsShelf({
    super.key,
    required this.title,
    required this.picks,
    required this.onTitleTap,
    this.onDismissPick,
    this.showBottomDivider = true,
    this.userAnimeListsMap = const {},
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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
          height: 248,
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
                width: 144,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onTitleTap(anime),
                  onLongPress: () => _showDismissMenu(context, anime),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 144,
                        height: 204,
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
                                      memCacheWidth: 360,
                                      maxWidthDiskCache: 480,
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
                              left: 8,
                              top: 8,
                              right: 36,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  height: 22,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xD10C1018),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.45),
                                      width: 0.8,
                                    ),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    pick.reasonTag,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: InkWell(
                                key: ValueKey('rec_more_${anime.id}'),
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showDismissMenu(context, anime),
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                    color: Color(0xD10C1018),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.more_horiz_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            if (userAnimeListsMap[anime.id] != null)
                              Positioned(
                                left: 8,
                                bottom: 8,
                                child: UserListStatusPill(
                                  status: userAnimeListsMap[anime.id]!,
                                  isCompact: true,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 38,
                        child: Text(
                          anime.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (showBottomDivider) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(height: 12),
        ],
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
