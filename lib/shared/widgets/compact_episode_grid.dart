import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/catalog/domain/entities/episode_item.dart';

/// Порог количества серий, после которого автоматически включается компактная сетка.
const int kCompactEpisodeGridThreshold = 36;

/// Размер одного диапазона серий для чипов пагинации (1–100, 101–200, ...).
const int kEpisodeRangeChunkSize = 100;

/// Вычисляет индекс диапазона [0..chunks-1], в котором находится [targetEpisode].
int computeEpisodeRangeIndex(
  List<EpisodeItem> episodes,
  int? targetEpisode, {
  int chunkSize = kEpisodeRangeChunkSize,
}) {
  if (episodes.isEmpty || targetEpisode == null) return 0;
  final idx = episodes.indexWhere((e) => e.episode == targetEpisode);
  if (idx >= 0) {
    return idx ~/ chunkSize;
  }
  for (var i = 0; i < episodes.length; i++) {
    if (episodes[i].episode >= targetEpisode) {
      return i ~/ chunkSize;
    }
  }
  return (episodes.length - 1) ~/ chunkSize;
}

/// Возвращает срез серий для выбранного диапазона [rangeIndex].
List<EpisodeItem> sliceEpisodesForRange(
  List<EpisodeItem> episodes,
  int rangeIndex, {
  int chunkSize = kEpisodeRangeChunkSize,
}) {
  if (episodes.length <= chunkSize) return episodes;
  final totalChunks = (episodes.length / chunkSize).ceil();
  final safeIndex = rangeIndex.clamp(0, totalChunks - 1);
  final start = safeIndex * chunkSize;
  final end = math.min(start + chunkSize, episodes.length);
  return episodes.sublist(start, end);
}

/// Горизонтальная лента тональных чипов диапазонов (`1–100`, `101–200`, ...).
class EpisodeRangeChips extends StatelessWidget {
  final List<EpisodeItem> episodes;
  final int selectedRangeIndex;
  final ValueChanged<int> onRangeSelected;
  final EdgeInsetsGeometry padding;

  const EpisodeRangeChips({
    super.key,
    required this.episodes,
    required this.selectedRangeIndex,
    required this.onRangeSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    if (episodes.length <= kEpisodeRangeChunkSize) {
      return const SizedBox.shrink();
    }

    final chunkCount = (episodes.length / kEpisodeRangeChunkSize).ceil();
    final safeSelected = selectedRangeIndex.clamp(0, chunkCount - 1);

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: chunkCount,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final start = index * kEpisodeRangeChunkSize;
          final end = math.min(start + kEpisodeRangeChunkSize, episodes.length);
          final label = '${episodes[start].episode}–${episodes[end - 1].episode}';
          final isSelected = index == safeSelected;

          return Material(
            color: isSelected
                ? const Color(0xFFFF6B4A)
                : const Color(0xFF1A2030),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                HapticFeedback.selectionClick();
                onRangeSelected(index);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.78),
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Тональная плитка номера серии в компактной сетке без рамок.
class CompactEpisodeTile extends StatelessWidget {
  final EpisodeItem episode;
  final bool isActive;
  final bool isWatched;
  final bool isDownloaded;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const CompactEpisodeTile({
    super.key,
    required this.episode,
    required this.isActive,
    required this.isWatched,
    required this.isDownloaded,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color textColor;

    if (isActive) {
      bgColor = const Color(0xFFFF6B4A);
      textColor = Colors.white;
    } else if (isWatched) {
      bgColor = const Color(0xFF121620);
      textColor = Colors.white38;
    } else {
      bgColor = const Color(0xFF1A2030);
      textColor = Colors.white.withValues(alpha: 0.87);
    }

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onLongPress!();
              },
        child: Stack(
          children: [
            Center(
              child: Text(
                '${episode.episode}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isDownloaded)
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFF35D9D5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Модальное меню быстрых действий по долгому нажатию на плитку серии.
Future<void> showEpisodeQuickActionsSheet(
  BuildContext context, {
  required EpisodeItem episode,
  required bool isDownloaded,
  required VoidCallback onDownload,
  required VoidCallback onMarkWatched,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF141824),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  episode.name != null && episode.name!.trim().isNotEmpty
                      ? 'Серия ${episode.episode} · ${episode.name!.trim()}'
                      : 'Серия ${episode.episode}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  isDownloaded
                      ? Icons.download_done_rounded
                      : Icons.download_for_offline_outlined,
                  color: const Color(0xFF35D9D5),
                ),
                title: Text(
                  isDownloaded ? 'Серия уже скачана' : 'Скачать серию',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  if (!isDownloaded) {
                    onDownload();
                  }
                },
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFFFF6B4A),
                ),
                title: const Text(
                  'Отметить просмотренной',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onMarkWatched();
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Компактная сетка серий с чипами диапазонов для модальных окон (например, [PlayerEpisodesSheet]).
class CompactEpisodeGrid extends StatelessWidget {
  static const SliverGridDelegateWithMaxCrossAxisExtent gridDelegate =
      SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 64,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childAspectRatio: 1.35,
  );

  final List<EpisodeItem> episodes;
  final int selectedRangeIndex;
  final ValueChanged<int> onRangeSelected;
  final int? activeEpisode;
  final int? lastWatchedEpisode;
  final bool Function(int episodeNumber)? isDownloaded;
  final ValueChanged<EpisodeItem> onEpisodeTap;
  final ValueChanged<EpisodeItem>? onEpisodeLongPress;
  final EdgeInsetsGeometry gridPadding;

  const CompactEpisodeGrid({
    super.key,
    required this.episodes,
    required this.selectedRangeIndex,
    required this.onRangeSelected,
    this.activeEpisode,
    this.lastWatchedEpisode,
    this.isDownloaded,
    required this.onEpisodeTap,
    this.onEpisodeLongPress,
    this.gridPadding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    final visibleEpisodes = sliceEpisodesForRange(episodes, selectedRangeIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (episodes.length > kEpisodeRangeChunkSize) ...[
          const SizedBox(height: 10),
          EpisodeRangeChips(
            episodes: episodes,
            selectedRangeIndex: selectedRangeIndex,
            onRangeSelected: onRangeSelected,
          ),
        ],
        Expanded(
          child: GridView.builder(
            padding: gridPadding,
            gridDelegate: gridDelegate,
            itemCount: visibleEpisodes.length,
            itemBuilder: (context, index) {
              final ep = visibleEpisodes[index];
              final isActive = activeEpisode != null && ep.episode == activeEpisode;
              final isWatched = !isActive &&
                  lastWatchedEpisode != null &&
                  ep.episode <= lastWatchedEpisode!;
              final downloaded = isDownloaded?.call(ep.episode) ?? false;

              return CompactEpisodeTile(
                episode: ep,
                isActive: isActive,
                isWatched: isWatched,
                isDownloaded: downloaded,
                onTap: () => onEpisodeTap(ep),
                onLongPress: onEpisodeLongPress == null
                    ? null
                    : () => onEpisodeLongPress!(ep),
              );
            },
          ),
        ),
      ],
    );
  }
}
