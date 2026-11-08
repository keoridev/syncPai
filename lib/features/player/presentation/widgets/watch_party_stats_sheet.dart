import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/widgets/glass_container.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';

/// Интерактивная карточка «Watch Party Сторис» (Spotify Wrapped-стиль для аниме)
class WatchPartyStatsSheet extends StatelessWidget {
  final AnimeTitle title;
  final EpisodeItem episode;
  final int pauseCount;
  final int emojisSent;
  final int peerPingMs;
  final String peerName;
  final VoidCallback onClose;

  const WatchPartyStatsSheet({
    super.key,
    required this.title,
    required this.episode,
    required this.pauseCount,
    required this.emojisSent,
    required this.peerPingMs,
    required this.peerName,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: GlassContainer(
            borderRadius: BorderRadius.circular(28),
            blurSigma: 24,
            backgroundOpacity: 0.16,
            customBorder: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.4), width: 1.5),
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.auto_awesome_rounded, color: AppColors.primaryLight, size: 18),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'WATCH PARTY WRAPPED',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Превью тайтла
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 120,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: title.posterMedium.isNotEmpty ? title.posterMedium : title.posterSmall,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                        ),
                        Container(
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Серия ${episode.episode} досмотрена вместе!',
                                  style: TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Статистика сессии
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        '⏸️ Пауз в комнате',
                        '$pauseCount раз',
                        pauseCount > 3 ? 'Главный тормоз: $peerName' : 'Идеальный темп',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMetricCard(
                        '🔥 Эмодзи Danmaku',
                        '$emojisSent шт.',
                        'Эмоциональный просмотр',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Кнопка «Поделиться сторис»
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Поделиться в Telegram / Сторис', style: TextStyle(fontWeight: FontWeight.w800)),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Clipboard.setData(ClipboardData(
                        text: 'Смотрели ${title.displayTitle} (серия ${episode.episode}) вместе в SyncPai! 🍿🔥',
                      ));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Текст и статистика скопированы для Stories!'),
                          backgroundColor: AppColors.syncActive,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, String sub) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 2),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

