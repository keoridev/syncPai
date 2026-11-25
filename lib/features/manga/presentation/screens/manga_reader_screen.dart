import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/services/mascot_companion_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../data/datasources/mangadex_datasource.dart';
import '../../data/repositories/manga_progress_repository.dart';
import '../../data/repositories/manga_repository.dart';
import '../../domain/entities/manga_bridge.dart';
import '../cubit/manga_read_history_cubit.dart';
import '../cubit/user_manga_list_cubit.dart';

enum MangaReadingMode { webtoon, paged }

/// Встроенная читалка манги и манхвы (MangaDex):
/// - Вертикальный Webtoon-режим (ListView.builder) и горизонтальный постраничный режим (PageView.builder)
/// - Упреждающее кэширование следующих 3 страниц (3-page lookahead precaching)
/// - Оверлей управления по тапу, выбор главы и сохранение прогресса чтения
class MangaReaderScreen extends StatefulWidget {
  final AnimeMangaBridge bridge;
  final int? initialChapter;
  /// 1-based initial page index when resuming from history.
  final int? initialPage;
  final String formatLabel;
  final MangaDexDataSource? dataSource;
  final MangaProgressRepository? progressRepository;

  const MangaReaderScreen({
    super.key,
    required this.bridge,
    this.initialChapter,
    this.initialPage,
    this.formatLabel = 'Манга',
    this.dataSource,
    this.progressRepository,
  });

