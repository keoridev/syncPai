import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/compact_episode_grid.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../downloads/presentation/cubit/download_cubit.dart';
import '../../../watch_history/presentation/cubit/watch_history_cubit.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';

/// Шторка быстрого выбора серии прямо из плеера (Bottom Sheet)
class PlayerEpisodesSheet extends StatefulWidget {
  final PlayerCubit cubit;
  final PlayerState state;

  const PlayerEpisodesSheet({
    super.key,
    required this.cubit,
    required this.state,
  });

  static Future<void> show(
    BuildContext context, {
    required PlayerCubit cubit,
    required PlayerState state,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PlayerEpisodesSheet(cubit: cubit, state: state),
    );
  }

  @override
  State<PlayerEpisodesSheet> createState() => _PlayerEpisodesSheetState();
}

class _PlayerEpisodesSheetState extends State<PlayerEpisodesSheet> {
  bool? _manualCompactGrid;
  int? _selectedRangeIndex;

  @override
  Widget build(BuildContext context) {
    final episodes = widget.state.title.episodes;
    final primary = Theme.of(context).colorScheme.primary;
    final currentEp = widget.state.episode.episode;
    final isCompactGrid =
        _manualCompactGrid ?? (episodes.length > kCompactEpisodeGridThreshold);

    int? lastWatchedEp;
    if (getIt.isRegistered<WatchHistoryCubit>()) {
      lastWatchedEp =
          getIt<WatchHistoryCubit>().state.historyMap[widget.state.title.id]?.episode;
    }
    lastWatchedEp ??= currentEp;

    final effectiveRangeIndex = _selectedRangeIndex ??
        computeEpisodeRangeIndex(episodes, currentEp);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Хэндл
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Заголовок + переключатель вида (список / сетка)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.video_library_rounded, color: primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Выбор серии',
                              style: AppTypography.titleMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Всего серий: ${episodes.isNotEmpty ? episodes.length : widget.state.title.episodesTotal ?? "—"}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      if (episodes.isNotEmpty)
                        IconButton(
                          key: const ValueKey('player_episode_view_toggle'),
                          tooltip: isCompactGrid ? 'Показать списком' : 'Показать сеткой',
                          icon: Icon(
                            isCompactGrid
                                ? Icons.view_agenda_rounded
                                : Icons.grid_view_rounded,
                            color: AppColors.textSecondary,
                            size: 22,
                          ),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _manualCompactGrid = !isCompactGrid;
                            });
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white10, height: 1),

                // Список / сетка серий
                Expanded(
                  child: episodes.isEmpty
                      ? const Center(
                          child: Text(
                            'Список серий недоступен',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        )
                      : isCompactGrid
                          ? CompactEpisodeGrid(
                              episodes: episodes,
                              selectedRangeIndex: effectiveRangeIndex,
                              onRangeSelected: (idx) {
                                setState(() => _selectedRangeIndex = idx);
                              },
                              activeEpisode: currentEp,
                              lastWatchedEpisode: lastWatchedEp,
                              isDownloaded: (epNum) =>
                                  getIt.isRegistered<DownloadCubit>() &&
                                  getIt<DownloadCubit>()
                                      .state
                                      .isDownloaded(widget.state.title.id, epNum),
                              onEpisodeTap: (ep) {
                                HapticFeedback.lightImpact();
                                Navigator.pop(context);
                                widget.cubit.switchEpisode(ep);
                              },
                              onEpisodeLongPress: (ep) => _onEpisodeLongPress(ep),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              itemCount: episodes.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final ep = episodes[index];
                                final isPlaying = ep.episode == currentEp;

                                return InkWell(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.pop(context);
                                    widget.cubit.switchEpisode(ep);
                                  },
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isPlaying
                                          ? primary.withValues(alpha: 0.18)
                                          : Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isPlaying ? primary : Colors.white.withValues(alpha: 0.08),
                                        width: isPlaying ? 1.4 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        // 16:9 Превью момента серии (скриншот эпизода)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Container(
                                            width: 88,
                                            height: 52,
                                            color: Colors.black38,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                if (ep.previewUrl != null && ep.previewUrl!.isNotEmpty)
                                                  CachedNetworkImage(
                                                    imageUrl: wrapCorsSafeUrl(ep.previewUrl!),
                                                    fit: BoxFit.cover,
                                                    memCacheWidth: 200,
                                                    placeholder: (_, __) => const ColoredBox(color: Colors.black26),
                                                    errorWidget: (_, __, ___) =>
                                                        _buildEpisodePlaceholder(widget.state.title.posterSmall),
                                                  )
                                                else
                                                  _buildEpisodePlaceholder(widget.state.title.posterSmall),
                                                if (isPlaying)
                                                  Container(
                                                    color: Colors.black.withValues(alpha: 0.45),
                                                    child: Center(
                                                      child: Container(
                                                        padding: const EdgeInsets.all(6),
                                                        decoration: BoxDecoration(
                                                          color: primary,
                                                          shape: BoxShape.circle,
                                                        ),
                                                        child: const Icon(
                                                          Icons.play_arrow_rounded,
                                                          color: Colors.white,
                                                          size: 16,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  Positioned(
                                                    left: 5,
                                                    bottom: 5,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black.withValues(alpha: 0.70),
                                                        borderRadius: BorderRadius.circular(5),
                                                      ),
                                                      child: Text(
                                                        '#${ep.episode}',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Серия ${ep.episode}',
                                                style: TextStyle(
                                                  color: isPlaying ? primary : AppColors.textPrimary,
                                                  fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w600,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                              if (ep.name != null && ep.name!.isNotEmpty)
                                                Text(
                                                  ep.name!,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: AppColors.textSecondary,
                                                    fontSize: 11.5,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (isPlaying)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: primary,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'СЕЙЧАС',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onEpisodeLongPress(EpisodeItem ep) {
    final title = widget.state.title;
    final isDownloaded = getIt.isRegistered<DownloadCubit>() &&
        getIt<DownloadCubit>().state.isDownloaded(title.id, ep.episode);
    showEpisodeQuickActionsSheet(
      context,
      episode: ep,
      isDownloaded: isDownloaded,
      onDownload: () {
        if (!getIt.isRegistered<DownloadCubit>()) return;
        final streamUrl = ep.fhdUrl ?? ep.hdUrl ?? ep.sdUrl;
        if (streamUrl == null || streamUrl.isEmpty) return;
        final quality = ep.fhdUrl != null
            ? '1080p FHD'
            : (ep.hdUrl != null ? '720p HD' : '480p SD');
        getIt<DownloadCubit>().startSmartDownload(
          title: title,
          episode: ep,
          quality: quality,
        );
      },
      onMarkWatched: () async {
        if (!getIt.isRegistered<WatchHistoryCubit>()) return;
        await getIt<WatchHistoryCubit>().saveProgress(
          titleId: title.id,
          titleName: title.russianTitle,
          posterUrl: title.posterMedium,
          episode: ep.episode,
          episodeName: ep.name,
          position: const Duration(minutes: 24),
          duration: const Duration(minutes: 24),
        );
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildEpisodePlaceholder(String posterUrl) {
    if (posterUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: wrapCorsSafeUrl(posterUrl),
        fit: BoxFit.cover,
        memCacheWidth: 200,
        errorWidget: (_, __, ___) => const ColoredBox(
          color: Colors.black45,
          child: Center(child: Icon(Icons.movie_outlined, color: Colors.white38, size: 22)),
        ),
      );
    }
    return const ColoredBox(
      color: Colors.black45,
      child: Center(child: Icon(Icons.movie_outlined, color: Colors.white38, size: 22)),
    );
  }
}
