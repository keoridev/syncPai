import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';
import '../../../../core/widgets/tv_focusable.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import '../../../downloads/domain/entities/download_task.dart';
import '../../../downloads/presentation/cubit/download_cubit.dart';
import '../../../downloads/presentation/cubit/download_state.dart';
import '../../../player/domain/entities/player_quality.dart';
import '../../../watch_history/presentation/cubit/watch_history_cubit.dart';
import '../../../watch_history/presentation/cubit/watch_history_state.dart';
import '../../domain/entities/user_anime_entry.dart';
import '../cubit/anime_list_cubit.dart';
import '../cubit/anime_list_state.dart';

class SavedAnimeScreen extends StatefulWidget {
  final ValueChanged<AnimeTitle>? onTitleSelected;
  final VoidCallback? onGoToCatalog;

  const SavedAnimeScreen({
    super.key,
    this.onTitleSelected,
    this.onGoToCatalog,
  });

  @override
  State<SavedAnimeScreen> createState() => _SavedAnimeScreenState();
}

enum SavedAnimeViewMode { list, grid, card }

enum SavedAnimeSort {
  dateAdded('По дате обновления', Icons.access_time_rounded),
  alphabetical('По алфавиту (А–Я)', Icons.sort_by_alpha_rounded),
  progress('По прогрессу серий', Icons.play_circle_outline_rounded);

  final String label;
  final IconData icon;
  const SavedAnimeSort(this.label, this.icon);
}