  @override
  State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends State<MangaReaderScreen> {
  late final MangaDexDataSource _dataSource;
  late final MangaProgressRepository _progressRepo;

  late MangaReadingMode _readingMode;
  List<MangaDexChapter> _chapters = const [];
  int _currentChapterIndex = 0;
  List<String> _pages = const [];
  List<String> _dataSaverPages = const [];
  final Set<int> _useDataSaverIndices = {};
  final Map<int, int> _pageRetrySeeds = {};
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(0);
  bool _isLoadingChapters = true;
  bool _isLoadingPages = false;
  bool _showOverlay = true;
  String? _errorMessage;

  final ScrollController _webtoonScrollController = ScrollController();
  PageController _pageController = PageController();
  final Set<String> _precachedUrls = {};
  final Map<int, Timer> _pageTimeoutTimers = {};
  int? _notifiedFinishedChapterIdx;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ??
        (getIt.isRegistered<MangaDexDataSource>()
            ? getIt<MangaDexDataSource>()
            : MangaDexDataSource());
    _progressRepo = widget.progressRepository ??
        (getIt.isRegistered<MangaProgressRepository>()
            ? getIt<MangaProgressRepository>()
            : MangaProgressRepository());
    _readingMode = MangaReadingMode.webtoon;
    _webtoonScrollController.addListener(_onWebtoonScroll);
    CatalogCubit.pushForegroundScreen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MascotCompanionService.instance.setMangaContext(true);
      MascotCompanionService.instance.maybeShowLateNightMangaTip();
      if (widget.bridge.continueFromChapter != null) {
        MascotCompanionService.instance.notifyMangaBridgeResumed(
          'главы ${widget.bridge.continueFromChapter}',
        );
      }
    });
    _initReader();
  }

  @override
  void dispose() {
    for (final timer in _pageTimeoutTimers.values) {
      timer.cancel();
    }
    _pageTimeoutTimers.clear();
    _saveCurrentProgress();
    CatalogCubit.popForegroundScreen();
    final nextMangaContext =
        getIt.isRegistered<CatalogCubit>() ? getIt<CatalogCubit>().isMangaMode : false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MascotCompanionService.instance.setMangaContext(nextMangaContext);
    });
    _webtoonScrollController.removeListener(_onWebtoonScroll);
    _webtoonScrollController.dispose();
    _pageController.dispose();
    _currentPageNotifier.dispose();
    super.dispose();
  }

  void _onWebtoonScroll() {
    if (_readingMode != MangaReadingMode.webtoon ||
        _pages.isEmpty ||
        !_webtoonScrollController.hasClients) {
      return;
    }
    final pos = _webtoonScrollController.position;
    final maxExtent = pos.maxScrollExtent;
    if (maxExtent <= 0) return;
    final ratio = (pos.pixels / maxExtent).clamp(0.0, 1.0);
    final estimatedIndex =
        (ratio * (_pages.length - 1)).round().clamp(0, _pages.length - 1);
    if (estimatedIndex != _currentPageNotifier.value) {
      _onPageChanged(estimatedIndex);
    }
  }

  Future<void> _initReader() async {
    setState(() {
      _isLoadingChapters = true;
      _errorMessage = null;
    });

    final repo = getIt.isRegistered<MangaRepository>()
        ? getIt<MangaRepository>()
        : MangaRepository.instance;
    final chapters = widget.dataSource != null
        ? await _dataSource.getChapters(
            widget.bridge.mangaDexId,
            title: widget.bridge.mangaTitle,
          )
        : await repo.getChapters(
            MangaDexManga(
              id: widget.bridge.mangaDexId,
              title: widget.bridge.mangaTitle,
              coverUrl: widget.bridge.coverUrl,
              originalLanguage: widget.bridge.isManhwa ? 'ko' : 'ja',
            ),
          );
    if (!mounted) return;

    if (chapters.isEmpty) {
      setState(() {
        _isLoadingChapters = false;
        _errorMessage = 'Главы для этого тайтла пока недоступны на MangaDex.';
      });
      return;
    }

    int targetIdx = 0;
    int initialPage = widget.initialPage != null
        ? (widget.initialPage! - 1).clamp(0, 9999)
        : 0;

    final targetChap = widget.initialChapter ?? widget.bridge.continueFromChapter;
    if (targetChap != null) {
      final foundIdx = chapters.indexWhere(
        (c) =>
            c.chapterNumber != null &&
            (c.chapterNumber! - targetChap).abs() < 0.01,
      );
      if (foundIdx >= 0) {
        targetIdx = foundIdx;
      } else {
        final nextHigher = chapters.indexWhere(
          (c) => (c.chapterNumber ?? 0) >= targetChap,
        );
        if (nextHigher >= 0) targetIdx = nextHigher;
      }
    } else {
      final saved = await _progressRepo.getProgress(widget.bridge.mangaDexId);
      if (saved != null) {
        final savedIdx = chapters.indexWhere(
          (c) => c.chapterLabel == saved.chapterNumber,
        );
        if (savedIdx >= 0) {
          targetIdx = savedIdx;
          if (widget.initialPage == null) {
            initialPage = saved.pageIndex;
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _currentChapterIndex = targetIdx;
      _isLoadingChapters = false;
    });

    await _loadChapterPages(targetIdx, initialPage: initialPage);
  }

  Future<void> _loadChapterPages(
    int chapterIndex, {
    int initialPage = 0,
  }) async {
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return;
    final chapter = _chapters[chapterIndex];

    for (final timer in _pageTimeoutTimers.values) {
      timer.cancel();
    }
    _pageTimeoutTimers.clear();
    setState(() {
      _currentChapterIndex = chapterIndex;
      _isLoadingPages = true;
      _errorMessage = null;
      _pages = const [];
      _dataSaverPages = const [];
      _useDataSaverIndices.clear();
      _pageRetrySeeds.clear();
      _currentPageNotifier.value = 0;
    });

    final repo = getIt.isRegistered<MangaRepository>()
        ? getIt<MangaRepository>()
        : MangaRepository.instance;
    final bundle = widget.dataSource != null
        ? await _dataSource.getChapterPagesWithFallback(chapter.id)
        : await repo.getChapterPagesWithFallback(chapter.id);
    if (!mounted) return;
    final pages = bundle.dataUrls.isNotEmpty ? bundle.dataUrls : bundle.dataSaverUrls;

    final safePage = pages.isEmpty
        ? 0
        : initialPage.clamp(0, pages.length - 1);

    _pageController.dispose();
    _pageController = PageController(initialPage: safePage);

    setState(() {
      _pages = pages;
      _dataSaverPages = bundle.dataSaverUrls;
      _isLoadingPages = false;
      if (pages.isEmpty) {
        _errorMessage = 'Не удалось загрузить страницы главы.';
      }
    });
    _currentPageNotifier.value = safePage;

    if (pages.isNotEmpty) {
      _precacheAhead(safePage);
      _saveCurrentProgress();
      if (_readingMode == MangaReadingMode.webtoon &&
          _webtoonScrollController.hasClients) {
        _webtoonScrollController.jumpTo(0);
      }
    }
  }

  void _precacheAhead(int fromIndex) {
    if (!mounted || _pages.isEmpty) return;
    for (int offset = 1; offset <= 2; offset++) {
      final target = fromIndex + offset;
      if (target >= _pages.length) break;
      final url = _pages[target];
      if (_precachedUrls.add(url)) {
        unawaited(
          precacheImage(CachedNetworkImageProvider(url), context)
              .catchError((_) {}),
        );
      }
    }
  }

  void _onPageChanged(int index) {
    if (_currentPageNotifier.value == index) return;
    _currentPageNotifier.value = index;
    _precacheAhead(index);
    _saveCurrentProgress();
    if (index >= 2 &&
        getIt.isRegistered<UserMangaListCubit>() &&
        _chapters.isNotEmpty &&
        _currentChapterIndex >= 0 &&
        _currentChapterIndex < _chapters.length) {
      final chapter = _chapters[_currentChapterIndex];
      unawaited(
        getIt<UserMangaListCubit>().recordAutoProgress(
          mangaId: widget.bridge.mangaDexId,
          mangaTitle: widget.bridge.mangaTitle,
          coverUrl: widget.bridge.coverUrl,
          chapterLabel: chapter.chapterLabel,
          pageIndex: index,
          chaptersCount: widget.bridge.chaptersCount ?? _chapters.length,
        ),
      );
    }
    if (_pages.length > 1 &&
        index == _pages.length - 1 &&
        _notifiedFinishedChapterIdx != _currentChapterIndex) {
      _notifiedFinishedChapterIdx = _currentChapterIndex;
      final hasNext = _currentChapterIndex + 1 < _chapters.length;
      MascotCompanionService.instance.notifyMangaChapterFinished(
        onNextChapter: hasNext
            ? () => _loadChapterPages(_currentChapterIndex + 1)
            : null,
      );
    }
  }

  void _saveCurrentProgress() {
    if (_chapters.isEmpty ||
        _currentChapterIndex < 0 ||
        _currentChapterIndex >= _chapters.length) {
      return;
    }
    final chapter = _chapters[_currentChapterIndex];
    unawaited(
      _progressRepo.saveProgress(
        mangaId: widget.bridge.mangaDexId,
        mangaTitle: widget.bridge.mangaTitle,
        chapterNumber: chapter.chapterLabel,
        pageIndex: _currentPageNotifier.value,
      ),
    );
    if (getIt.isRegistered<MangaReadHistoryCubit>()) {
      unawaited(
        getIt<MangaReadHistoryCubit>().recordProgress(
          MangaHistoryEntry(
            mangaId: widget.bridge.mangaDexId,
            title: widget.bridge.mangaTitle,
            coverUrl: widget.bridge.coverUrl,
            formatLabel: widget.formatLabel,
            chapterId: chapter.id,
            chapterLabel: chapter.chapterLabel.startsWith('Глава') ||
                    chapter.chapterLabel.startsWith('Спешл')
                ? chapter.chapterLabel
                : 'Глава ${chapter.chapterLabel}',
            pageIndex: _currentPageNotifier.value + 1,
            totalPages: _pages.isNotEmpty ? _pages.length : 1,
            updatedAt: DateTime.now(),
          ),
        ),
      );
    }
  }

  Future<void> _pinToProfileShowcase() async {
    HapticFeedback.mediumImpact();
    final chapter = _chapters.isNotEmpty &&
            _currentChapterIndex >= 0 &&
            _currentChapterIndex < _chapters.length
        ? _chapters[_currentChapterIndex]
        : null;
    await _progressRepo.saveFeaturedManga(
      FeaturedMangaShowcase(
        mangaId: widget.bridge.mangaDexId,
        mangaTitle: widget.bridge.mangaTitle,
        coverUrl: widget.bridge.coverUrl,
        chapterLabel: chapter?.chapterLabel ?? '1',
        totalChapters: widget.bridge.chaptersCount ?? (_chapters.isNotEmpty ? _chapters.length : null),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Манга закреплена в витрине профиля'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _toggleReadingMode() {
    HapticFeedback.selectionClick();
    final nextMode = _readingMode == MangaReadingMode.webtoon
        ? MangaReadingMode.paged
        : MangaReadingMode.webtoon;
    if (nextMode == MangaReadingMode.paged) {
      _pageController.dispose();
      _pageController = PageController(initialPage: _currentPageNotifier.value);
    }
    setState(() => _readingMode = nextMode);
  }

  void _openChapterSelector() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF131722),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final primary = Theme.of(context).colorScheme.primary;
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Row(
                    children: [
                      Icon(Icons.menu_book_rounded, color: primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Главы (${_chapters.length})',
                          style: AppTypography.titleMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    itemCount: _chapters.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (ctx, idx) {
                      final chap = _chapters[idx];
                      final isCurrent = idx == _currentChapterIndex;
                      return InkWell(
                        key: ValueKey('manga_chapter_item_${chap.chapterLabel}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          _loadChapterPages(idx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? primary.withValues(alpha: 0.16)
                                : const Color(0xFF0B0E14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCurrent
                                  ? primary
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      chap.displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent
                                            ? primary
                                            : AppColors.textPrimary,
                                        fontWeight: isCurrent
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      chap.secondaryMeta,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  chap.translatedLanguage.toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentChapter = _chapters.isNotEmpty &&
            _currentChapterIndex >= 0 &&
            _currentChapterIndex < _chapters.length
        ? _chapters[_currentChapterIndex]
        : null;
    final hasPrev = _currentChapterIndex > 0;
    final hasNext =
        _chapters.isNotEmpty && _currentChapterIndex < _chapters.length - 1;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Основной холст страниц (Webtoon / Paged) с интуитивными зонами тапа
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) {
              if (_readingMode == MangaReadingMode.webtoon || _pages.isEmpty) {
                setState(() => _showOverlay = !_showOverlay);
                return;
              }
              final width = MediaQuery.sizeOf(context).width;
              final dx = details.localPosition.dx;
              if (dx < width * 0.25) {
                if (_currentPageNotifier.value > 0) {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                  );
                }
              } else if (dx > width * 0.75) {
                if (_currentPageNotifier.value < _pages.length - 1) {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                  );
                }
              } else {
                setState(() => _showOverlay = !_showOverlay);
              }
            },
            child: _buildReaderContent(primary),
          ),

          // Верхний минималистичный оверлей с контрастным градиентом
          if (_showOverlay)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  8,
                  MediaQuery.paddingOf(context).top + 6,
                  10,
                  16,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xD90B0E14),
                      Color(0x990B0E14),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.bridge.mangaTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (currentChapter != null)
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    currentChapter.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  key: const ValueKey('manga_reader_lang_badge'),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: currentChapter.translatedLanguage == 'ru'
                                        ? const Color(0xFF35D9D5).withValues(alpha: 0.2)
                                        : Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    '${currentChapter.translatedLanguage.toUpperCase()} • ${currentChapter.source}',
                                    style: TextStyle(
                                      color: currentChapter.translatedLanguage == 'ru'
                                          ? const Color(0xFF35D9D5)
                                          : Colors.white70,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('manga_pin_showcase_btn'),
                      tooltip: 'В витрину профиля',
                      onPressed: _pinToProfileShowcase,
                      icon: const Icon(
                        Icons.stars_rounded,
                        color: Color(0xFFFFD54F),
                        size: 22,
                      ),
                    ),
                    if (_chapters.isNotEmpty)
                      TextButton.icon(
                        key: const ValueKey('manga_reader_chapters_btn'),
                        onPressed: _openChapterSelector,
                        icon: const Icon(Icons.list_rounded, size: 18),
                        label: const Text('Главы'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xFF131722),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Нижний минималистичный оверлей с контрастным градиентом и ValueListenableBuilder
          if (_showOverlay && !_isLoadingChapters)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  12,
                  18,
                  12,
                  MediaQuery.paddingOf(context).bottom + 12,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xE60B0E14),
                      Color(0xA60B0E14),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      key: const ValueKey('manga_prev_chapter_btn'),
                      onPressed: hasPrev
                          ? () => _loadChapterPages(_currentChapterIndex - 1)
                          : null,
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        size: 18,
                        color: hasPrev ? Colors.white : AppColors.textMuted,
                      ),
                      label: Text(
                        'Пред. глава',
                        style: TextStyle(
                          color: hasPrev ? Colors.white : AppColors.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _currentPageNotifier,
                          builder: (context, pageIdx, _) {
                            return Text(
                              _pages.isNotEmpty
                                  ? 'Стр. ${pageIdx + 1} / ${_pages.length}'
                                  : (currentChapter?.displayTitle ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Material(
                      key: const ValueKey('manga_mode_toggle_btn'),
                      color: const Color(0xFF1A2030),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _toggleReadingMode,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _readingMode == MangaReadingMode.webtoon
                                    ? Icons.view_day_rounded
                                    : Icons.auto_stories_rounded,
                                color: const Color(0xFF35D9D5),
                                size: 15,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _readingMode == MangaReadingMode.webtoon
                                    ? 'Вебтун'
                                    : 'Страницы',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      key: const ValueKey('manga_next_chapter_btn'),
                      onPressed: hasNext
                          ? () => _loadChapterPages(_currentChapterIndex + 1)
                          : null,
                      icon: Icon(
                        Icons.skip_next_rounded,
                        size: 18,
                        color: hasNext ? Colors.white : AppColors.textMuted,
                      ),
                      label: Text(
                        'След. глава',
                        style: TextStyle(
                          color: hasNext ? Colors.white : AppColors.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReaderContent(Color primary) {
    if (_isLoadingChapters || _isLoadingPages) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(primary),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.menu_book_outlined,
                color: AppColors.textMuted,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _initReader,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Повторить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      final encoded = Uri.encodeComponent(widget.bridge.mangaTitle);
                      launchUrl(
                        Uri.parse('https://shikimori.io/mangas?search=$encoded'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 17),
                    label: const Text('Открыть на Shikimori'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A2030),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_readingMode == MangaReadingMode.paged) {
      return PageView.builder(
        key: const ValueKey('manga_paged_view'),
        controller: _pageController,
        itemCount: _pages.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 3.0,
            child: Center(
              child: _buildMangaPageImage(index, primary, fit: BoxFit.contain),
            ),
          );
        },
      );
    }

    // Вертикальный Webtoon-режим (центрирован до 760px на широких экранах, cacheExtent 1800)
    return Center(
      child: ConstrainedBox(
        key: const ValueKey('manga_webtoon_max_width'),
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView.builder(
          key: const ValueKey('manga_webtoon_list'),
          controller: _webtoonScrollController,
          cacheExtent: 1200,
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 56,
            bottom: MediaQuery.paddingOf(context).bottom + 72,
          ),
          itemCount: _pages.length,
          itemBuilder: (context, index) {
            return _buildMangaPageImage(
              index,
              primary,
              fit: BoxFit.fitWidth,
              width: double.infinity,
            );
          },
        ),
      ),
    );
  }

  Widget _buildMangaPageImage(
    int index,
    Color primary, {
    required BoxFit fit,
    double? width,
  }) {
    final useSaver = _useDataSaverIndices.contains(index) &&
        index < _dataSaverPages.length;
    final imageUrl = useSaver ? _dataSaverPages[index] : _pages[index];
    final retrySeed = _pageRetrySeeds[index] ?? 0;
    final canFallbackToSaver = !useSaver &&
        index < _dataSaverPages.length &&
        _dataSaverPages[index] != imageUrl;

    if (canFallbackToSaver) {
      _pageTimeoutTimers[index] ??= Timer(const Duration(seconds: 4), () {
        _pageTimeoutTimers.remove(index);
        if (mounted && !_useDataSaverIndices.contains(index)) {
          setState(() => _useDataSaverIndices.add(index));
        }
      });
    }

    return CachedNetworkImage(
      key: ValueKey('manga_page_${index}_${useSaver ? 'ds' : 'hq'}_$retrySeed'),
      imageUrl: imageUrl,
      httpHeaders: imageUrl.contains('remanga')
          ? const {'Referer': 'https://remanga.org'}
          : null,
      fit: fit,
      width: width,
      imageBuilder: (_, imageProvider) {
        _pageTimeoutTimers.remove(index)?.cancel();
        return Image(
          image: imageProvider,
          fit: fit,
          width: width,
        );
      },
      placeholder: (_, __) => const SizedBox(
        height: 360,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (_, __, ___) {
        _pageTimeoutTimers.remove(index)?.cancel();
        if (canFallbackToSaver) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_useDataSaverIndices.contains(index)) {
              setState(() => _useDataSaverIndices.add(index));
            }
          });
          return const SizedBox(
            height: 360,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return SizedBox(
          height: 220,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textMuted,
                  size: 32,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _pageRetrySeeds[index] = retrySeed + 1;
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Повторить'),
                  style: TextButton.styleFrom(foregroundColor: primary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

