import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/player_navigation_guard.dart';
import '../../../../core/widgets/mascot/mascot_state.dart';
import '../../../../core/widgets/mascot/sync_pai_mascot.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../player/domain/entities/player_quality.dart';
import '../../domain/entities/download_task.dart';
import '../cubit/download_cubit.dart';
import '../cubit/download_state.dart';

/// Экран управления офлайн-загрузками «Менеджер загрузок SyncPai».
/// Поддерживает:
/// - Статусы загрузок (В очереди, скачивается, завершено, ошибка, пауза)
/// - Офлайн-воспроизведение без необходимости подключения к интернету
/// - Управление локальной памятью и индикатор занятого места
/// - Диалоги подтверждения удаления (защита от случайной потери файлов)
/// - Переключение фильтров и красивый пустой экран с Пай-тян
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  int _selectedFilter = 0; // 0: Все, 1: Завершённые, 2: В процессе
  int _storageUsedBytes = 0;

  @override
  void initState() {
    super.initState();
    _refreshStorage();
  }

  Future<void> _refreshStorage() async {
    final cubit = context.read<DownloadCubit>();
    final bytes = await cubit.getStorageUsedBytes();
    if (mounted) {
      setState(() {
        _storageUsedBytes = bytes;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 МБ';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} МБ';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} ГБ';
  }

  void _playOfflineEpisode(DownloadTask task) {
    final file = File(task.localPath);
    if (!file.existsSync() || file.lengthSync() < 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Файл повреждён или перемещён. Попробуйте скачать серию заново.'),
          backgroundColor: AppColors.syncError,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();

    final dummyTitle = AnimeTitle(
      id: task.titleId,
      code: 'download_${task.titleId}',
      russianTitle: task.titleName,
      englishTitle: task.titleName,
      posterSmall: task.posterUrl,
      posterMedium: task.posterUrl,
      posterOriginal: task.posterUrl,
      genres: const [],
      description: 'Локальный офлайн-файл',
      status: 'Офлайн',
    );

    final dummyEpisode = EpisodeItem(
      episode: task.episode,
      name: task.episodeName,
      fhdUrl: task.localPath,
      hdUrl: task.localPath,
      sdUrl: task.localPath,
    );

    PlayerNavigationGuard.openPlayer(
      context,
      extra: {
        'title': dummyTitle,
        'episode': dummyEpisode,
        'quality': PlayerQuality.fhd,
      },
    );
  }

  Future<void> _confirmDeleteTask(DownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141722),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: const Text('Удалить скачанную серию?', style: TextStyle(color: Colors.white)),
        content: Text(
          '«${task.titleName}» — ${task.episodeName}\nФайл будет безвозвратно удален с устройства.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.syncError,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<DownloadCubit>().deleteDownload(task.id);
      await _refreshStorage();
    }
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141722),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: const Text('Очистить все загрузки?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Все скачанные серии будут удалены из памяти устройства. Это действие нельзя отменить.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.syncError,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить всё'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<DownloadCubit>().deleteAllDownloads();
      await _refreshStorage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Офлайн-загрузки',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.textSecondary),
            tooltip: 'Очистить все загрузки',
            onPressed: _confirmDeleteAll,
          ),
        ],
      ),
      body: BlocConsumer<DownloadCubit, DownloadState>(
        listener: (context, state) {
          _refreshStorage();
        },
        builder: (context, state) {
          final allTasks = state.tasks.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final filteredTasks = allTasks.where((t) {
            if (_selectedFilter == 1) return t.status == DownloadStatus.completed;
            if (_selectedFilter == 2) {
              return t.status == DownloadStatus.downloading ||
                  t.status == DownloadStatus.queued ||
                  t.status == DownloadStatus.paused ||
                  t.status == DownloadStatus.failed;
            }
            return true;
          }).toList();

          final completedCount = allTasks.where((t) => t.status == DownloadStatus.completed).length;

          return Column(
            children: [
              // 1. Информационная плашка памяти и хранилища
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.sd_storage_rounded, size: 18, color: themePrimary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Занято серий: $completedCount • ${_formatBytes(_storageUsedBytes)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: themePrimary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Офлайн режим',
                              style: TextStyle(
                                color: themePrimary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (_storageUsedBytes / (10 * 1024 * 1024 * 1024)).clamp(0.02, 1.0),
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation<Color>(themePrimary),
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Фильтр табов
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _buildFilterChip(0, 'Все (${allTasks.length})', themePrimary),
                    const SizedBox(width: 8),
                    _buildFilterChip(1, 'Готовые ($completedCount)', themePrimary),
                    const SizedBox(width: 8),
                    _buildFilterChip(2, 'Активные (${allTasks.length - completedCount})', themePrimary),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 3. Список серий или пустой экран
              Expanded(
                child: filteredTasks.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: filteredTasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final task = filteredTasks[index];
                          return _buildDownloadItemTile(task, themePrimary);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(int index, String label, Color primary) {
    final isSelected = _selectedFilter == index;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = index);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primary.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadItemTile(DownloadTask task, Color primary) {
    final isCompleted = task.status == DownloadStatus.completed;
    final isDownloading = task.status == DownloadStatus.downloading;
    final isPaused = task.status == DownloadStatus.paused;
    final isFailed = task.status == DownloadStatus.failed;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isCompleted ? () => _playOfflineEpisode(task) : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                // Постер аниме
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      if (task.posterUrl.isNotEmpty)
                        Image.network(
                          task.posterUrl,
                          width: 54,
                          height: 76,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPosterPlaceholder(),
                        )
                      else
                        _buildPosterPlaceholder(),
                      if (isCompleted)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.25),
                            child: const Center(
                              child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 28),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Описание серии
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.titleName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.episodeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Прогресс или статус
                      if (isDownloading) ...[
                        Row(
                          children: [
                            Text(
                              '${(task.progress * 100).toInt()}% • ${_formatBytes(task.downloadedBytes)}',
                              style: TextStyle(color: primary, fontSize: 10.5, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: task.progress,
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            valueColor: AlwaysStoppedAnimation<Color>(primary),
                            minHeight: 3,
                          ),
                        ),
                      ] else if (isCompleted) ...[
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.syncActive, size: 13),
                            const SizedBox(width: 4),
                            Text(
                              'Готово к просмотру • ${_formatBytes(task.downloadedBytes > 0 ? task.downloadedBytes : 280 * 1024 * 1024)}',
                              style: const TextStyle(color: AppColors.syncActive, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ] else if (isPaused) ...[
                        Row(
                          children: [
                            const Icon(Icons.pause_circle_rounded, color: Color(0xFFFFB300), size: 13),
                            const SizedBox(width: 4),
                            const Text(
                              'Приостановлено',
                              style: TextStyle(color: Color(0xFFFFB300), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ] else if (isFailed) ...[
                        Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.syncError, size: 13),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                task.errorMessage ?? 'Ошибка скачивания',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.syncError, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Действия
                if (isDownloading)
                  IconButton(
                    icon: const Icon(Icons.pause_rounded, color: Colors.white, size: 20),
                    tooltip: 'Приостановить',
                    onPressed: () => context.read<DownloadCubit>().pauseDownload(task.id),
                  )
                else if (isPaused || isFailed)
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: primary, size: 20),
                    tooltip: 'Повторить',
                    onPressed: () => context.read<DownloadCubit>().resumeDownload(task.id),
                  ),

                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted, size: 19),
                  tooltip: 'Удалить серию',
                  onPressed: () => _confirmDeleteTask(task),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPosterPlaceholder() {
    return Container(
      width: 54,
      height: 76,
      color: Colors.white.withValues(alpha: 0.08),
      child: const Icon(Icons.movie_rounded, color: AppColors.textMuted, size: 24),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 160,
              height: 160,
              child: SyncPaiMascot(
                state: MascotState.emptyAnime,
                size: MascotSize.medium,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ваша офлайн-библиотека пуста',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Скачивайте любимые серии аниме, чтобы смотреть их в дороге без интернета.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentTurquoise,
                foregroundColor: const Color(0xFF0F1117),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.explore_rounded, size: 18),
              label: const Text('Перейти в каталог', style: TextStyle(fontWeight: FontWeight.w800)),
              onPressed: () => context.go('/'),
            ),
          ],
        ),
      ),
    );
  }
}
