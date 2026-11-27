import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../catalog/domain/entities/catalog_settings.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import '../../domain/entities/manga_bridge.dart';
import '../cubit/manga_read_history_cubit.dart';
import '../cubit/user_manga_list_cubit.dart';
import '../screens/manga_details_screen.dart';

/// Встроенный браузер манги и манхвы внутри каталога SyncPai (flat matte UI, без BoxShadow/неона).
class MangaCatalogView extends StatelessWidget {
  final String searchQuery;

  const MangaCatalogView({
    super.key,
    this.searchQuery = '',
  });

  static const Color _surfaceCard = Color(0xFF141821);
  static const Color _surfaceElevated = Color(0xFF1C212E);
  static const Color _tonalBorder = Color(0x14FFFFFF);
  static const Color _coralAccent = Color(0xFFFF6B4A);

  static const List<({String id, String label})> _tabs = [
    (id: 'all', label: 'Всё'),
    (id: 'manhwa', label: 'Манхва'),
    (id: 'manga', label: 'Манга'),
    (id: 'popular', label: 'Популярное'),
    (id: 'completed', label: 'Завершённые'),
  ];

  void _resumeFromHistory(BuildContext context, MangaHistoryEntry entry) {
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

  Widget _buildContinueReadingStrip(
    BuildContext context,
    double horizontalPad,
  ) {
    if (!getIt.isRegistered<MangaReadHistoryCubit>()) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return BlocBuilder<MangaReadHistoryCubit, MangaReadHistoryState>(
      bloc: getIt<MangaReadHistoryCubit>(),
      builder: (context, historyState) {
        if (historyState.entries.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        final items = historyState.entries.take(10).toList();
        return SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(horizontalPad, 4, horizontalPad, 8),
                child: Text(
                  'Продолжить чтение',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    return Material(
                      key: ValueKey('manga_continue_card_${entry.mangaId}'),
                      color: _surfaceCard,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _resumeFromHistory(context, entry),
                        child: Container(
                          width: 268,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _tonalBorder),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: entry.coverUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: wrapCorsSafeUrl(entry.coverUrl),
                                        httpHeaders: entry.coverUrl.contains('remanga')
                                            ? const {'Referer': 'https://remanga.org/'}
                                            : null,
                                        memCacheWidth: 360,
                                        width: 48,
                                        height: 68,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        width: 48,
                                        height: 68,
                                        color: _surfaceElevated,
                                        child: const Icon(
                                          Icons.menu_book_rounded,
                                          color: AppColors.textMuted,
                                          size: 20,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      entry.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${entry.chapterLabel} • Стр. ${entry.pageIndex}/${entry.totalPages}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Читать',
                                      style: TextStyle(
                                        color: _coralAccent,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _openManga(BuildContext context, MangaDexManga manga) {
    try {
      context.pushNamed(
        'manga_details',
        pathParameters: {'id': manga.id},
        extra: manga,
      );
    } catch (_) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MangaDetailsScreen(
            mangaId: manga.id,
            initialManga: manga,
          ),
        ),
      );
    }
  }

  String _formatLabel(MangaDexManga manga) {
    if (manga.originalLanguage == 'ko') return 'Манхва';
    if (manga.originalLanguage == 'zh') return 'Маньхуа';
    return 'Манга';
  }

  String _metaLine(MangaDexManga manga) {
    final parts = <String>[_formatLabel(manga)];
    if (manga.chaptersCount != null && manga.chaptersCount! > 0) {
      parts.add('${manga.chaptersCount} гл.');
    }
    if (manga.rating != null && manga.rating! > 0) {
      parts.add(manga.rating!.toStringAsFixed(1));
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPad = screenWidth >= 900 ? 20.0 : (screenWidth < 390 ? 12.0 : 14.0);

    return BlocBuilder<CatalogCubit, CatalogState>(
      builder: (context, state) {
        final cubit = context.read<CatalogCubit>();
        final loaded = state is CatalogLoaded ? state : null;
        final activeTab = loaded?.mangaTab ?? 'all';
        final isLoading = loaded?.isMangaLoading ?? false;
        final isLoadingMore = loaded?.isMangaLoadingMore ?? false;
        final items = loaded?.mangaItems ?? const <MangaDexManga>[];
        final isListMode = loaded?.viewMode == CatalogViewMode.list;
        final mobileCols = screenWidth < 390
            ? 2
            : (loaded?.gridDensity.mobileColumns ?? 2);

        final Map<String, MangaListStatus> listStatusById = {};
        if (getIt.isRegistered<UserMangaListCubit>()) {
          for (final entry in getIt<UserMangaListCubit>().state.entries) {
            listStatusById[entry.mangaId] = entry.status;
          }
        }

        return SliverMainAxisGroup(
          slivers: [
            _buildContinueReadingStrip(context, horizontalPad),
            // Чистая строка вкладок с 2.5px коралловым индикатором (как в каталоге Аниме)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                  itemCount: _tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 18),
                  itemBuilder: (context, index) {
                    final tab = _tabs[index];
                    final isSelected = tab.id == activeTab;
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => cubit.selectMangaTab(tab.id),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                            child: Text(
                              tab.label,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontSize: 13.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 2.5,
                            width: isSelected ? 28 : 0,
                            decoration: BoxDecoration(
                              color: _coralAccent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1, color: _tonalBorder)),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (isLoading && items.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                  child: Center(
                    child: Text(
                      'Ничего не найдено',
                      style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ),
              )
            else if (isListMode)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 20),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _buildListRow(
                    context,
                    items[index],
                    listStatusById[items[index].id],
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 16),
                sliver: SliverGrid(
                  gridDelegate: screenWidth >= 900
                      ? () {
                          final approxW = (screenWidth - 230 - horizontalPad * 2)
                              .clamp(360.0, 2400.0);
                          final cols = (approxW / 231).ceil().clamp(2, 8);
                          final cardW = ((approxW - 16 * (cols - 1)) / cols)
                              .clamp(150.0, 215.0);
                          return SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 215,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: cardW / (cardW * 1.5 + 68),
                          );
                        }()
                      : () {
                          final cols = screenWidth >= 600 ? 3 : mobileCols;
                          final spacing = mobileCols == 3 ? 8.0 : 12.0;
                          final cardW =
                              (screenWidth - horizontalPad * 2 - spacing * (cols - 1)) /
                                  cols;
                          return SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: mobileCols == 3 ? 12.0 : 14.0,
                            childAspectRatio: cardW / (cardW * 1.5 + 68),
                          );
                        }(),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildGridCard(
                      context,
                      items[index],
                      listStatusById[items[index].id],
                      isCompact: screenWidth < 600 && mobileCols == 3,
                    ),
                    childCount: items.length,
                  ),
                ),
              ),
              if (isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    MangaDexManga manga,
    MangaListStatus? listStatus, {
    bool isCompact = false,
  }) {
    final formatLabel = _formatLabel(manga);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openManga(context, manga),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox.expand(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _surfaceCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _tonalBorder),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (manga.coverUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: wrapCorsSafeUrl(manga.coverUrl),
                          httpHeaders: manga.coverUrl.contains('remanga')
                              ? const {'Referer': 'https://remanga.org/'}
                              : null,
                          memCacheWidth: 360,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const ColoredBox(
                            color: _surfaceCard,
                            child: Icon(
                              Icons.menu_book_rounded,
                              color: AppColors.textMuted,
                              size: 30,
                            ),
                          ),
                        )
                      else
                        const ColoredBox(
                          color: _surfaceCard,
                          child: Icon(
                            Icons.menu_book_rounded,
                            color: AppColors.textMuted,
                            size: 30,
                          ),
                        ),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            formatLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (listStatus != null)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _coralAccent.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              listStatus.labelRu,
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
            ),
            ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  manga.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: isCompact ? 11.5 : 13.0,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _metaLine(manga),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: isCompact ? 10.5 : 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListRow(
    BuildContext context,
    MangaDexManga manga,
    MangaListStatus? listStatus,
  ) {
    return Material(
      color: _surfaceCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openManga(context, manga),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _tonalBorder),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 76,
                  height: 108,
                  child: manga.coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: wrapCorsSafeUrl(manga.coverUrl),
                          httpHeaders: manga.coverUrl.contains('remanga')
                              ? const {'Referer': 'https://remanga.org/'}
                              : null,
                          memCacheWidth: 360,
                          fit: BoxFit.cover,
                        )
                      : const ColoredBox(
                          color: _surfaceElevated,
                          child: Icon(
                            Icons.menu_book_rounded,
                            color: AppColors.textMuted,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      manga.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (manga.originalTitle != null &&
                        manga.originalTitle!.trim().isNotEmpty &&
                        manga.originalTitle != manga.title) ...[
                      const SizedBox(height: 3),
                      Text(
                        manga.originalTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _metaLine(manga),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (listStatus != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _coralAccent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          listStatus.labelRu,
                          style: const TextStyle(
                            color: _coralAccent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Читать',
                  style: TextStyle(
                    color: _coralAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