class _SavedAnimeScreenState extends State<SavedAnimeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  SavedAnimeViewMode _viewMode = SavedAnimeViewMode.list;
  SavedAnimeSort _sortBy = SavedAnimeSort.dateAdded;

  // Массовое управление (Batch Edit)
  bool _isSelectionMode = false;
  final Set<int> _selectedAnimeIds = {};

  // Кэш запросов фоновой подгрузки постеров
  final Set<int> _posterFetchAttempts = {};

  void _showSortSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.strokeMedium,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Сортировка списка',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ...SavedAnimeSort.values.map((sort) {
                  final isSelected = sort == _sortBy;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      sort.icon,
                      color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
                      size: 20,
                    ),
                    title: Text(
                      sort.label,
                      style: TextStyle(
                        color: isSelected ? AppColors.primaryLight : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_rounded, color: AppColors.primaryLight, size: 20)
                        : null,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _sortBy = sort);
                      Navigator.pop(ctx);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  String _resolvePosterUrl(UserAnimeEntry entry) {
    if (entry.posterUrl != null &&
        entry.posterUrl!.isNotEmpty &&
        !entry.posterUrl!.contains('placeholder') &&
        entry.posterUrl!.startsWith('http')) {
      return entry.posterUrl!;
    }
    try {
      final catalogState = context.read<CatalogCubit>().state;
      if (catalogState is CatalogLoaded) {
        final clean = entry.cleanTitleRu.toLowerCase().trim();
        final match = catalogState.titles.firstWhere(
          (t) =>
              t.id == entry.animeId ||
              t.russianTitle.toLowerCase().trim() == clean ||
              (t.englishTitle.isNotEmpty &&
                  t.englishTitle.toLowerCase().trim() == clean),
        );
        if (match.posterMedium.isNotEmpty) return match.posterMedium;
        if (match.posterOriginal.isNotEmpty) return match.posterOriginal;
        if (match.posterSmall.isNotEmpty) return match.posterSmall;
      }
    } catch (_) {}
    return entry.posterUrl ?? '';
  }

  /// Тихо и незаметно найти постер в API AniLibria/каталоге и закэшировать в базе
  void _triggerPosterFetch(UserAnimeEntry entry) {
    if (_posterFetchAttempts.contains(entry.animeId)) return;
    _posterFetchAttempts.add(entry.animeId);

    final titleToSearch = entry.cleanTitleRu.isNotEmpty ? entry.cleanTitleRu : entry.titleRu;
    if (titleToSearch.isEmpty) return;

    Future.microtask(() async {
      try {
        if (!mounted) return;
        if (getIt.isRegistered<CatalogRepository>()) {
          final repo = getIt<CatalogRepository>();
          final results = await repo.searchTitles(titleToSearch, limit: 3);
          if (results.isNotEmpty && mounted) {
            final best = results.first;
            final resolved = best.posterMedium.isNotEmpty
                ? best.posterMedium
                : (best.posterOriginal.isNotEmpty
                    ? best.posterOriginal
                    : best.posterSmall);
            if (resolved.isNotEmpty) {
              context.read<AnimeListCubit>().updatePosterUrl(entry.animeId, resolved);
            }
          }
        }
      } catch (_) {}
    });
  }

  /// Виджет постера: ShimmerPlaceholder вместо сломанных иконок документов
  Widget _buildPosterImage({
    required UserAnimeEntry entry,
    double? width,
    double? height,
    BorderRadius? borderRadius,
  }) {
    final posterUrl = _resolvePosterUrl(entry);
    final br = borderRadius ?? BorderRadius.circular(12);
    final hasValidUrl = posterUrl.isNotEmpty &&
        !posterUrl.contains('placeholder') &&
        posterUrl.startsWith('http');

    if (!hasValidUrl) {
      _triggerPosterFetch(entry);
      return ShimmerPlaceholder(
        width: width ?? double.infinity,
        height: height ?? double.infinity,
        borderRadius: br,
      );
    }

    return CachedNetworkImage(
      imageUrl: posterUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      placeholder: (_, __) => ShimmerPlaceholder(
        width: width ?? double.infinity,
        height: height ?? double.infinity,
        borderRadius: br,
      ),
      errorWidget: (_, __, ___) {
        _triggerPosterFetch(entry);
        return ShimmerPlaceholder(
          width: width ?? double.infinity,
          height: height ?? double.infinity,
          borderRadius: br,
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- МАССОВОЕ УПРАВЛЕНИЕ (BATCH EDIT) ---
  void _handleItemLongPress(UserAnimeEntry entry) {
    HapticFeedback.mediumImpact();
    setState(() {
      if (!_isSelectionMode) {
        _isSelectionMode = true;
        _selectedAnimeIds.add(entry.animeId);
      } else {
        _toggleSelection(entry.animeId);
      }
    });
  }

  void _handleItemTap(BuildContext context, UserAnimeEntry entry) {
    if (_isSelectionMode) {
      HapticFeedback.selectionClick();
      setState(() {
        _toggleSelection(entry.animeId);
      });
    } else {
      _openDetailsForEntry(context, entry);
    }
  }

  void _toggleSelection(int animeId) {
    if (_selectedAnimeIds.contains(animeId)) {
      _selectedAnimeIds.remove(animeId);
      if (_selectedAnimeIds.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedAnimeIds.add(animeId);
    }
  }

  void _exitSelectionMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _isSelectionMode = false;
      _selectedAnimeIds.clear();
    });
  }

  void _toggleSelectAll(List<UserAnimeEntry> currentEntries) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedAnimeIds.length == currentEntries.length) {
        _selectedAnimeIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedAnimeIds.clear();
        _selectedAnimeIds.addAll(currentEntries.map((e) => e.animeId));
      }
    });
  }

  Widget _buildSelectionIndicator(int animeId) {
    final isSelected = _selectedAnimeIds.contains(animeId);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? AppColors.primary : Colors.black.withValues(alpha: 0.6),
        border: Border.all(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.8),
          width: 2,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
          : null,
    );
  }

  Widget _buildBatchEditBar(BuildContext context, List<UserAnimeEntry> currentEntries) {
    final count = _selectedAnimeIds.length;
    final allSelected = currentEntries.isNotEmpty && count == currentEntries.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: GlassContainer(
          borderRadius: BorderRadius.circular(20),
          blurSigma: 20,
          backgroundOpacity: 0.18,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 22),
                tooltip: 'Отмена',
                onPressed: _exitSelectionMode,
              ),
              const SizedBox(width: 4),
              Text(
                'Выбрано: $count',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: Icon(
                  allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                  size: 18,
                ),
                label: Text(
                  allSelected ? 'Снять' : 'Все',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                onPressed: () => _toggleSelectAll(currentEntries),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.drive_file_move_outlined, color: AppColors.primaryLight, size: 22),
                tooltip: 'Перенести',
                onPressed: count == 0 ? null : () => _showBatchMoveSheet(context),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.syncError, size: 22),
                tooltip: 'Удалить',
                onPressed: count == 0 ? null : () => _confirmBatchDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBatchMoveSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.strokeMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Перенести ${_selectedAnimeIds.length} тайтлов в:',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...AnimeListStatus.values.map((status) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(status.icon, color: status.color, size: 18),
                  ),
                  title: Text(
                    status.labelRu,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
                  onTap: () async {
                    final ids = _selectedAnimeIds.toList();
                    Navigator.pop(ctx);
                    await context.read<AnimeListCubit>().batchChangeStatus(ids, status);
                    _exitSelectionMode();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Перенесено ${ids.length} тайтлов в «${status.labelRu}»'),
                          backgroundColor: AppColors.syncActive,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmBatchDelete(BuildContext context) {
    HapticFeedback.lightImpact();
    final count = _selectedAnimeIds.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Удалить $count тайтлов?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text(
          'Выбранные тайтлы будут удалены из всех ваших списков. Это действие нельзя отменить.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.syncError,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final ids = _selectedAnimeIds.toList();
              Navigator.pop(ctx);
              await context.read<AnimeListCubit>().batchDelete(ids);
              _exitSelectionMode();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Удалено тайтлов: ${ids.length}'),
                    backgroundColor: AppColors.syncError,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Удалить', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showChangeStatusSheet(BuildContext context, UserAnimeEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.strokeMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                entry.cleanTitleRu,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              ...AnimeListStatus.values.map((status) {
                final isSelected = entry.status == status;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(status.icon, color: status.color, size: 18),
                  ),
                  title: Text(
                    status.labelRu,
                    style: TextStyle(
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                      : null,
                  onTap: () {
                    context.read<AnimeListCubit>().setAnimeStatus(
                          animeId: entry.animeId,
                          titleRu: entry.titleRu,
                          posterUrl: entry.posterUrl,
                          status: status,
                          lastEpisode: entry.lastEpisode,
                          episodesTotal: entry.episodesTotal,
                        );
                    Navigator.pop(ctx);
                  },
                );
              }),
              const Divider(color: AppColors.strokeMedium),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.syncError, size: 22),
                title: const Text(
                  'Удалить из закладок',
                  style: TextStyle(color: AppColors.syncError, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  context.read<AnimeListCubit>().removeAnime(entry.animeId);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetailsForEntry(BuildContext context, UserAnimeEntry entry) {
    try {
      final catalogState = context.read<CatalogCubit>().state;
      AnimeTitle? matched;
      final clean = entry.cleanTitleRu.toLowerCase().trim();
      if (catalogState is CatalogLoaded) {
        try {
          matched = catalogState.titles.firstWhere(
            (t) =>
                t.id == entry.animeId ||
                t.russianTitle.toLowerCase().trim() == clean ||
                (t.englishTitle.isNotEmpty &&
                    t.englishTitle.toLowerCase().trim() == clean),
          );
        } catch (_) {}
      }

      final poster = _resolvePosterUrl(entry);
      final targetTitle = matched ??
          AnimeTitle(
            id: entry.animeId,
            code: 'search:${entry.cleanTitleRu}',
            russianTitle: entry.cleanTitleRu,
            englishTitle: entry.cleanTitleRu,
            posterSmall: poster,
            posterMedium: poster,
            posterOriginal: poster,
            genres: const [],
            description: '',
            status: entry.status.labelRu,
            episodesTotal: entry.episodesTotal,
          );

      if (widget.onTitleSelected != null) {
        widget.onTitleSelected!(targetTitle);
      } else {
        context.pushNamed('details', extra: targetTitle);
      }
    } catch (_) {}
  }

  void _openPlayerForDownload(BuildContext context, DownloadTask dl) {
    final targetTitle = AnimeTitle(
      id: dl.titleId,
      code: 'title_${dl.titleId}',
      russianTitle: dl.titleName,
      englishTitle: dl.titleName,
      posterSmall: dl.posterUrl,
      posterMedium: dl.posterUrl,
      posterOriginal: dl.posterUrl,
      genres: const [],
      description: '',
      status: 'Офлайн',
    );
    final ep = EpisodeItem(
      episode: dl.episode,
      name: dl.episodeName,
      fhdUrl: dl.localPath,
      hdUrl: dl.localPath,
      sdUrl: dl.localPath,
    );
    context.pushNamed('player', extra: {
      'title': targetTitle,
      'episode': ep,
      'quality': PlayerQuality.fhd,
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AnimeListCubit, AnimeListState>(
      builder: (context, listState) {
        final activeTab = listState.selectedTab;
        var entries = List<UserAnimeEntry>.from(listState.entriesFor(activeTab));

        if (_searchQuery.isNotEmpty) {
          entries = entries
              .where((e) =>
                  e.cleanTitleRu.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                  e.titleRu.toLowerCase().contains(_searchQuery.toLowerCase()))
              .toList();
        }

        // Упорядочивание списка по выбранному критерию
        switch (_sortBy) {
          case SavedAnimeSort.dateAdded:
            entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            break;
          case SavedAnimeSort.alphabetical:
            entries.sort((a, b) => a.cleanTitleRu.toLowerCase().compareTo(b.cleanTitleRu.toLowerCase()));
            break;
          case SavedAnimeSort.progress:
            entries.sort((a, b) => b.lastEpisode.compareTo(a.lastEpisode));
            break;
        }

        return PopScope(
          canPop: !_isSelectionMode,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _isSelectionMode) {
              _exitSelectionMode();
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            bottomNavigationBar: _isSelectionMode
                ? _buildBatchEditBar(context, entries)
                : null,
            body: SafeArea(
              bottom: false,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ЗАГОЛОВОК: «Мои списки & Закладки»
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppDimensions.spacingXl,
                        AppDimensions.spacingLg,
                        AppDimensions.spacingXl,
                        AppDimensions.spacingSm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.bookmark_rounded, color: AppColors.primaryLight, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Мои списки',
                                  style: AppTypography.displayMedium.copyWith(
                                    fontSize: 22,
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Все сохраненные тайтлы и планы просмотра',
                                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),

                          // Переключатель вида: Список / Сетка / Карточки
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.strokeMedium),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildViewModeButton(SavedAnimeViewMode.list, Icons.view_list_rounded),
                                _buildViewModeButton(SavedAnimeViewMode.grid, Icons.grid_view_rounded),
                                _buildViewModeButton(SavedAnimeViewMode.card, Icons.view_agenda_rounded),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // БЛОК 1 В СТИЛЕ ЖИДКОГО СТЕКЛА: «Продолжить просмотр» из WatchHistory
                  // (Без громоздкой кнопки «Смотреть», вся карточка кликабельна с аккуратным шевроном)
                  BlocBuilder<WatchHistoryCubit, WatchHistoryState>(
                    builder: (context, historyState) {
                      final recent = historyState.lastWatched;
                      if (recent == null) return const SliverToBoxAdapter(child: SizedBox.shrink());

                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppDimensions.spacingXl,
                            0,
                            AppDimensions.spacingXl,
                            14,
                          ),
                          child: GlassContainer(
                            borderRadius: BorderRadius.circular(20),
                            blurSigma: 16,
                            backgroundOpacity: 0.08,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            onTap: () {
                              final entry = listState.getEntryFor(recent.titleId);
                              if (entry != null) {
                                _openDetailsForEntry(context, entry);
                              }
                            },
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.play_circle_fill_rounded, color: AppColors.primaryLight, size: 28),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'ПРОДОЛЖИТЬ ПРОСМОТР',
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.primaryLight,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        recent.titleName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.titleSmall.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        'Серия ${recent.episode} • ${recent.formattedPosition} / ${recent.formattedDuration}',
                                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 22),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // БЛОК ОФЛАЙН-ЗАГРУЗОК (DOWNLOAD MANAGER В СТИЛЕ ЖИДКОГО СТЕКЛА)
                  if (getIt.isRegistered<DownloadCubit>())
                    BlocBuilder<DownloadCubit, DownloadState>(
                      bloc: getIt<DownloadCubit>(),
                      builder: (context, dlState) {
                        if (dlState.completedTasks.isEmpty && dlState.activeTasks.isEmpty) {
                          return const SliverToBoxAdapter(child: SizedBox.shrink());
                        }

                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppDimensions.spacingXl,
                              0,
                              AppDimensions.spacingXl,
                              AppDimensions.spacingMd,
                            ),
                            child: GlassContainer(
                              borderRadius: BorderRadius.circular(16),
                              blurSigma: 16,
                              backgroundOpacity: 0.08,
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.offline_pin_rounded,
                                        color: AppColors.accentSecondary,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Скачано офлайн',
                                        style: AppTypography.titleSmall.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${dlState.totalDownloadedCount} серий • ${dlState.formattedTotalBytesUsed}',
                                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 64,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: dlState.completedTasks.length,
                                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                                      itemBuilder: (context, i) {
                                        final item = dlState.completedTasks[i];
                                        return TvFocusable(
                                          borderRadius: BorderRadius.circular(10),
                                          scaleFactor: 1.05,
                                          onPressed: () => _openPlayerForDownload(context, item),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.05),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.white.withValues(alpha: 0.1),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(6),
                                                  child: Container(
                                                    width: 36,
                                                    height: 48,
                                                    color: AppColors.surfaceElevated,
                                                    child: item.posterUrl.isNotEmpty
                                                        ? Image.network(
                                                            item.posterUrl,
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (_, __, ___) => const Icon(Icons.movie, size: 16),
                                                          )
                                                        : const Icon(Icons.movie, size: 16),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      item.titleName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: AppColors.textPrimary,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    Text(
                                                      'Серия ${item.episode} • ${item.quality}',
                                                      style: const TextStyle(
                                                        color: AppColors.textSecondary,
                                                        fontSize: 10.5,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(width: 6),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textMuted),
                                                  onPressed: () {
                                                    getIt<DownloadCubit>().deleteDownload(item.id);
                                                  },
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
                        );
                      },
                    ),

                  // СТРОКА ПОИСКА ПО ЗАКЛАДКАМ В СТИЛЕ ЖИДКОГО СТЕКЛА И КНОПКА СОРТИРОВКИ
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                      child: Row(
                        children: [
                          Expanded(
                            child: GlassContainer(
                              borderRadius: BorderRadius.circular(14),
                              blurSigma: 12,
                              backgroundOpacity: 0.05,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(color: AppColors.textPrimary),
                                decoration: InputDecoration(
                                  hintText: 'Поиск по сохраненным тайтлам...',
                                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
                                  icon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                                  border: InputBorder.none,
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted, size: 18),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                ),
                                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GlassIconButton(
                            icon: Icons.sort_rounded,
                            tooltip: 'Сортировка списка',
                            size: 46,
                            iconSize: 22,
                            iconColor: _sortBy != SavedAnimeSort.dateAdded
                                ? AppColors.primaryLight
                                : AppColors.textSecondary,
                            onTap: () => _showSortSheet(context),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 14)),

                  // СЕЛЕКТОР КАТЕГОРИЙ В СТИЛЕ ЖИДКОГО СТЕКЛА: «Смотрю», «В планах», «Просмотрено»...
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 40,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: AnimeListStatus.values.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, idx) {
                          final status = AnimeListStatus.values[idx];
                          final isSelected = status == activeTab;
                          final count = listState.countFor(status);

                          return GestureDetector(
                            onTap: () => context.read<AnimeListCubit>().selectTab(status),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.surfaceElevated.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.strokeMedium,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    status.icon,
                                    size: 15,
                                    color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    status.labelRu,
                                    style: TextStyle(
                                      color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  if (count > 0) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.black.withValues(alpha: 0.25)
                                            : AppColors.surface,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$count',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected ? Colors.white : AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 14)),

                  // СПИСОК ТАЙТЛОВ
                  if (entries.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl, vertical: 48),
                        child: Center(
                          child: Column(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.strokeMedium),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  activeTab.icon,
                                  size: 30,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'По запросу «$_searchQuery» ничего не найдено'
                                    : 'В списке «${activeTab.labelRu}» пока пусто',
                                style: AppTypography.titleMedium.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Добавляйте понравившиеся тайтлы из каталога или импортируйте свой профиль из Anixart',
                                textAlign: TextAlign.center,
                                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                              ),
                              if (widget.onGoToCatalog != null) ...[
                                const SizedBox(height: 18),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: AppColors.textPrimary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: widget.onGoToCatalog,
                                  child: const Text('Перейти в каталог', style: TextStyle(fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (_viewMode == SavedAnimeViewMode.grid)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.60,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final entry = entries[index];

                            return InkWell(
                              onTap: () => _handleItemTap(context, entry),
                              onLongPress: () => _isSelectionMode
                                  ? _handleItemTap(context, entry)
                                  : _handleItemLongPress(entry),
                              borderRadius: BorderRadius.circular(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: SizedBox(
                                            width: double.infinity,
                                            height: double.infinity,
                                            child: _buildPosterImage(
                                              entry: entry,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                        // Бейдж статуса
                                        if (!_isSelectionMode)
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.65),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: entry.status.color, width: 1.5),
                                              ),
                                              child: Icon(entry.status.icon, size: 10, color: entry.status.color),
                                            ),
                                          ),
                                        // Индикатор выбора в режиме массового управления
                                        if (_isSelectionMode)
                                          Positioned(
                                            top: 6,
                                            left: 6,
                                            child: _buildSelectionIndicator(entry.animeId),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    entry.cleanTitleRu,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          childCount: entries.length,
                        ),
                      ),
                    )
                  else if (_viewMode == SavedAnimeViewMode.card)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final entry = entries[index];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GlassContainer(
                                borderRadius: BorderRadius.circular(18),
                                blurSigma: 14,
                                backgroundOpacity: 0.08,
                                padding: const EdgeInsets.all(12),
                                onTap: () => _handleItemTap(context, entry),
                                child: Row(
                                  children: [
                                    if (_isSelectionMode) ...[
                                      _buildSelectionIndicator(entry.animeId),
                                      const SizedBox(width: 10),
                                    ],
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        width: 72,
                                        height: 100,
                                        child: _buildPosterImage(
                                          entry: entry,
                                          width: 72,
                                          height: 100,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.cleanTitleRu,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTypography.titleSmall.copyWith(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(entry.status.icon, size: 14, color: entry.status.color),
                                              const SizedBox(width: 6),
                                              Text(
                                                entry.status.labelRu,
                                                style: TextStyle(
                                                  color: entry.status.color,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (entry.episodesTotal != null) ...[
                                                const Text(' • ', style: TextStyle(color: AppColors.textMuted)),
                                                Text(
                                                  '${entry.lastEpisode} / ${entry.episodesTotal} эп.',
                                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!_isSelectionMode)
                                      IconButton(
                                        icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                                        onPressed: () => _showChangeStatusSheet(context, entry),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: entries.length,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final entry = entries[index];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: GlassContainer(
                                borderRadius: BorderRadius.circular(16),
                                blurSigma: 12,
                                backgroundOpacity: 0.06,
                                padding: const EdgeInsets.all(10),
                                onTap: () => _handleItemTap(context, entry),
                                child: Row(
                                  children: [
                                    if (_isSelectionMode) ...[
                                      _buildSelectionIndicator(entry.animeId),
                                      const SizedBox(width: 10),
                                    ],
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 52,
                                        height: 72,
                                        child: _buildPosterImage(
                                          entry: entry,
                                          width: 52,
                                          height: 72,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.cleanTitleRu,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTypography.titleSmall.copyWith(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                entry.status.icon,
                                                size: 13,
                                                color: entry.status.color,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                entry.status.labelRu,
                                                style: AppTypography.caption.copyWith(
                                                  color: AppColors.primaryLight,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                ),
                                              ),
                                              if (entry.episodesTotal != null) ...[
                                                const Text(' • ', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                                                Text(
                                                  'Серия ${entry.lastEpisode} из ${entry.episodesTotal}',
                                                  style: AppTypography.caption.copyWith(
                                                    color: AppColors.textSecondary,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!_isSelectionMode)
                                      IconButton(
                                        icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                                        onPressed: () => _showChangeStatusSheet(context, entry),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: entries.length,
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 90), // Отступ под парящий Glass Bottom Nav Bar
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildViewModeButton(SavedAnimeViewMode mode, IconData icon) {
    final isSelected = _viewMode == mode;
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _viewMode = mode);
      },
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isSelected ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}
