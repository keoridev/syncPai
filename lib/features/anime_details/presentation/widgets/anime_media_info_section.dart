import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../domain/entities/anime_video_item.dart';
import '../../domain/entities/related_anime_release.dart';
import '../../domain/entities/user_lists_stats.dart';
import 'anime_videos_section.dart';
import 'franchise_progression_chart.dart';
import 'related_releases_section.dart';
import 'user_lists_distribution_widget.dart';

/// Вкладка «О тайтле» (Медиа, Связанные сезоны, Видео и Трейлеры, Распределение по спискам).
class AnimeMediaInfoSection extends StatelessWidget {
  final AnimeTitle title;
  final VoidCallback? onOpenTrailer;
  final VoidCallback? onOpenAllVideos;
  final VoidCallback? onShowAllComments;
  final List<RelatedAnimeRelease> relatedReleases;
  final ValueChanged<RelatedAnimeRelease>? onReleaseSelected;
  final List<AnimeVideoItem> videos;
  final UserListsStats userStats;

  const AnimeMediaInfoSection({
    super.key,
    required this.title,
    this.onOpenTrailer,
    this.onOpenAllVideos,
    this.onShowAllComments,
    this.relatedReleases = const [],
    this.onReleaseSelected,
    this.videos = const [],
    this.userStats = const UserListsStats(),
  });

  @override
  Widget build(BuildContext context) {
    final ep = title.episodes.isNotEmpty ? title.episodes.first : null;
    final opening = ep?.opening;
    final ending = ep?.ending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. «В списках у людей» (Anixart / Shikimori статус-бар)
        UserListsDistributionWidget(stats: userStats),
        const SizedBox(height: 20),

        // 2. «Связанные релизы» (Сезоны, Фильмы, Спин-оффы)
        if (relatedReleases.isNotEmpty) ...[
          RelatedReleasesSection(
            releases: relatedReleases,
            onReleaseSelected: onReleaseSelected,
            onShowAllComments: onShowAllComments,
          ),
          const SizedBox(height: 20),
          if (relatedReleases.length >= 2) ...[
            FranchiseProgressionChart(
              releases: relatedReleases,
              onReleaseSelected: onReleaseSelected,
            ),
            const SizedBox(height: 20),
          ],
        ],

        // 3. «Видео & Трейлеры» (Карусель PV + список промо-роликов)
        if (videos.isNotEmpty) ...[
          AnimeVideosSection(
            videos: videos,
            animeTitle: title.displayTitle,
            onOpenAllVideos: onOpenAllVideos,
          ),
          const SizedBox(height: 20),
        ] else if (title.trailerUrl != null && title.trailerUrl!.isNotEmpty) ...[
          // Fallback карточка трейлера если список видео пуст
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.strokeMedium),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0000).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.play_circle_fill_rounded,
                    color: Color(0xFFFF0000),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Официальный трейлер',
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'YouTube • HD 1080p',
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.strokeMedium),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: const Text('Смотреть', style: TextStyle(fontSize: 12)),
                  onPressed: onOpenTrailer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // 4. Карточка Опенинга и Эндинга
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.strokeMedium),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'МУЗЫКА И ТАЙМКОДЫ',
                style: AppTypography.caption.copyWith(
                  letterSpacing: 1.2,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
              const SizedBox(height: 14),

              // Опенинг
              _buildMusicRow(
                icon: Icons.music_note_rounded,
                iconColor: AppColors.primary,
                title: 'Opening (Опенинг)',
                subtitle: opening != null
                    ? '${_formatSec(opening.start)} — ${_formatSec(opening.stop)} (90 сек)'
                    : 'Стандартный хронометраж ~90 сек',
                badgeText: 'Авто-пропуск',
                badgeColor: AppColors.primary,
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: AppColors.strokeMedium, height: 1),
              ),

              // Эндинг
              _buildMusicRow(
                icon: Icons.headphones_rounded,
                iconColor: AppColors.syncActive,
                title: 'Ending (Эндинг)',
                subtitle: ending != null
                    ? '${_formatSec(ending.start)} — ${_formatSec(ending.stop)}'
                    : 'В конце каждого эпизода',
                badgeText: 'Титры',
                badgeColor: AppColors.syncActive,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMusicRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
          ),
          child: Text(
            badgeText,
            style: AppTypography.caption.copyWith(
              color: badgeColor,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  static String _formatSec(int totalSec) {
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
