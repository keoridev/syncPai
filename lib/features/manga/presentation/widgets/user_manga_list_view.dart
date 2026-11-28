import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/safe_anime_poster.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../main/presentation/screens/main_screen.dart';
import '../../domain/entities/manga_bridge.dart';
import '../cubit/manga_read_history_cubit.dart';
import '../cubit/user_manga_list_cubit.dart';

/// Вкладка «Манга» внутри единого экрана «Мои списки & Закладки».
class UserMangaListView extends StatefulWidget {
  final bool isGridView;
  final int gridColumns;

  const UserMangaListView({
    super.key,
    this.isGridView = true,
    this.gridColumns = 3,
  });

  @override
  State<UserMangaListView> createState() => _UserMangaListViewState();
}

class _UserMangaListViewState extends State<UserMangaListView> {
  bool _isHistorySelected = false;

  void _resumeHistoryEntry(BuildContext context, MangaHistoryEntry entry) {
    final chapterNum = int.tryParse(
      RegExp(r'\d+').firstMatch(entry.chapterLabel)?.group(0) ?? '',
    );
    final bridge = AnimeMangaBridge(
      anilibriaId: 0,
      mangaDexId: entry.mangaId,
      mangaTitle: entry.title,
      coverUrl: entry.coverUrl,
      isManhwa: entry.formatLabel == 'Манхва',
    );
    try {
      context.pushNamed(
        'manga_reader',
        extra: {
          'bridge': bridge,
          'initialChapter': chapterNum,
          'initialPage': entry.pageIndex,
          'formatLabel': entry.formatLabel,
        },
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!getIt.isRegistered<UserMangaListCubit>()) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text(
              'Списки манги недоступны',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
        ),
      );
    }

    final historyCubit = getIt.isRegistered<MangaReadHistoryCubit>()
        ? getIt<MangaReadHistoryCubit>()
        : null;

    if (historyCubit == null) {
      return _buildWithHistory(context, const <MangaHistoryEntry>[]);
    }

