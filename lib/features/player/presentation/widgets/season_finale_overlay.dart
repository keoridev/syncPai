import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/network/image_cors_helper.dart';
import '../cubit/player_state.dart';

/// Встроенная карточка финала сезона поверх видеополотна (для Android и Windows Desktop).
/// Никогда не перекрывает список серий под плеером или правый сайдбар на десктопе.
class SeasonFinaleOverlay extends StatelessWidget {
  final SeasonFinalePrompt prompt;
  final VoidCallback onDismiss;
  final VoidCallback? onWatchSequel;
  final VoidCallback? onAddPlanned;
  final VoidCallback? onReadManga;
  final VoidCallback onFindSimilar;

  const SeasonFinaleOverlay({
    super.key,
    required this.prompt,
    required this.onDismiss,
    this.onWatchSequel,
    this.onAddPlanned,
    this.onReadManga,
    required this.onFindSimilar,
  });

  @override
  Widget build(BuildContext context) {
    final nextSeason = prompt.nextSeason;
    final bridge = prompt.mangaBridge;
    final hasPlayableSequel = nextSeason != null && !nextSeason.isAnnounced;
    final hasAnnouncedSequel = nextSeason != null && nextSeason.isAnnounced;

    late final String headline;
    late final String subtitle;
    late final String primaryLabel;
    VoidCallback? primaryAction;

    if (hasPlayableSequel) {
      headline = 'Доступен следующий сезон: ${nextSeason.name}';
      subtitle = 'Можно сразу перейти к просмотру продолжения.';
      primaryLabel = 'Смотреть ${nextSeason.name}';
      primaryAction = onWatchSequel;
    } else if (bridge != null) {
      headline = 'Продолжения аниме пока нет';
      subtitle = 'Сюжет идёт дальше в манге «${bridge.mangaTitle}»';
      primaryLabel = bridge.continueFromChapter != null
          ? 'Читать мангу с ${bridge.continueFromChapter} главы'
          : 'Открыть мангу';
      primaryAction = onReadManga;
    } else if (hasAnnouncedSequel) {
      headline = 'Анонсирован следующий сезон: ${nextSeason.name}';
      subtitle = 'Добавьте продолжение в планы, чтобы не пропустить выход.';
      primaryLabel = 'В планах';
      primaryAction = onAddPlanned;
    } else {
      headline = 'Сезон завершён';
      subtitle = 'Подберите похожие тайтлы по жанру и атмосфере.';
      primaryLabel = 'Похожие аниме';
      primaryAction = onFindSimilar;
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          color: Colors.black.withValues(alpha: 0.48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Container(
                key: const ValueKey('season_finale_overlay_card'),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xE611151E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x1FFFFFFF)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipOval(
                              child: Image.asset(
                                'assets/mascot/general/mascot_happy.png',
                                width: 34,
                                height: 34,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: Icon(
                                    Icons.auto_awesome_rounded,
                                    color: Color(0xFFFF6B4A),
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            if (bridge != null &&
                                bridge.coverUrl.trim().isNotEmpty) ...[
                              const SizedBox(width: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 32,
                                  height: 44,
                                  child: CachedNetworkImage(
                                    imageUrl: wrapCorsSafeUrl(bridge.coverUrl),
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: const Color(0xFF1C212E),
                                      child: const Icon(
                                        Icons.menu_book_rounded,
                                        color: Colors.white38,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1C212E),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0x1FFFFFFF),
                                  ),
                                ),
                                child: const Text(
                                  'ФИНАЛ СЕЗОНА',
                                  style: TextStyle(
                                    color: Color(0xFFFF6B4A),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                headline,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                softWrap: true,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('season_finale_close_btn'),
                          onPressed: onDismiss,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white60,
                            size: 18,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Закрыть',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (primaryAction != null)
                          FilledButton.icon(
                            key: const ValueKey('season_finale_primary_btn'),
                            onPressed: primaryAction,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B4A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: Icon(
                              bridge != null && !hasPlayableSequel
                                  ? Icons.menu_book_rounded
                                  : Icons.play_arrow_rounded,
                              size: 16,
                            ),
                            label: Text(
                              primaryLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (bridge != null || hasPlayableSequel || hasAnnouncedSequel)
                          OutlinedButton(
                            key: const ValueKey('season_finale_similar_btn'),
                            onPressed: onFindSimilar,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFF1C212E),
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0x1FFFFFFF)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Похожие аниме',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

