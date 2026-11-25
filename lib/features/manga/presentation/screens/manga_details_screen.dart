import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/services/mascot_companion_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../data/datasources/mangadex_datasource.dart';
import '../../data/repositories/manga_progress_repository.dart';
import '../../domain/entities/manga_bridge.dart';
import '../cubit/manga_read_history_cubit.dart';
import '../cubit/user_manga_list_cubit.dart';

/// Экран деталей манги/манхвы со списком глав и быстрым переходом к чтению.
class MangaDetailsScreen extends StatefulWidget {
  final String mangaId;
  final MangaDexManga? initialManga;

  const MangaDetailsScreen({
    super.key,
    required this.mangaId,
    this.initialManga,
  });

  @override
  State<MangaDetailsScreen> createState() => _MangaDetailsScreenState();
}

class _MangaDetailsScreenState extends State<MangaDetailsScreen> {
  MangaDexManga? _manga;
  List<MangaDexChapter> _chapters = const [];
  MangaReadingProgress? _savedProgress;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _manga = widget.initialManga;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MascotCompanionService.instance.setMangaContext(true);
    });
    _loadData();
  }

  @override
  void dispose() {
    final nextMangaContext =
        getIt.isRegistered<CatalogCubit>() ? getIt<CatalogCubit>().isMangaMode : false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MascotCompanionService.instance.setMangaContext(nextMangaContext);
    });
    super.dispose();
  }

  Future<void> _loadData() async {
    final ds = getIt.isRegistered<MangaDexDataSource>()
        ? getIt<MangaDexDataSource>()
        : MangaDexDataSource();
    final progressRepo = getIt.isRegistered<MangaProgressRepository>()
        ? getIt<MangaProgressRepository>()
        : null;

    final loadedManga = _manga ?? await ds.getMangaById(widget.mangaId);
    final results = await Future.wait([
      ds.getChapters(
        widget.mangaId,
        title: loadedManga?.title,
        originalTitle: loadedManga?.originalTitle,
      ),
      if (progressRepo != null)
        progressRepo.getProgress(widget.mangaId)
      else
        Future.value(null),
    ]);

    if (!mounted) return;
    setState(() {
      _manga = loadedManga ?? _manga;
      _chapters = results[0] as List<MangaDexChapter>;
      _savedProgress = results[1] as MangaReadingProgress?;
      _isLoading = false;
    });
  }

  IconData _statusIcon(MangaListStatus status) {
    switch (status) {
      case MangaListStatus.reading:
        return Icons.auto_stories_rounded;
      case MangaListStatus.planned:
        return Icons.bookmark_outline_rounded;
      case MangaListStatus.completed:
        return Icons.check_circle_outline_rounded;
      case MangaListStatus.dropped:
        return Icons.pause_circle_outline_rounded;
    }
  }

  Color _statusColor(MangaListStatus status) {
    switch (status) {
      case MangaListStatus.reading:
        return const Color(0xFF35D9D5);
      case MangaListStatus.planned:
        return const Color(0xFFFF9F43);
      case MangaListStatus.completed:
        return const Color(0xFF2ED573);
      case MangaListStatus.dropped:
        return const Color(0xFFFF6B6B);
    }
  }

  void _showMangaStatusSheet(
    BuildContext context,
    MangaDexManga? manga,
    UserMangaEntry? currentEntry,
  ) {
    final cubit = getIt<UserMangaListCubit>();
    final title = manga?.title.isNotEmpty == true ? manga!.title : 'Манга';
    final coverUrl = manga?.coverUrl ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
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
                    'Добавить в список',
                    style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  ...MangaListStatus.values.map((status) {
                    final isSelected = currentEntry?.status == status;
                    final color = _statusColor(status);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(_statusIcon(status), color: color, size: 18),
                      ),
                      title: Text(
                        status.labelRu,
                        style: TextStyle(
                          color: isSelected ? AppColors.primary : AppColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                          : null,
                      onTap: () {
                        cubit.setStatus(
                          mangaId: widget.mangaId,
                          mangaTitle: title,
                          coverUrl: coverUrl,
                          status: status,
                          lastReadChapter: _savedProgress?.chapterNumber ?? '1',
                          lastReadPage: _savedProgress?.pageIndex ?? 0,
                          chaptersCount: _chapters.isNotEmpty ? _chapters.length : null,
                        );
                        Navigator.pop(sheetContext);
                      },
                    );
                  }),
                  if (currentEntry != null) ...[
                    const Divider(color: AppColors.strokeMedium),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.syncError,
                        size: 22,
                      ),
                      title: const Text(
                        'Удалить из списков',
                        style: TextStyle(
                          color: AppColors.syncError,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        cubit.removeEntry(widget.mangaId);
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openChapter(MangaDexChapter chapter, {int? initialPage}) {
    final manga = _manga ??
        MangaDexManga(
          id: widget.mangaId,
          title: 'Манга',
          coverUrl: '',
        );
    final formatLabel = manga.originalLanguage == 'ko'
        ? 'Манхва'
        : (manga.originalLanguage == 'zh' ? 'Маньхуа' : 'Манга');
    final bridge = AnimeMangaBridge(
      anilibriaId: 0,
      mangaDexId: manga.id,
      mangaTitle: manga.title,
      coverUrl: manga.coverUrl,
      isManhwa: manga.originalLanguage == 'ko',
      chaptersCount: _chapters.length,
    );
    context.pushNamed(
      'manga_reader_chapter',
      pathParameters: {'chapterId': chapter.id},
      extra: {
        'bridge': bridge,
        'initialChapter': chapter.chapterNumber?.floor(),
        'initialPage': initialPage,
        'formatLabel': formatLabel,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final manga = _manga;
    final langLabel = manga?.originalLanguage == 'ko'
        ? 'Манхва'
        : (manga?.originalLanguage == 'zh' ? 'Маньхуа' : 'Манга');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          manga?.title ?? 'Загрузка...',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 112,
                            height: 162,
                            child: (manga?.coverUrl.isNotEmpty ?? false)
                                ? CachedNetworkImage(
                                    imageUrl: wrapCorsSafeUrl(manga!.coverUrl),
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const ColoredBox(
                                      color: Color(0xFF1A2030),
                                      child: Icon(Icons.menu_book_rounded, color: Colors.white38, size: 32),
                                    ),
                                  )
                                : const ColoredBox(
                                    color: Color(0xFF1A2030),
                                    child: Icon(Icons.menu_book_rounded, color: Colors.white38, size: 32),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A2030),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  langLabel,
                                  style: const TextStyle(
                                    color: Color(0xFF35D9D5),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                manga?.title ?? 'Манга',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.titleLarge.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_chapters.length} гл.',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (_chapters.isNotEmpty)
                                    Builder(
                                      builder: (context) {
                                        Widget buildCta(MangaHistoryEntry? historyEntry) {
                                          final ctaLabel = historyEntry != null
                                              ? 'Продолжить • ${historyEntry.chapterLabel} (стр. ${historyEntry.pageIndex})'
                                              : (_savedProgress != null
                                                  ? 'Продолжить (гл. ${_savedProgress!.chapterNumber})'
                                                  : 'Читать с 1 главы');
                                          return SizedBox(
                                            height: 44,
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFFFF6B4A),
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                              icon: const Icon(Icons.menu_book_rounded, size: 18),
                                              label: Text(
                                                ctaLabel,
                                                style: const TextStyle(fontWeight: FontWeight.w700),
                                              ),
                                              onPressed: () {
                                                if (historyEntry != null) {
                                                  final target = _chapters.firstWhere(
                                                    (c) => c.id == historyEntry.chapterId,
                                                    orElse: () => _chapters.first,
                                                  );
                                                  _openChapter(
                                                    target,
                                                    initialPage: historyEntry.pageIndex,
                                                  );
                                                  return;
                                                }
                                                final savedNum = _savedProgress != null
                                                    ? int.tryParse(_savedProgress!.chapterNumber)
                                                    : null;
                                                final target = savedNum != null
                                                    ? _chapters.firstWhere(
                                                        (c) =>
                                                            c.chapterNumber?.floor() ==
                                                            savedNum,
                                                        orElse: () => _chapters.first,
                                                      )
                                                    : _chapters.first;
                                                _openChapter(
                                                  target,
                                                  initialPage: _savedProgress != null
                                                      ? _savedProgress!.pageIndex + 1
                                                      : null,
                                                );
                                              },
                                            ),
                                          );
                                        }

                                        if (!getIt.isRegistered<MangaReadHistoryCubit>()) {
                                          return buildCta(null);
                                        }
                                        return BlocBuilder<MangaReadHistoryCubit,
                                            MangaReadHistoryState>(
                                          bloc: getIt<MangaReadHistoryCubit>(),
                                          builder: (context, historyState) =>
                                              buildCta(historyState.getEntryFor(widget.mangaId)),
                                        );
                                      },
                                    ),
                                  if (getIt.isRegistered<UserMangaListCubit>())
                                    BlocBuilder<UserMangaListCubit, UserMangaListState>(
                                      bloc: getIt<UserMangaListCubit>(),
                                      builder: (context, listState) {
                                        final entry = listState.getEntryFor(widget.mangaId);
                                        final isInList = entry != null;
                                        return Material(
                                          key: const ValueKey('manga_details_list_status_btn'),
                                          color: isInList
                                              ? AppColors.primary.withValues(alpha: 0.18)
                                              : const Color(0xFF1A2030),
                                          borderRadius: BorderRadius.circular(12),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () => _showMangaStatusSheet(
                                              context,
                                              manga,
                                              entry,
                                            ),
                                            child: Container(
                                              height: 44,
                                              padding: const EdgeInsets.symmetric(horizontal: 14),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    isInList
                                                        ? Icons.bookmark_rounded
                                                        : Icons.bookmark_add_outlined,
                                                    size: 18,
                                                    color: isInList
                                                        ? AppColors.primaryLight
                                                        : AppColors.textPrimary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    isInList ? entry.status.labelRu : 'В списки',
                                                    style: TextStyle(
                                                      color: isInList
                                                          ? AppColors.primaryLight
                                                          : AppColors.textPrimary,
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'Главы',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (_chapters.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151923),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.menu_book_outlined,
                              color: AppColors.textMuted,
                              size: 36,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Главы недоступны на MangaDex из-за ограничений правообладателя',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E2536),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                final encoded = Uri.encodeComponent(manga?.title ?? '');
                                launchUrl(
                                  Uri.parse('https://shikimori.io/mangas?search=$encoded'),
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                              icon: const Icon(Icons.open_in_new_rounded, size: 17),
                              label: const Text('Открыть на Shikimori'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: _chapters.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final ch = _chapters[index];
                        final savedNum = _savedProgress != null
                            ? int.tryParse(_savedProgress!.chapterNumber)
                            : null;
                        final isLastRead = savedNum != null &&
                            ch.chapterNumber?.floor() == savedNum;
                        return Material(
                          color: isLastRead
                              ? const Color(0xFFFF6B4A).withValues(alpha: 0.16)
                              : const Color(0xFF161A24),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openChapter(ch),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ch.displayTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isLastRead
                                                ? const Color(0xFFFF6B4A)
                                                : Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          ch.secondaryMeta,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isLastRead) ...[
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF2ED573),
                                      size: 16,
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: ch.translatedLanguage == 'ru'
                                          ? const Color(0xFF35D9D5).withValues(alpha: 0.18)
                                          : Colors.white.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${ch.translatedLanguage.toUpperCase()} • ${ch.source}',
                                      style: TextStyle(
                                        color: ch.translatedLanguage == 'ru'
                                            ? const Color(0xFF35D9D5)
                                            : AppColors.textSecondary,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
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
              ],
            ),
    );
  }
}