    return BlocBuilder<MangaReadHistoryCubit, MangaReadHistoryState>(
      bloc: historyCubit,
      builder: (context, historyState) =>
          _buildWithHistory(context, historyState.entries),
    );
  }

  Widget _buildWithHistory(
    BuildContext context,
    List<MangaHistoryEntry> historyEntries,
  ) {

    return BlocBuilder<UserMangaListCubit, UserMangaListState>(
      bloc: getIt<UserMangaListCubit>(),
      builder: (context, state) {
        final items = state.entriesFor(state.selectedTab);
        final primary = Theme.of(context).colorScheme.primary;

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: MangaListStatus.values.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final isSelected = _isHistorySelected;
                      final count = historyEntries.length;
                      return Material(
                        key: const ValueKey('manga_list_tab_history'),
                        color: isSelected ? primary : const Color(0xFF1A2030),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => _isHistorySelected = true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Center(
                              child: Text(
                                count > 0 ? 'История ($count)' : 'История',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final status = MangaListStatus.values[index - 1];
                    final isSelected = !_isHistorySelected && status == state.selectedTab;
                    final count = state.entriesFor(status).length;
                    return Material(
                      key: ValueKey('manga_list_tab_${status.name}'),
                      color: isSelected ? primary : const Color(0xFF1A2030),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          if (_isHistorySelected) {
                            setState(() => _isHistorySelected = false);
                          }
                          getIt<UserMangaListCubit>().selectTab(status);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Center(
                            child: Text(
                              count > 0 ? '${status.labelRu} ($count)' : status.labelRu,
                              style: TextStyle(
                                color: isSelected ? Colors.white : AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 14)),
            if (_isHistorySelected) ...[
              if (historyEntries.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                    child: Center(
                      child: Text(
                        'История чтения пока пуста',
                        style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  sliver: SliverList.separated(
                    itemCount: historyEntries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = historyEntries[index];
                      return Material(
                        color: const Color(0xFF151923),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _resumeHistoryEntry(context, entry),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: entry.coverUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: wrapCorsSafeUrl(entry.coverUrl),
                                          width: 52,
                                          height: 74,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 52,
                                          height: 74,
                                          color: const Color(0xFF1A2030),
                                          child: const Icon(
                                            Icons.menu_book_rounded,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${entry.formatLabel} • ${entry.chapterLabel} • Стр. ${entry.pageIndex}/${entry.totalPages}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF35D9D5),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Color(0xFFFF6B4A),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ] else if (items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151923),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.auto_stories_rounded,
                                color: primary,
                                size: 26,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'В разделе «${state.selectedTab.labelRu}» пока пусто',
                              textAlign: TextAlign.center,
                              style: AppTypography.titleMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Добавляйте мангу и манхву в списки, чтобы отслеживать прогресс чтения.',
                              textAlign: TextAlign.center,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Material(
                              key: const ValueKey('manga_empty_go_catalog_btn'),
                              color: primary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  if (getIt.isRegistered<CatalogCubit>()) {
                                    getIt<CatalogCubit>().setMangaMode(true);
                                  } else {
                                    try {
                                      context.read<CatalogCubit>().setMangaMode(true);
                                    } catch (_) {}
                                  }
                                  if (!MainScreen.switchToTab(0)) {
                                    GoRouter.maybeOf(context)?.go('/');
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.explore_outlined,
                                        color: primary,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Перейти в каталог манги',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: primary,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else if (widget.isGridView)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverGrid(
                  gridDelegate: _buildGridDelegate(context),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final entry = items[index];
                      return _buildMangaGridCard(context, entry);
                    },
                    childCount: items.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    final chapterProgress = entry.chaptersCount != null
                        ? 'Глава ${entry.lastReadChapter} / ${entry.chaptersCount}'
                        : 'Глава ${entry.lastReadChapter}';

                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Material(
                        color: const Color(0xFF151923),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _openDetails(context, entry),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 54,
                                    height: 78,
                                    child: SafeAnimePoster(
                                      key: ValueKey(
                                        'manga_list_${entry.mangaId}_${entry.mangaTitle}',
                                      ),
                                      imageUrl: entry.coverUrl,
                                      title: entry.mangaTitle,
                                      borderRadius: 10,
                                      memCacheWidth: 160,
                                      monogramFontSize: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.mangaTitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        chapterProgress,
                                        style: const TextStyle(
                                          color: Color(0xFF35D9D5),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (entry.status == MangaListStatus.reading)
                                  ElevatedButton(
                                    key: ValueKey('manga_resume_${entry.mangaId}'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () => _openReader(context, entry),
                                    child: const Text(
                                      'Продолжить',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  SliverGridDelegate _buildGridDelegate(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    if (screenW >= 900) {
      final approxW = (screenW - 230 - 48).clamp(360.0, 2400.0);
      final cols = (approxW / 231).ceil().clamp(2, 8);
      final cardW = ((approxW - 16 * (cols - 1)) / cols).clamp(150.0, 215.0);
      return SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 215,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: cardW / (cardW * 1.5 + 68),
      );
    }
    final cols = widget.gridColumns.clamp(1, 4);
    if (cols == 1) {
      return const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1,
        childAspectRatio: 2.8,
        mainAxisSpacing: 8,
      );
    }
    final cardW = (screenW - 40 - 12.0 * (cols - 1)) / cols;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cols,
      childAspectRatio: cardW / (cardW * 1.5 + 68),
      crossAxisSpacing: 12.0,
      mainAxisSpacing: 12.0,
    );
  }

  Widget _buildMangaGridCard(BuildContext context, UserMangaEntry entry) {
    final progressPill = entry.chaptersCount != null
        ? 'Гл. ${entry.lastReadChapter} / ${entry.chaptersCount}'
        : 'Гл. ${entry.lastReadChapter}';
    final subtitle = '${entry.status.labelRu} • $progressPill';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openDetails(context, entry),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF161A22),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x18FFFFFF)),
                      ),
                      child: SafeAnimePoster(
                        key: ValueKey(
                          'manga_grid_${entry.mangaId}_${entry.mangaTitle}',
                        ),
                        imageUrl: entry.coverUrl,
                        title: entry.mangaTitle,
                        borderRadius: 13,
                        memCacheWidth: 360,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xE60D0F12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0x33FFFFFF)),
                        ),
                        child: Text(
                          progressPill,
                          style: const TextStyle(
                            color: Color(0xFFF8FAFC),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: Text(
                entry.mangaTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetails(BuildContext context, UserMangaEntry entry) {
    final effectiveId = entry.mangaId.trim().isNotEmpty
        ? entry.mangaId.trim()
        : entry.mangaTitle.trim();
    if (effectiveId.isEmpty) return;
    final initialManga = MangaDexManga(
      id: effectiveId,
      title: entry.mangaTitle,
      coverUrl: entry.coverUrl,
      chaptersCount: entry.chaptersCount,
      source: 'shikimori',
    );
    context.pushNamed(
      'manga_details',
      pathParameters: {'id': effectiveId},
      extra: initialManga,
    );
  }

  void _openReader(BuildContext context, UserMangaEntry entry) {
    if (entry.mangaId.trim().isEmpty) {
      _openDetails(context, entry);
      return;
    }
    final bridge = AnimeMangaBridge(
      anilibriaId: 0,
      mangaDexId: entry.mangaId,
      mangaTitle: entry.mangaTitle,
      coverUrl: entry.coverUrl,
      chaptersCount: entry.chaptersCount,
    );
    context.pushNamed(
      'manga_reader',
      extra: {
        'bridge': bridge,
        'initialChapter': double.tryParse(entry.lastReadChapter)?.floor() ?? 1,
      },
    );
  }
}

