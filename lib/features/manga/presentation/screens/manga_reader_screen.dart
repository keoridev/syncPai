import 'dart:async';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../widgets/manga_panel_cropper_sheet.dart';

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

class _MangaReaderScreenState extends State<MangaReaderScreen>
    with SingleTickerProviderStateMixin {
  late final MangaDexDataSource _dataSource;
  late final MangaProgressRepository _progressRepo;

  late MangaReadingMode _readingMode;
  List<MangaDexChapter> _chapters = const [];
  int _currentChapterIndex = 0;
  List<String> _pages = const [];
  List<String> _dataSaverPages = const [];
  static const String _zoomScalePrefKey = 'reader_zoom_scale';
  final Map<int, double> _pageAspectRatios = {};
  final FocusNode _readerFocusNode = FocusNode();
  final TransformationController _pagedZoomController = TransformationController();
  final TransformationController _webtoonZoomController = TransformationController();
  late final AnimationController _zoomAnimController;
  Animation<Matrix4>? _zoomAnimation;
  Offset _doubleTapPosition = Offset.zero;
  int _activePointers = 0;
  double _zoomScale = 1.0;

  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  double get _currentPagedScale =>
      _pagedZoomController.value.getMaxScaleOnAxis();
  double _accumulatedOverscroll = 0.0;
  bool _isAutoTransitioningChapter = false;
  DateTime _lastPagedWheelAt = DateTime.fromMillisecondsSinceEpoch(0);
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
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_zoomAnimation == null) return;
        if (_readingMode == MangaReadingMode.webtoon) {
          _webtoonZoomController.value = _zoomAnimation!.value;
        } else {
          _pagedZoomController.value = _zoomAnimation!.value;
        }
      });
    _pagedZoomController.addListener(_onPagedZoomChanged);
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
    _loadZoomScale();
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
    _pagedZoomController.removeListener(_onPagedZoomChanged);
    _pagedZoomController.dispose();
    _webtoonZoomController.dispose();
    _zoomAnimController.dispose();
    _readerFocusNode.dispose();
    super.dispose();
  }

  void _onPagedZoomChanged() {
    if (mounted) setState(() {});
  }

  void _handleDoubleTapZoom(TransformationController controller) {
    final currentScale = controller.value.getMaxScaleOnAxis();
    final Matrix4 targetMatrix;
    if (currentScale > 1.2) {
      targetMatrix = Matrix4.identity();
    } else {
      const targetScale = 1.85;
      final x = -_doubleTapPosition.dx * (targetScale - 1.0);
      final y = -_doubleTapPosition.dy * (targetScale - 1.0);
      targetMatrix = Matrix4.identity()
        ..translateByDouble(x, y, 0.0, 1.0)
        ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
    }
    _zoomAnimation = Matrix4Tween(
      begin: controller.value,
      end: targetMatrix,
    ).animate(
      CurvedAnimation(parent: _zoomAnimController, curve: Curves.easeOutCubic),
    );
    _zoomAnimController.forward(from: 0.0);
  }

  Future<void> _loadZoomScale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_zoomScalePrefKey);
      if (saved != null && mounted) {
        final clamped = saved.clamp(0.75, 2.25);
        setState(() => _zoomScale = clamped);
        _syncPagedZoomMatrix(clamped);
      }
    } catch (_) {}
  }

  void _syncPagedZoomMatrix(double scale) {
    final s = scale.clamp(0.75, 3.5);
    _pagedZoomController.value =
        s == 1.0 ? Matrix4.identity() : (Matrix4.identity()..scaleByDouble(s, s, 1.0, 1.0));
  }

  Future<void> _setZoomScale(double next) async {
    final clamped = ((next * 100).round() / 100.0).clamp(0.75, 2.25);
    if ((clamped - _zoomScale).abs() < 0.001) return;
    setState(() => _zoomScale = clamped);
    _syncPagedZoomMatrix(clamped);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_zoomScalePrefKey, clamped);
    } catch (_) {}
  }

  Future<void> _goToNextChapter() async {
    if (_isAutoTransitioningChapter) return;
    if (_currentChapterIndex + 1 >= _chapters.length) return;
    _isAutoTransitioningChapter = true;
    _accumulatedOverscroll = 0.0;
    try {
      await _loadChapterPages(_currentChapterIndex + 1);
      if (mounted &&
          _readingMode == MangaReadingMode.webtoon &&
          _webtoonScrollController.hasClients) {
        _webtoonScrollController.jumpTo(0.0);
      }
    } finally {
      _isAutoTransitioningChapter = false;
    }
  }

  Future<void> _goToPrevChapter() async {
    if (_isAutoTransitioningChapter) return;
    if (_currentChapterIndex <= 0) return;
    _isAutoTransitioningChapter = true;
    _accumulatedOverscroll = 0.0;
    try {
      await _loadChapterPages(_currentChapterIndex - 1);
      if (mounted &&
          _readingMode == MangaReadingMode.webtoon &&
          _webtoonScrollController.hasClients) {
        _webtoonScrollController.jumpTo(0.0);
      }
    } finally {
      _isAutoTransitioningChapter = false;
    }
  }

  void _stepPagedNext() {
    if (_pages.isEmpty) return;
    if (_currentPageNotifier.value < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    } else {
      _goToNextChapter();
    }
  }

  void _stepPagedPrev() {
    if (_pages.isEmpty) return;
    if (_currentPageNotifier.value > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    } else {
      _goToPrevChapter();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _setZoomScale(_zoomScale + 0.15);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _setZoomScale(_zoomScale - 0.15);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      _setZoomScale(1.0);
      return KeyEventResult.handled;
    }

    if (_readingMode == MangaReadingMode.paged) {
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.keyD ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.pageDown) {
        _stepPagedNext();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.keyA ||
          key == LogicalKeyboardKey.pageUp) {
        _stepPagedPrev();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Webtoon mode
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS ||
        key == LogicalKeyboardKey.space) {
      if (_webtoonScrollController.hasClients) {
        final pos = _webtoonScrollController.position;
        if (pos.pixels >= pos.maxScrollExtent - 4) {
          _goToNextChapter();
        } else {
          final target = (pos.pixels + 480.0).clamp(0.0, pos.maxScrollExtent);
          _webtoonScrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      if (_webtoonScrollController.hasClients) {
        final pos = _webtoonScrollController.position;
        final target = (pos.pixels - 480.0).clamp(0.0, pos.maxScrollExtent);
        _webtoonScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.bracketRight) {
      _goToNextChapter();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.bracketLeft) {
      _goToPrevChapter();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _pages.isEmpty) return;

    if (_readingMode == MangaReadingMode.paged) {
      final now = DateTime.now();
      if (now.difference(_lastPagedWheelAt) < const Duration(milliseconds: 220)) {
        return;
      }
      _lastPagedWheelAt = now;
      if (event.scrollDelta.dy > 0) {
        _stepPagedNext();
      } else if (event.scrollDelta.dy < 0) {
        _stepPagedPrev();
      }
      return;
    }

    if (_webtoonScrollController.hasClients &&
        _currentChapterIndex + 1 < _chapters.length) {
      final pos = _webtoonScrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 2 && event.scrollDelta.dy > 0) {
        final nextAccum = _accumulatedOverscroll + event.scrollDelta.dy.abs();
        setState(() => _accumulatedOverscroll = nextAccum);
        if (nextAccum > 140.0) {
          _goToNextChapter();
        }
      } else if (event.scrollDelta.dy < 0 && _accumulatedOverscroll > 0) {
        setState(() => _accumulatedOverscroll = 0.0);
      }
    }
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
        _errorMessage = 'Главы пока не найдены ни в одном из источников.';
      });
      return;
    }

    int targetIdx = 0;
    int initialPage = widget.initialPage != null
        ? (widget.initialPage! - 1).clamp(0, 9999)
        : 0;

    final targetChap = widget.initialChapter ?? widget.bridge.continueFromChapter;
    final historyEntry = getIt.isRegistered<MangaReadHistoryCubit>()
        ? getIt<MangaReadHistoryCubit>().state.getEntryFor(widget.bridge.mangaDexId)
        : null;
    final savedHistoryChapNum = historyEntry != null
        ? double.tryParse(
            RegExp(r'\d+(?:\.\d+)?')
                    .firstMatch(historyEntry.chapterLabel)
                    ?.group(0) ??
                '',
          )
        : null;

    if (targetChap != null &&
        historyEntry != null &&
        savedHistoryChapNum != null &&
        savedHistoryChapNum > targetChap) {
      // Не откатываем прогресс назад, если пользователь уже прочитал дальше
      final byId = chapters.indexWhere((c) => c.id == historyEntry.chapterId);
      final byNum = chapters.indexWhere(
        (c) =>
            c.chapterNumber != null &&
            (c.chapterNumber! - savedHistoryChapNum).abs() < 0.01,
      );
      targetIdx = byId >= 0 ? byId : (byNum >= 0 ? byNum : 0);
      initialPage = (historyEntry.pageIndex - 1).clamp(0, 9999);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        MascotCompanionService.instance.notifyMangaSavedProgressPreserved(
          historyEntry.chapterLabel,
          historyEntry.pageIndex,
        );
      });
    } else if (targetChap != null) {
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
        : await repo.getChapterPagesForChapter(
            chapter,
            mangaTitle: widget.bridge.mangaTitle,
          );
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
    if (index >= 3 &&
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

  Future<void> _cropCurrentPageToShowcase() async {
    HapticFeedback.lightImpact();
    if (_pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Дождитесь загрузки страниц главы'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final safeIdx = _currentPageNotifier.value.clamp(0, _pages.length - 1);
    final pageUrl = _pages[safeIdx];
    final chapter = _chapters.isNotEmpty &&
            _currentChapterIndex >= 0 &&
            _currentChapterIndex < _chapters.length
        ? _chapters[_currentChapterIndex]
        : null;
    final chapterNum = chapter?.chapterLabel.trim() ?? '';
    final chapterLabel = chapterNum.isNotEmpty ? 'Глава $chapterNum' : 'Глава 1';
    final referer = resolveMangaImageReferer(pageUrl);

    final saved = await MangaPanelCropperSheet.show(
      context,
      mangaId: widget.bridge.mangaDexId,
      mangaTitle: widget.bridge.mangaTitle,
      chapterLabel: chapterLabel,
      pageUrl: pageUrl,
      refererHeader: referer,
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Кадр добавлен в витрину профиля'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
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

    return Focus(
      focusNode: _readerFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: Scaffold(
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
                                    currentChapter.translatedLanguage.toUpperCase(),
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
                      key: const ValueKey('manga_crop_showcase_btn'),
                      tooltip: 'Витрина',
                      onPressed: _cropCurrentPageToShowcase,
                      icon: const Icon(
                        Icons.crop_rounded,
                        color: Colors.white,
                        size: 20,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!kIsWeb && Platform.isWindows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141821),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0x14FFFFFF)),
                          ),
                          child: const Text(
                            'Стрелки / Пробел — листать • Колесо вниз в конце — след. глава',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    Row(
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
                        if (_isDesktopPlatform) ...[
                          const SizedBox(width: 6),
                          _buildZoomControlPill(),
                        ],
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
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
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
      return Listener(
        onPointerDown: (_) => setState(() => _activePointers++),
        onPointerUp: (_) =>
            setState(() => _activePointers = (_activePointers - 1).clamp(0, 10)),
        onPointerCancel: (_) =>
            setState(() => _activePointers = (_activePointers - 1).clamp(0, 10)),
        child: PageView.builder(
          key: const ValueKey('manga_paged_view'),
          controller: _pageController,
          physics: (_activePointers >= 2 || _currentPagedScale > 1.02)
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemCount: _pages.length,
          onPageChanged: (idx) {
            _syncPagedZoomMatrix(_zoomScale);
            _onPageChanged(idx);
          },
          itemBuilder: (context, index) {
            return GestureDetector(
              onDoubleTapDown: (details) =>
                  _doubleTapPosition = details.localPosition,
              onDoubleTap: () => _handleDoubleTapZoom(_pagedZoomController),
              child: InteractiveViewer(
                transformationController: _pagedZoomController,
                minScale: 0.75,
                maxScale: 3.5,
                panEnabled: true,
                scaleEnabled: true,
                child: Center(
                  child: _buildMangaPageImage(index, primary, fit: BoxFit.contain),
                ),
              ),
            );
          },
        ),
      );
    }

    // Вертикальный Webtoon-режим (центрирован до 680 * _zoomScale на широких экранах)
    final currentChapter = _chapters.isNotEmpty &&
            _currentChapterIndex >= 0 &&
            _currentChapterIndex < _chapters.length
        ? _chapters[_currentChapterIndex]
        : null;
    final nextChapter = (_currentChapterIndex + 1 < _chapters.length)
        ? _chapters[_currentChapterIndex + 1]
        : null;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWebtoonWidth =
        (680.0 * _zoomScale).clamp(280.0, screenWidth);

    return Listener(
      onPointerDown: (_) => setState(() => _activePointers++),
      onPointerUp: (_) =>
          setState(() => _activePointers = (_activePointers - 1).clamp(0, 10)),
      onPointerCancel: (_) =>
          setState(() => _activePointers = (_activePointers - 1).clamp(0, 10)),
      child: GestureDetector(
        onDoubleTapDown: (details) =>
            _doubleTapPosition = details.localPosition,
        onDoubleTap: () => _handleDoubleTapZoom(_webtoonZoomController),
        child: InteractiveViewer(
          transformationController: _webtoonZoomController,
          minScale: 0.75,
          maxScale: 3.0,
          panEnabled: true,
          scaleEnabled: true,
          boundaryMargin: const EdgeInsets.symmetric(horizontal: 140, vertical: 60),
          child: Center(
            child: ConstrainedBox(
              key: const ValueKey('manga_webtoon_max_width'),
              constraints: BoxConstraints(maxWidth: maxWebtoonWidth),
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (nextChapter != null && notification is OverscrollNotification) {
                    if (notification.overscroll > 0) {
                      final nextAccum =
                          _accumulatedOverscroll + notification.overscroll;
                      setState(() => _accumulatedOverscroll = nextAccum);
                      if (nextAccum > 140.0) {
                        _goToNextChapter();
                      }
                    }
                  } else if (notification is ScrollUpdateNotification &&
                      _accumulatedOverscroll > 0 &&
                      notification.metrics.pixels <
                          notification.metrics.maxScrollExtent - 10) {
                    setState(() => _accumulatedOverscroll = 0.0);
                  }
                  return false;
                },
                child: ListView.builder(
                  key: const ValueKey('manga_webtoon_list'),
                  controller: _webtoonScrollController,
                  physics: _activePointers >= 2
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  cacheExtent: 1200,
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 56,
              bottom: MediaQuery.paddingOf(context).bottom + 72,
            ),
            itemCount: _pages.length + (nextChapter != null ? 1 : 0),
            itemBuilder: (context, index) {
              if (nextChapter != null && index == _pages.length) {
                final progress = (_accumulatedOverscroll / 140.0).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: InkWell(
                    key: const ValueKey('manga_webtoon_next_chapter_card'),
                    onTap: _goToNextChapter,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141821),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x14FFFFFF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Конец главы ${currentChapter?.chapterLabel ?? ''}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Далее: Глава ${nextChapter.chapterLabel}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: primary,
                                size: 20,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress > 0 ? progress : 0.0,
                              minHeight: 4,
                              backgroundColor: const Color(0xFF1C212E),
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return _KeepAliveMangaPageSlot(
                key: ValueKey('webtoon_slot_$index'),
                child: AspectRatio(
                  aspectRatio: _pageAspectRatios[index] ?? 0.70,
                  child: _buildMangaPageImage(
                    index,
                    primary,
                    fit: BoxFit.fitWidth,
                    width: double.infinity,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
    ),
    ),
    );
  }

  Widget _buildZoomControlPill() {
    final canZoomOut = _zoomScale > 0.751;
    final canZoomIn = _zoomScale < 2.249;
    final percentLabel = '${(_zoomScale * 100).round()}%';

    return Container(
      key: const ValueKey('manga_zoom_control_pill'),
      decoration: BoxDecoration(
        color: const Color(0xFF141821),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('manga_zoom_out_btn'),
            onTap: canZoomOut ? () => _setZoomScale(_zoomScale - 0.15) : null,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              child: Icon(
                Icons.remove_rounded,
                size: 15,
                color: canZoomOut ? Colors.white : AppColors.textMuted,
              ),
            ),
          ),
          InkWell(
            key: const ValueKey('manga_zoom_reset_btn'),
            onTap: () => _setZoomScale(1.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text(
                percentLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          InkWell(
            key: const ValueKey('manga_zoom_in_btn'),
            onTap: canZoomIn ? () => _setZoomScale(_zoomScale + 0.15) : null,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              child: Icon(
                Icons.add_rounded,
                size: 15,
                color: canZoomIn ? Colors.white : AppColors.textMuted,
              ),
            ),
          ),
        ],
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

    final referer = resolveMangaImageReferer(imageUrl);
    return CachedNetworkImage(
      key: ValueKey('manga_page_${index}_${useSaver ? 'ds' : 'hq'}_$retrySeed'),
      imageUrl: imageUrl,
      httpHeaders: referer != null ? {'Referer': referer} : null,
      fit: fit,
      width: width,
      imageBuilder: (_, imageProvider) {
        _pageTimeoutTimers.remove(index)?.cancel();
        if (!_pageAspectRatios.containsKey(index)) {
          final stream = imageProvider.resolve(const ImageConfiguration());
          late final ImageStreamListener listener;
          listener = ImageStreamListener(
            (info, _) {
              stream.removeListener(listener);
              if (mounted && info.image.height > 0) {
                final ratio = (info.image.width / info.image.height).clamp(0.25, 3.0);
                if (_pageAspectRatios[index] != ratio) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _pageAspectRatios[index] = ratio);
                    }
                  });
                }
              }
            },
            onError: (_, __) => stream.removeListener(listener),
          );
          stream.addListener(listener);
        }
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

class _KeepAliveMangaPageSlot extends StatefulWidget {
  final Widget child;
  const _KeepAliveMangaPageSlot({super.key, required this.child});

  @override
  State<_KeepAliveMangaPageSlot> createState() =>
      _KeepAliveMangaPageSlotState();
}

class _KeepAliveMangaPageSlotState extends State<_KeepAliveMangaPageSlot>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

