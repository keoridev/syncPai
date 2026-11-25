import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import '../../domain/entities/manga_bridge.dart';
import '../cubit/manga_read_history_cubit.dart';
import '../screens/manga_details_screen.dart';

/// Встроенный браузер манги и манхвы внутри каталога SyncPai.
class MangaCatalogView extends StatelessWidget {
  final String searchQuery;

  const MangaCatalogView({
    super.key,
    this.searchQuery = '',
  });

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
                padding: EdgeInsets.fromLTRB(horizontalPad, 2, horizontalPad, 8),
                child: Text(
                  'Продолжить чтение',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    return Material(
                      key: ValueKey('manga_continue_card_${entry.mangaId}'),
                      color: const Color(0xFF151923),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _resumeFromHistory(context, entry),
                        child: Container(
                          width: 268,
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: entry.coverUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: wrapCorsSafeUrl(entry.coverUrl),
                                        width: 50,
                                        height: 70,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        width: 50,
                                        height: 70,
                                        color: const Color(0xFF1A2030),
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
                                        color: Color(0xFF35D9D5),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Читать',
                                      style: TextStyle(
                                        color: Color(0xFFFF6B4A),
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
              const SizedBox(height: 12),
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

  Widget _buildLangPill({
    required Key key,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: isSelected
          ? const Color(0xFF35D9D5).withValues(alpha: 0.18)
          : const Color(0xFF151923),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF35D9D5) : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
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
        final russianOnly = loaded?.mangaRussianOnly ?? true;
        final isLoading = loaded?.isMangaLoading ?? false;
        final isLoadingMore = loaded?.isMangaLoadingMore ?? false;
        final items = loaded?.mangaItems ?? const <MangaDexManga>[];

        return SliverMainAxisGroup(
          slivers: [
            _buildContinueReadingStrip(context, horizontalPad),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 8),
                child: Row(
                  children: [
                    _buildLangPill(
                      key: const ValueKey('manga_lang_ru'),
                      label: 'Русский',
                      isSelected: russianOnly,
                      onTap: () => cubit.setMangaRussianOnly(true),
                    ),
                    const SizedBox(width: 8),
                    _buildLangPill(
                      key: const ValueKey('manga_lang_all'),
                      label: 'Все языки',
                      isSelected: !russianOnly,
                      onTap: () => cubit.setMangaRussianOnly(false),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                  itemCount: _tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tab = _tabs[index];
                    final isSelected = tab.id == activeTab;
                    return Material(
                      color: isSelected
                          ? const Color(0xFFFF6B4A)
                          : const Color(0xFF1A2030),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => cubit.selectMangaTab(tab.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Center(
                            child: Text(
                              tab.label,
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
                      activeTab == 'lists'
                          ? 'Вы ещё не начали читать мангу'
                          : 'Ничего не найдено',
                      style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: screenWidth >= 900 ? 210 : 170,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.56,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final manga = items[index];
                      final typeLabel = manga.originalLanguage == 'ko'
                          ? 'Манхва'
                          : (manga.originalLanguage == 'zh' ? 'Маньхуа' : 'Манга');
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _openManga(context, manga),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (manga.coverUrl.isNotEmpty)
                                        CachedNetworkImage(
                                          imageUrl: wrapCorsSafeUrl(manga.coverUrl),
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => Container(
                                            color: const Color(0xFF151923),
                                            child: const Icon(
                                              Icons.menu_book_rounded,
                                              color: AppColors.textMuted,
                                              size: 32,
                                            ),
                                          ),
                                        )
                                      else
                                        Container(
                                          color: const Color(0xFF151923),
                                          child: const Icon(
                                            Icons.menu_book_rounded,
                                            color: AppColors.textMuted,
                                            size: 32,
                                          ),
                                        ),
                                      Positioned(
                                        left: 8,
                                        top: 8,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.72),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                typeLabel,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: manga.hasRussianTranslation
                                                    ? const Color(0xFF35D9D5)
                                                        .withValues(alpha: 0.85)
                                                    : Colors.black.withValues(alpha: 0.72),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                manga.hasRussianTranslation ? 'RU' : 'EN',
                                                style: TextStyle(
                                                  color: manga.hasRussianTranslation
                                                      ? const Color(0xFF0A0D14)
                                                      : Colors.white70,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                manga.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
}
