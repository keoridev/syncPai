import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/services/mascot_companion_service.dart';
import '../../../anime_details/data/datasources/shikimori_remote_datasource.dart';
import '../../../manga/data/datasources/mangadex_datasource.dart';
import '../../../manga/data/repositories/manga_repository.dart';
import '../../../manga/domain/entities/manga_bridge.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/entities/catalog_filter.dart';
import '../../domain/entities/catalog_filter_query.dart';
import '../../domain/entities/catalog_settings.dart';
import '../../data/datasources/shikimori_announced_datasource.dart';
import '../../data/services/catalog_persistent_store.dart';
import '../../domain/usecases/get_catalog_usecase.dart';
import '../../domain/usecases/get_updates.dart';
import '../../domain/usecases/search_catalog_usecase.dart';
import '../../domain/usecases/search_titles.dart';
import '../../services/catalog_prefetch_service.dart';
import 'catalog_state.dart';

class CatalogCubit extends Cubit<CatalogState> {
  final GetUpdates getUpdates;
  final SearchTitles searchTitles;
  final SharedPreferences? prefs;
  final GetCatalogUseCase? getCatalogUseCase;
  final SearchCatalogUseCase? searchCatalogUseCase;
  final ShikimoriAnnouncedDataSource? shikimoriAnnouncedDataSource;
  final MangaDexDataSource? mangaDexDataSource;
  final ShikimoriRemoteDataSource? shikimoriRemoteDataSource;

  Timer? _searchDebounceTimer;
  Timer? _filterDebounceTimer;
  Timer? _mangaSearchDebounce;
  CancelToken? _foregroundCancelToken;
  List<AnimeTitle> _cachedUpdates = [];

  CancelToken _resetForegroundCancelToken(String reason) {
    if (_foregroundCancelToken != null && !_foregroundCancelToken!.isCancelled) {
      _foregroundCancelToken!.cancel(reason);
    }
    _foregroundCancelToken = CancelToken();
    return _foregroundCancelToken!;
  }

  // In-Memory кэш: Ключ - название категории/жанра (например, 'Экшен', 'Все'), Значение - список тайтлов
  final Map<String, List<AnimeTitle>> _cache = {};
  // Текущая страница для каждой категории
  final Map<String, int> _pageMap = {};
  // Наличие страниц для каждой категории
  final Map<String, bool> _hasMoreMap = {};
  // Флаг, чтобы не дублировать одновременные сетевые запросы пагинации
  bool _isLoadingMore = false;

  final Map<String, List<AnimeTitle>> _pageCache = {};
  final Map<String, List<AnimeTitle>> _tabMemoryCache = {};
  final Map<String, CancelToken> _inFlight = {};
  final Map<String, Future<void>> _inFlightFutures = {};
  String _activeFilterKey = 'all|updates|||false';
  int _requestId = 0;
  int _loadGeneration = 0;
  bool _initialized = false;

  void _cancelForeignInFlight(String activeSignature) {
    final prefix = '${activeSignature}_p';
    final staleKeys =
        _inFlight.keys.where((k) => !k.startsWith(prefix)).toList();
    for (final k in staleKeys) {
      final token = _inFlight.remove(k);
      if (token != null && !token.isCancelled) {
        token.cancel('Filter changed to $activeSignature');
      }
      _inFlightFutures.remove(k);
    }
  }

  /// Единая таблица маппинга быстрых вкладок каталога в источник данных [CatalogTabSource].
  static Map<String, CatalogTabSource> get quickTabSources => {
        'all': const AnilibriaCatalogSource(
          CatalogFilter(sorting: CatalogSorting.freshAtDesc),
        ),
        'ongoing': const AnilibriaCatalogSource(
          CatalogFilter(
            sorting: CatalogSorting.freshAtDesc,
            publishStatuses: [PublishStatus.isOngoing],
          ),
        ),
        'released': const AnilibriaCatalogSource(
          CatalogFilter(
            sorting: CatalogSorting.freshAtDesc,
            publishStatuses: [PublishStatus.isNotOngoing],
          ),
        ),
        'popular': const AnilibriaCatalogSource(
          CatalogFilter(sorting: CatalogSorting.ratingDesc),
        ),
        'movies': const AnilibriaCatalogSource(
          CatalogFilter(
            sorting: CatalogSorting.freshAtDesc,
            types: [ReleaseType.movie],
          ),
        ),
        'anons': ShikimoriAnnouncedSource(computeNextShikimoriSeason()),
        'schedule': const AniLibriaScheduleSource(),
      };

  /// Декларативная загрузка каталога по [CatalogFilter].
  Future<void> load(
    CatalogFilter filter, {
    int page = 1,
    bool refresh = false,
  }) {
    return loadSource(
      AnilibriaCatalogSource(filter),
      page: page,
      refresh: refresh,
    );
  }

  /// Универсальная загрузка вкладки по [CatalogTabSource] (AniLibria catalog / Shikimori announced / schedule)
  /// с отменой чужих токенов, дедупликацией in-flight `(signature, page)`, последовательной пагинацией и SWR.
  Future<void> loadSource(
    CatalogTabSource source, {
    int page = 1,
    bool refresh = false,
  }) async {
    final sig = source is ShikimoriAnnouncedSource
        ? 'tab:announcements'
        : source.signature;
    final effectivePage =
        (source is AnilibriaCatalogSource || source is ShikimoriAnnouncedSource)
            ? page
            : 1;
    final inFlightKey = '${sig}_p$effectivePage';
    if (_inFlightFutures.containsKey(inFlightKey)) {
      return _inFlightFutures[inFlightKey]!;
    }

    // Последовательная пагинация: page > 1 разрешён только для AnilibriaCatalogSource и при hasMore == true
    if (effectivePage > 1) {
      final cur = state is CatalogLoaded ? (state as CatalogLoaded) : null;
      if (_isLoadingMore ||
          cur == null ||
          cur.activeFilterKey != sig ||
          !cur.hasMore ||
          effectivePage != cur.currentPage + 1) {
        return;
      }
      _isLoadingMore = true;
      emit(cur.copyWith(isLoadingMore: true, isLoadingNextPage: true));
    }

    final currentGen = ++_loadGeneration;
    _activeFilterKey = sig;
    _cancelForeignInFlight(sig);

    final CatalogFilter? catalogFilter =
        source is AnilibriaCatalogSource ? source.filter : null;
    final sortBy = catalogFilter != null
        ? _sortFromCatalogSorting(catalogFilter.sorting)
        : CatalogSort.updates;
    final statusFilter = catalogFilter != null
        ? _statusFromFilter(catalogFilter)
        : (source is ShikimoriAnnouncedSource ? 'anons' : null);
    final typeFilter = (catalogFilter != null && catalogFilter.types.isNotEmpty)
        ? catalogFilter.types.first.apiValue
        : null;

    // Stale-While-Revalidate на page == 1
    if (effectivePage == 1 && !refresh) {
      final swr = CatalogPersistentStore.instance.getBySignature(sig);
      if (swr != null && swr.items.isNotEmpty) {
        emit(CatalogLoaded(
          titles: swr.items,
          filteredTitles: swr.items,
          sortBy: sortBy,
          statusFilter: statusFilter,
          typeFilter: typeFilter,
          viewMode: _currentViewMode,
          gridDensity: _currentGridDensity,
          currentPage: swr.page,
          hasMore: source is AnilibriaCatalogSource ? swr.hasMore : false,
          activeFilterKey: sig,
          isRefreshing: true,
        ));
      } else if (state is! CatalogLoaded) {
        emit(const CatalogLoading());
      } else {
        emit((state as CatalogLoaded).copyWith(
          activeFilterKey: sig,
          statusFilter: statusFilter,
          clearStatusFilter: statusFilter == null,
          typeFilter: typeFilter,
          clearTypeFilter: typeFilter == null,
          sortBy: sortBy,
          isRefreshing: true,
          titles: const [],
          filteredTitles: const [],
        ));
      }
    }

    final cancelToken = CancelToken();
    _inFlight[inFlightKey] = cancelToken;

    final future = () async {
      try {
        final List<AnimeTitle> incoming;
        final bool hasMore;

        switch (source) {
          case AnilibriaCatalogSource(:final filter):
            final useCase = getCatalogUseCase ??
                (getIt.isRegistered<GetCatalogUseCase>()
                    ? getIt<GetCatalogUseCase>()
                    : null);
            if (useCase == null) return;
            final pageResult = await useCase.getReleases(
              filter: filter,
              page: effectivePage,
              limit: 40,
              cancelToken: cancelToken,
            );
            incoming = pageResult.items.map((e) => e.toAnimeTitle()).toList();
            hasMore = pageResult.hasMore;
            break;

          case ShikimoriAnnouncedSource(:final season):
            if (getIt.isRegistered<ShikimoriRemoteDataSource>()) {
              incoming = await getIt<ShikimoriRemoteDataSource>()
                  .getUpcomingAnnouncements(page: effectivePage, limit: 40);
              hasMore = incoming.length >= 40;
            } else {
              final shikiDs = shikimoriAnnouncedDataSource ??
                  (getIt.isRegistered<ShikimoriAnnouncedDataSource>()
                      ? getIt<ShikimoriAnnouncedDataSource>()
                      : null);
              if (shikiDs == null) {
                incoming = const [];
              } else {
                incoming = await shikiDs.fetchAnnounced(
                  season: season,
                  cancelToken: cancelToken,
                );
              }
              hasMore = false;
            }
            break;

          case AniLibriaScheduleSource():
            final useCase = getCatalogUseCase ??
                (getIt.isRegistered<GetCatalogUseCase>()
                    ? getIt<GetCatalogUseCase>()
                    : null);
            if (useCase == null) {
              incoming = const [];
            } else {
              final entities = await useCase.getSchedule(
                cancelToken: cancelToken,
              );
              incoming = entities.map((e) => e.toAnimeTitle()).toList();
            }
            hasMore = false;
            break;
        }

        if (currentGen != _loadGeneration || cancelToken.isCancelled || isClosed) {
          if (currentGen != _loadGeneration) {
            debugPrint(
              '[CatalogCubit] Discarded stale load response (gen=$currentGen, active=$_loadGeneration)',
            );
          }
          return;
        }

        final List<AnimeTitle> combined;
        if (effectivePage > 1 && state is CatalogLoaded) {
          final existing = (state as CatalogLoaded).titles;
          final seen = existing.map((e) => e.id).toSet();
          combined = [
            ...existing,
            ...incoming.where((item) => seen.add(item.id)),
          ];
        } else {
          combined = incoming;
        }

        CatalogPersistentStore.instance.putBySignature(
          sig,
          combined,
          page: effectivePage,
          hasMore: hasMore,
        );
        _tabMemoryCache[sig] = combined;

        emit(CatalogLoaded(
          titles: combined,
          filteredTitles: combined,
          sortBy: sortBy,
          statusFilter: statusFilter,
          typeFilter: typeFilter,
          viewMode: _currentViewMode,
          gridDensity: _currentGridDensity,
          currentPage: effectivePage,
          hasMore: hasMore,
          isLoadingMore: false,
          activeFilterKey: sig,
          isRefreshing: false,
          isLoadingNextPage: false,
        ));
      } catch (e) {
        if (currentGen != _loadGeneration || cancelToken.isCancelled || isClosed) {
          return;
        }
        if (state is CatalogLoaded) {
          emit((state as CatalogLoaded).copyWith(
            isLoadingMore: false,
            isRefreshing: false,
            isLoadingNextPage: false,
          ));
        } else {
          emit(CatalogLoaded(
            titles: const [],
            filteredTitles: const [],
            sortBy: sortBy,
            statusFilter: statusFilter,
            typeFilter: typeFilter,
            viewMode: _currentViewMode,
            gridDensity: _currentGridDensity,
            currentPage: 1,
            hasMore: false,
            activeFilterKey: sig,
          ));
        }
      } finally {
        if (effectivePage > 1) _isLoadingMore = false;
        _inFlight.remove(inFlightKey);
        _inFlightFutures.remove(inFlightKey);
      }
    }();

    _inFlightFutures[inFlightKey] = future;
    return future;
  }

  CatalogSort _sortFromCatalogSorting(CatalogSorting s) {
    switch (s) {
      case CatalogSorting.ratingDesc:
      case CatalogSorting.ratingAsc:
        return CatalogSort.rating;
      case CatalogSorting.yearDesc:
        return CatalogSort.yearDesc;
      case CatalogSorting.yearAsc:
        return CatalogSort.yearAsc;
      case CatalogSorting.freshAtDesc:
      case CatalogSorting.freshAtAsc:
        return CatalogSort.updates;
    }
  }

  String? _statusFromFilter(CatalogFilter filter) {
    if (filter.publishStatuses.contains(PublishStatus.isOngoing)) {
      return 'ongoing';
    }
    if (filter.publishStatuses.contains(PublishStatus.isNotOngoing)) {
      return 'released';
    }
    if (filter.productionStatuses.contains(ProductionStatus.isInProduction)) {
      return 'anons';
    }
    return null;
  }

  String _buildFilterKey({
    required Set<String> genres,
    required CatalogSort sortBy,
    String? statusFilter,
    String? typeFilter,
    bool matchAll = false,
  }) {
    final sortedGenres = genres
        .map((g) => g.trim().toLowerCase())
        .where((g) => g.isNotEmpty && g != 'все')
        .toList()
      ..sort();
    return '${sortedGenres.isEmpty ? "all" : sortedGenres.join(",")}|${sortBy.name}|${statusFilter ?? ""}|${typeFilter ?? ""}|$matchAll';
  }
  double _scrollOffset = 0.0;
  late CatalogViewMode _currentViewMode;
  late CatalogGridDensity _currentGridDensity;

  /// Сохраняет текущий скролл экрана, чтобы фоновые обновления не сдвигали видимые карточки.
  void setUserScrollOffset(double pixels) {
    _scrollOffset = pixels < 0 ? 0.0 : pixels;
  }

  /// Безопасное слияние свежих данных со списком на экране без перестановки верхних видимых карточек.
  static List<AnimeTitle> mergePreservingVisibleOrder({
    required List<AnimeTitle> currentVisible,
    required List<AnimeTitle> incoming,
  }) {
    if (currentVisible.isEmpty) return List<AnimeTitle>.from(incoming);
    final incomingById = <int, AnimeTitle>{for (final item in incoming) item.id: item};
    final merged = <AnimeTitle>[];
    for (final existing in currentVisible) {
      final updated = incomingById.remove(existing.id);
      merged.add(updated ?? existing);
    }
    if (incomingById.isNotEmpty) {
      merged.addAll(incomingById.values);
    }
    return merged;
  }

  String? _formatGenres(Set<String> genres) {
    final clean = genres
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty && g.toLowerCase() != 'все')
        .toList();
    return clean.isEmpty ? null : clean.join(',');
  }

  String _buildCacheKey({
    required String? genres,
    required CatalogSort sort,
    required String? status,
    String? type,
  }) {
    return '${genres ?? "all"}_${sort.name}_${status ?? "all"}_${type ?? "all"}';
  }

  CatalogCubit({
    required this.getUpdates,
    required this.searchTitles,
    this.prefs,
    this.getCatalogUseCase,
    this.searchCatalogUseCase,
    this.shikimoriAnnouncedDataSource,
    this.mangaDexDataSource,
    this.shikimoriRemoteDataSource,
  }) : super(const CatalogInitial()) {
    _currentViewMode = _loadSavedViewMode();
    _currentGridDensity = _loadSavedGridDensity();
  }

  CatalogViewMode _loadSavedViewMode() {
    final val = prefs?.getString('catalog_view_mode');
    return val == 'list' ? CatalogViewMode.list : CatalogViewMode.grid;
  }

  CatalogGridDensity _loadSavedGridDensity() {
    final val = prefs?.getInt('grid_columns_count') ?? prefs?.getInt('catalog_grid_density');
    return val == 3 ? CatalogGridDensity.compact : CatalogGridDensity.standard;
  }

  /// Загрузка обновлений каталога (с поддержкой pull-to-refresh)
  Future<void> loadUpdates({bool refresh = false}) async {
    if (!refresh && _initialized) return;
    _initialized = true;
    if (refresh) {
      _cache.clear();
      _pageMap.clear();
      _hasMoreMap.clear();
      _pageCache.clear();
      _tabMemoryCache.clear();
    } else if (state is CatalogLoaded && (state as CatalogLoaded).titles.length >= 12) {
      return;
    }

    final currentCategory = (state is CatalogLoaded && (state as CatalogLoaded).selectedGenres.isNotEmpty)
        ? (state as CatalogLoaded).selectedGenres.first
        : 'Все';
    _activeFilterKey = _buildFilterKey(
      genres: currentCategory == 'Все' ? const {} : {currentCategory},
      sortBy: CatalogSort.updates,
    );

    await _fetchCatalog(category: currentCategory, isLoadMore: false);
  }

  /// Выбор категории/жанра с моментальной отдачей из In-Memory кэша
  void onCategoryChanged(String? category) {
    String cleanCategory = (category == null || category.trim().isEmpty || category.trim() == 'Все')
        ? 'Все'
        : category.trim();

    // Если кликнули на уже активный жанр — сбрасываем на 'Все'
    if (state is CatalogLoaded) {
      final current = state as CatalogLoaded;
      if (cleanCategory != 'Все' &&
          current.selectedGenres.length == 1 &&
          current.selectedGenres.any((g) => g.toLowerCase() == cleanCategory.toLowerCase())) {
        cleanCategory = 'Все';
      }
    }

    final currentForKey = state is CatalogLoaded ? (state as CatalogLoaded) : null;
    final nextGenresForKey = cleanCategory == 'Все' ? const <String>{} : {cleanCategory};
    _activeFilterKey = _buildFilterKey(
      genres: nextGenresForKey,
      sortBy: currentForKey?.sortBy ?? CatalogSort.updates,
      statusFilter: currentForKey?.statusFilter,
      typeFilter: currentForKey?.typeFilter,
      matchAll: currentForKey?.matchAllGenres ?? false,
    );

    // 1. Проверяем наличие в двухуровневом кэше (In-Memory)
    final prefetched = CatalogPrefetchService.instance.getCached(cleanCategory);
    if (prefetched != null && prefetched.isNotEmpty && !_cache.containsKey(cleanCategory)) {
      _cache[cleanCategory] = prefetched;
    }

    // Если данные для этого жанра уже есть в кэше — отдаем их моментально (0ms)!
    if (_cache.containsKey(cleanCategory) && _cache[cleanCategory]!.isNotEmpty) {
      final cached = _cache[cleanCategory]!;
      _cachedUpdates = cached;
      final current = state is CatalogLoaded ? (state as CatalogLoaded) : null;
      final genres = cleanCategory == 'Все' ? const <String>{} : {cleanCategory};
      final sort = current?.sortBy ?? CatalogSort.updates;
      final statusFilter = current?.statusFilter;
      final matchAll = current?.matchAllGenres ?? false;

      final filtered = _applyFiltersAndSorting(
        cached,
        genres: genres,
        sortBy: sort,
        matchAll: matchAll,
        statusFilter: statusFilter,
      );

      emit(CatalogLoaded(
        titles: cached,
        filteredTitles: filtered,
        selectedGenres: genres,
        sortBy: sort,
        matchAllGenres: matchAll,
        statusFilter: statusFilter,
        searchQuery: '',
        isSearching: false,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: _pageMap[cleanCategory] ?? 1,
        hasMore: _hasMoreMap[cleanCategory] ?? true,
        isLoadingMore: false,
        isMangaMode: _isMangaMode,
        mangaItems: _mangaItems,
        mangaTab: _mangaTab,
        mangaRussianOnly: _mangaRussianOnly,
        isMangaLoading: _isMangaLoading,
        isMangaLoadingMore: _isMangaLoadingMore,
        hasMoreManga: _hasMoreManga,
        mangaSearchQuery: _mangaSearchQuery,
      ));
      _scheduleMangaPrefetch();

      // Если кэш устарел (> 15 минут), тихо обновляем его в фоне без сброса интерфейса
      if (CatalogPrefetchService.instance.isStale(cleanCategory)) {
        _fetchCatalog(category: cleanCategory, isLoadMore: false);
      }
      return;
    }

    // 0ms: мгновенно фильтруем локальный индекс (не смешивая с текущей лентой другого фильтра), пока API обновляется
    final genres = cleanCategory == 'Все' ? const <String>{} : {cleanCategory};
    if (state is CatalogLoaded) {
      final current = state as CatalogLoaded;
      final localSource = cleanCategory == 'Все'
          ? current.titles
          : CatalogPersistentStore.instance.queryLocal(
              genre: cleanCategory,
              status: current.statusFilter,
              type: current.typeFilter,
              sort: current.sortBy.name,
            );
      final instantFiltered = _applyFiltersAndSorting(
        localSource,
        genres: genres,
        sortBy: current.sortBy,
        matchAll: current.matchAllGenres,
        statusFilter: current.statusFilter,
        typeFilter: current.typeFilter,
      );
      emit(current.copyWith(
        selectedGenres: genres,
        searchQuery: '',
        isSearching: false,
        filteredTitles: instantFiltered,
        isLoadingMore: true,
      ));
    }

    _pageMap[cleanCategory] = 1;
    _filterDebounceTimer?.cancel();
    _resetForegroundCancelToken('Filter changed');
    _fetchCatalog(category: cleanCategory, isLoadMore: false);
  }

  Future<List<AnimeTitle>> _fetchSingleCatalogPage({
    required int page,
    required String? genreParam,
    required CatalogSort sortBy,
    required String? statusFilter,
    String? typeFilter,
    required CancelToken cancelToken,
  }) async {
    List<AnimeTitle> fetchedTitles = [];
    final useCase = getCatalogUseCase ??
        (getIt.isRegistered<GetCatalogUseCase>() ? getIt<GetCatalogUseCase>() : null);

    if (useCase != null) {
      try {
        final entities = await useCase(
          page: page,
          limit: 40,
          genres: genreParam,
          sort: sortBy.name,
          status: statusFilter,
          types: typeFilter,
          cancelToken: cancelToken,
        ).timeout(const Duration(seconds: 10));
        if (entities.isNotEmpty) {
          fetchedTitles = entities.map((e) => e.toAnimeTitle()).toList();
        }
        return fetchedTitles;
      } catch (e) {
        if (e is DioException && CancelToken.isCancel(e)) rethrow;
      }
    }

    if (fetchedTitles.isEmpty) {
      fetchedTitles = await getUpdates(page: page, limit: 40);
    }
    return fetchedTitles;
  }

  /// Загрузка данных каталога для выбранной категории (с авто-догрузкой до >= 12 карточек)
  Future<void> _fetchCatalog({
    required String category,
    required bool isLoadMore,
  }) async {
    final cleanCategory = (category.trim().isEmpty || category.trim() == 'Все') ? 'Все' : category.trim();

    if (isLoadMore) {
      if (_isLoadingMore) return;
      _isLoadingMore = true;
      if (state is CatalogLoaded) {
        emit((state as CatalogLoaded).copyWith(isLoadingMore: true));
      }
    } else {
      if (state is! CatalogLoaded) {
        final localSnapshot = CatalogPersistentStore.instance.queryLocal(
          genre: cleanCategory == 'Все' ? null : cleanCategory,
        );
        if (localSnapshot.isNotEmpty) {
          emit(CatalogLoaded(
            titles: localSnapshot,
            filteredTitles: localSnapshot,
            selectedGenres:
                cleanCategory == 'Все' ? const <String>{} : {cleanCategory},
            sortBy: CatalogSort.updates,
            matchAllGenres: false,
            statusFilter: null,
            searchQuery: '',
            isSearching: false,
            viewMode: _currentViewMode,
            gridDensity: _currentGridDensity,
            currentPage: 1,
            hasMore: true,
            isLoadingMore: true,
          ));
        } else {
          emit(const CatalogLoading());
        }
      }
    }

    final cancelToken = isLoadMore
        ? (_foregroundCancelToken != null && !_foregroundCancelToken!.isCancelled
            ? _foregroundCancelToken!
            : _resetForegroundCancelToken('Load more catalog'))
        : _resetForegroundCancelToken('New catalog fetch');
    final requestId = ++_requestId;
    final currentGeneration = ++_loadGeneration;
    final requestFilterKey = _activeFilterKey;
    int page = isLoadMore ? (_pageMap[cleanCategory] ?? 1) + 1 : 1;
    final genreParam = cleanCategory == 'Все' ? null : cleanCategory;
    final current = state is CatalogLoaded ? (state as CatalogLoaded) : null;
    final sort = current?.sortBy ?? CatalogSort.updates;
    final statusFilter = current?.statusFilter;
    final matchAll = current?.matchAllGenres ?? false;
    final genres = cleanCategory == 'Все' ? const <String>{} : {cleanCategory};

    final List<AnimeTitle> accumulated = isLoadMore
        ? List<AnimeTitle>.from(
            _cache[cleanCategory] ??
                (state is CatalogLoaded ? (state as CatalogLoaded).titles : const []),
          )
        : (cleanCategory != 'Все'
            ? CatalogPersistentStore.instance
                .queryLocal()
                .where((t) => matchesGenreOrAlias(t, cleanCategory))
                .toList()
            : <AnimeTitle>[]);
    final existingIds = accumulated.map((t) => t.id).toSet();

    final bool isFilteredQuery = genres.isNotEmpty ||
        statusFilter != null ||
        (current?.searchQuery.trim().isNotEmpty ?? false);

    try {
      bool hasMore = true;
      List<AnimeTitle> filtered = [];
      int pagesFetched = 0;
      const int maxPagesToFetch = 1;

      // Грузим строго 1 страницу на запрос; page=2+ подгружается исключительно при скролле.
      while (pagesFetched < maxPagesToFetch && hasMore) {
        final pageItems = await _fetchSingleCatalogPage(
          page: page,
          genreParam: genreParam,
          sortBy: sort,
          statusFilter: statusFilter,
          cancelToken: cancelToken,
        );

        if (requestId != _requestId ||
            requestFilterKey != _activeFilterKey ||
            cancelToken.isCancelled ||
            isClosed) {
          return;
        }

        pagesFetched++;
        hasMore = pageItems.isNotEmpty && pageItems.length >= 10;

        for (final item in pageItems) {
          if (existingIds.add(item.id)) {
            accumulated.add(item);
          }
        }

        filtered = _applyFiltersAndSorting(
          accumulated,
          genres: genres,
          sortBy: sort,
          matchAll: matchAll,
          statusFilter: statusFilter,
        );

        if (!isFilteredQuery || filtered.length >= 12 || !hasMore || pagesFetched >= maxPagesToFetch) {
          break;
        }
        page++;
      }

      if (requestId != _requestId ||
          currentGeneration != _loadGeneration ||
          requestFilterKey != _activeFilterKey ||
          cancelToken.isCancelled ||
          isClosed) {
        if (currentGeneration != _loadGeneration) {
          debugPrint('[CatalogCubit] Discarded stale response (gen=$currentGeneration, active=$_loadGeneration)');
        }
        return;
      }

      if (accumulated.isEmpty && state is CatalogLoaded && (state as CatalogLoaded).titles.isNotEmpty) {
        emit((state as CatalogLoaded).copyWith(hasMore: false, isLoadingMore: false));
        return;
      }

      final prevLoaded = state is CatalogLoaded ? (state as CatalogLoaded) : null;
      final sameVisibleScope = prevLoaded != null &&
          (prevLoaded.titles.length >= 12 || _scrollOffset > 40.0) &&
          prevLoaded.searchQuery.isEmpty &&
          prevLoaded.sortBy == sort &&
          prevLoaded.statusFilter == statusFilter &&
          prevLoaded.typeFilter == null &&
          prevLoaded.selectedGenres.length == genres.length &&
          prevLoaded.selectedGenres.containsAll(genres);

      final List<AnimeTitle> mergedTitles = (sameVisibleScope || (isLoadMore && prevLoaded != null && prevLoaded.titles.isNotEmpty))
          ? mergePreservingVisibleOrder(
              currentVisible: prevLoaded.titles,
              incoming: accumulated,
            )
          : accumulated;
      final List<AnimeTitle> mergedFiltered = _applyFiltersAndSorting(
        mergedTitles,
        genres: genres,
        sortBy: sort,
        matchAll: matchAll,
        statusFilter: statusFilter,
      );

      _cache[cleanCategory] = mergedTitles;
      _tabMemoryCache[requestFilterKey] = mergedFiltered;
      _pageMap[cleanCategory] = page;
      _hasMoreMap[cleanCategory] = hasMore;
      _cachedUpdates = mergedFiltered;

      CatalogPrefetchService.instance.putCache(cleanCategory, mergedTitles);
      unawaited(CatalogPersistentStore.instance.mergeAndPersist(mergedTitles));

      emit(CatalogLoaded(
        titles: mergedTitles,
        filteredTitles: mergedFiltered,
        selectedGenres: genres,
        sortBy: sort,
        matchAllGenres: matchAll,
        statusFilter: statusFilter,
        searchQuery: '',
        isSearching: false,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: page,
        hasMore: hasMore,
        isLoadingMore: false,
        isMangaMode: _isMangaMode,
        mangaItems: _mangaItems,
        mangaTab: _mangaTab,
        mangaRussianOnly: _mangaRussianOnly,
        isMangaLoading: _isMangaLoading,
        isMangaLoadingMore: _isMangaLoadingMore,
        hasMoreManga: _hasMoreManga,
        mangaSearchQuery: _mangaSearchQuery,
      ));
      _scheduleMangaPrefetch();
    } catch (e) {
      if (requestId != _requestId ||
          currentGeneration != _loadGeneration ||
          requestFilterKey != _activeFilterKey ||
          cancelToken.isCancelled ||
          isClosed) {
        if (currentGeneration != _loadGeneration) {
          debugPrint('[CatalogCubit] Discarded stale filtered response (gen=$currentGeneration, active=$_loadGeneration)');
        }
        return;
      }
      final localFallback = cleanCategory != 'Все'
          ? CatalogPersistentStore.instance
              .queryLocal()
              .where((t) => matchesGenreOrAlias(t, cleanCategory))
              .toList()
          : CatalogPersistentStore.instance.queryLocal();
      final combinedFallback = accumulated.isNotEmpty ? accumulated : localFallback;
      if (combinedFallback.isNotEmpty || cleanCategory != 'Все' || isFilteredQuery || state is CatalogLoaded) {
        final fallbackFiltered = _applyFiltersAndSorting(
          combinedFallback,
          genres: genres,
          sortBy: sort,
          matchAll: matchAll,
          statusFilter: statusFilter,
        );
        emit(CatalogLoaded(
          titles: combinedFallback,
          filteredTitles: fallbackFiltered,
          selectedGenres: genres,
          sortBy: sort,
          matchAllGenres: matchAll,
          statusFilter: statusFilter,
          searchQuery: '',
          isSearching: false,
          viewMode: _currentViewMode,
          gridDensity: _currentGridDensity,
          currentPage: page,
          hasMore: false,
          isLoadingMore: false,
        ));
      } else if (isLoadMore && state is CatalogLoaded) {
        emit((state as CatalogLoaded).copyWith(isLoadingMore: false));
      } else {
        emit(CatalogError(e.toString()));
      }
    } finally {
      if (isLoadMore) {
        _isLoadingMore = false;
      }
      if (!isClosed &&
          requestId == _requestId &&
          !cancelToken.isCancelled &&
          state is CatalogLoaded &&
          (state as CatalogLoaded).isLoadingMore) {
        emit((state as CatalogLoaded).copyWith(isLoadingMore: false));
      }
      if (identical(_foregroundCancelToken, cancelToken)) {
        _foregroundCancelToken = null;
      }
    }
  }

  /// Алиас для бесконечного скролла следующей страницы.
  Future<void> loadNextPage() => loadMore();

  DateTime? _lastLoadMoreAt;

  /// Подгрузка следующей страницы каталога (AniLibria API v1) с pre-fetch и cooldown 600ms
  Future<void> loadMore() async {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;
    if (_isLoadingMore || current.isLoadingMore || !current.hasMore || current.searchQuery.isNotEmpty) {
      return;
    }
    final now = DateTime.now();
    if (_lastLoadMoreAt != null &&
        now.difference(_lastLoadMoreAt!) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastLoadMoreAt = now;

    if (current.selectedGenres.length > 1 ||
        current.statusFilter != null ||
        current.typeFilter != null ||
        current.sortBy != CatalogSort.updates) {
      await _fetchFilteredCatalog(
        genres: current.selectedGenres,
        sortBy: current.sortBy,
        statusFilter: current.statusFilter,
        typeFilter: current.typeFilter,
        matchAll: current.matchAllGenres,
        isLoadMore: true,
      );
      return;
    }

    final category = current.selectedGenres.isNotEmpty ? current.selectedGenres.first : 'Все';
    await _fetchCatalog(category: category, isLoadMore: true);
  }

  static const int _mangaPageLimit = 30;
  static const int _mangaPrefetchLimit = 24;
  static final RegExp _cyrillicRegex = RegExp(r'[а-яА-ЯёЁ]');

  int _mangaPage = 1;

  static int _foregroundScreenDepth = 0;
  static bool get isBackgroundPrefetchPaused => _foregroundScreenDepth > 0;

  static void pushForegroundScreen() {
    _foregroundScreenDepth++;
  }

  static void popForegroundScreen() {
    if (_foregroundScreenDepth > 0) {
      _foregroundScreenDepth--;
    }
  }

  bool _isMangaMode = false;
  bool get isMangaMode => _isMangaMode;

  bool _mangaPrefetchScheduled = false;
  List<MangaDexManga> _mangaItems = const [];
  String _mangaTab = 'all';
  bool _mangaRussianOnly = true;
  bool _isMangaLoading = false;
  bool _isMangaLoadingMore = false;
  bool _hasMoreManga = true;
  String _mangaSearchQuery = '';
  DateTime? _lastMangaLoadMoreAt;
  int _mangaRequestGen = 0;

  MangaDexDataSource _resolveMangaDex() {
    if (mangaDexDataSource != null) return mangaDexDataSource!;
    if (getIt.isRegistered<MangaDexDataSource>()) {
      return getIt<MangaDexDataSource>();
    }
    return MangaDexDataSource();
  }

  ShikimoriRemoteDataSource? _resolveShikimori() {
    if (shikimoriRemoteDataSource != null) return shikimoriRemoteDataSource;
    if (getIt.isRegistered<ShikimoriRemoteDataSource>()) {
      return getIt<ShikimoriRemoteDataSource>();
    }
    return null;
  }

  void _emitMangaFields() {
    if (isClosed || state is! CatalogLoaded) return;
    emit((state as CatalogLoaded).copyWith(
      isMangaMode: _isMangaMode,
      mangaItems: _mangaItems,
      mangaTab: _mangaTab,
      mangaRussianOnly: _mangaRussianOnly,
      isMangaLoading: _isMangaLoading,
      isMangaLoadingMore: _isMangaLoadingMore,
      hasMoreManga: _hasMoreManga,
      mangaSearchQuery: _mangaSearchQuery,
    ));
  }

  MangaRepository _resolveMangaRepo() {
    if (mangaDexDataSource != null) {
      return MangaRepository(mangadex: mangaDexDataSource, prefs: prefs);
    }
    if (getIt.isRegistered<MangaRepository>()) {
      return getIt<MangaRepository>();
    }
    return MangaRepository.instance;
  }

  void _scheduleMangaPrefetch() {
    if (_mangaPrefetchScheduled || isClosed) return;
    _mangaPrefetchScheduled = true;
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!isClosed && !isBackgroundPrefetchPaused) {
        unawaited(_prefetchInitialMangaCatalog());
      }
    });
  }

  Future<void> _prefetchInitialMangaCatalog() async {
    if (isClosed || isBackgroundPrefetchPaused) return;
    try {
      final repo = _resolveMangaRepo();
      final cached = repo.getCachedCatalogPage(
        tab: 'all',
        page: 1,
        russianOnly: true,
      );
      if (cached != null && cached.isNotEmpty && _mangaItems.isEmpty) {
        _mangaItems = cached;
        _mangaPage = 1;
        _hasMoreManga = cached.length >= _mangaPrefetchLimit;
        _emitMangaFields();
        return;
      }

      final fetched = await repo.prefetchPage1(count: _mangaPrefetchLimit);
      if (isClosed || fetched.isEmpty) return;
      if (_mangaTab == 'all' && _mangaRussianOnly && _mangaSearchQuery.isEmpty) {
        _mangaItems = fetched;
        _mangaPage = 1;
        _hasMoreManga = fetched.length >= _mangaPrefetchLimit;
        _isMangaLoading = false;
        _emitMangaFields();
      }
    } catch (_) {}
  }

  void setMangaMode(bool value) {
    if (_isMangaMode == value) return;
    _isMangaMode = value;
    MascotCompanionService.instance.setMangaContext(value);
    _emitMangaFields();
    if (value && _mangaItems.isEmpty && !_isMangaLoading) {
      unawaited(loadMangaCatalog());
    }
  }

  void selectMangaTab(String tab) {
    if (_mangaTab == tab && _mangaItems.isNotEmpty) return;
    _mangaTab = tab;
    _hasMoreManga = true;
    unawaited(loadMangaCatalog());
  }

  void setMangaRussianOnly(bool russianOnly) {
    if (_mangaRussianOnly == russianOnly) return;
    _mangaRussianOnly = russianOnly;
    _hasMoreManga = true;
    unawaited(loadMangaCatalog());
  }

  void onMangaSearchChanged(String query) {
    _mangaSearchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _mangaSearchQuery = '';
      _hasMoreManga = true;
      unawaited(loadMangaCatalog());
      return;
    }
    _mangaSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!isClosed) {
        unawaited(searchMangaCatalog(trimmed));
      }
    });
  }

  Future<void> searchMangaCatalog(String query) async {
    final trimmed = query.trim();
    _mangaSearchQuery = trimmed;
    if (trimmed.isEmpty) {
      _hasMoreManga = true;
      await loadMangaCatalog();
      return;
    }
    final gen = ++_mangaRequestGen;
    _isMangaLoading = true;
    _isMangaLoadingMore = false;
    _hasMoreManga = false;
    _emitMangaFields();

    if (mangaDexDataSource != null) {
      final ds = _resolveMangaDex();
      final merged = <MangaDexManga>[];
      final seenIds = <String>{};
      void appendUnique(List<MangaDexManga> list) {
        for (final m in list) {
          if (seenIds.add(m.id)) merged.add(m);
        }
      }

      final primary = await ds.searchManga(trimmed, limit: _mangaPageLimit);
      appendUnique(primary);
      if (_cyrillicRegex.hasMatch(trimmed) && merged.length < 3) {
        final shiki = _resolveShikimori();
        if (shiki != null) {
          final shikiMatches = await shiki.searchMangas(trimmed, limit: 5);
          for (final match in shikiMatches.take(2)) {
            final eng = match.english.trim();
            if (eng.isEmpty) continue;
            final extra = await ds.searchManga(eng, limit: 20);
            appendUnique(extra);
          }
        }
      }
      if (isClosed || gen != _mangaRequestGen) return;
      _mangaItems = merged;
      _isMangaLoading = false;
      _hasMoreManga = false;
      _emitMangaFields();
      return;
    }

    final merged = await _resolveMangaRepo().searchManga(trimmed);
    if (isClosed || gen != _mangaRequestGen) return;
    _mangaItems = merged;
    _isMangaLoading = false;
    _hasMoreManga = false;
    _emitMangaFields();
  }

  Future<void> loadNextMangaPage() async {
    if (_isMangaLoading ||
        _isMangaLoadingMore ||
        !_hasMoreManga ||
        _mangaSearchQuery.isNotEmpty) {
      return;
    }
    final now = DateTime.now();
    if (_lastMangaLoadMoreAt != null &&
        now.difference(_lastMangaLoadMoreAt!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastMangaLoadMoreAt = now;
    await loadMangaCatalog(loadMore: true);
  }

  Future<void> loadMangaCatalog({bool loadMore = false}) async {
    if (_mangaSearchQuery.isNotEmpty && !loadMore) {
      await searchMangaCatalog(_mangaSearchQuery);
      return;
    }
    final gen = loadMore ? _mangaRequestGen : ++_mangaRequestGen;
    final nextPage = loadMore ? _mangaPage + 1 : 1;

    if (mangaDexDataSource != null) {
      final offset = loadMore ? _mangaItems.length : 0;
      if (loadMore) {
        _isMangaLoadingMore = true;
      } else {
        _isMangaLoading = _mangaItems.isEmpty;
        _isMangaLoadingMore = false;
      }
      _emitMangaFields();

      final origLang = _mangaTab == 'manhwa'
          ? 'ko'
          : (_mangaTab == 'manga' ? 'ja' : null);
      final order = _mangaTab == 'popular' ? 'rating' : 'followedCount';
      final status = _mangaTab == 'completed' ? 'completed' : null;
      final fetched = await _resolveMangaDex().browseManga(
        originalLanguage: origLang,
        availableTranslatedLanguage: _mangaRussianOnly ? 'ru' : null,
        status: status,
        order: order,
        limit: _mangaPageLimit,
        offset: offset,
      );
      if (isClosed || gen != _mangaRequestGen) return;
      if (loadMore) {
        final seenIds = _mangaItems.map((e) => e.id).toSet();
        final merged = List<MangaDexManga>.from(_mangaItems);
        for (final item in fetched) {
          if (seenIds.add(item.id)) merged.add(item);
        }
        _mangaItems = merged;
        _isMangaLoadingMore = false;
      } else {
        _mangaItems = fetched;
        _isMangaLoading = false;
      }
      _hasMoreManga = fetched.length >= _mangaPageLimit;
      _emitMangaFields();
      return;
    }

    final repo = _resolveMangaRepo();
    if (!loadMore) {
      final instant = repo.getCachedCatalogPage(
        tab: _mangaTab,
        page: 1,
        russianOnly: _mangaRussianOnly,
      );
      if (instant != null && instant.isNotEmpty) {
        _mangaItems = instant;
        _mangaPage = 1;
        _isMangaLoading = false;
        _isMangaLoadingMore = false;
        _hasMoreManga = instant.length >= _mangaPrefetchLimit;
        _emitMangaFields();
        return;
      }
    }

    if (loadMore) {
      _isMangaLoadingMore = true;
    } else {
      _isMangaLoading = _mangaItems.isEmpty;
      _isMangaLoadingMore = false;
    }
    _emitMangaFields();

    final fetched = await repo.getCatalog(
      tab: _mangaTab,
      page: nextPage,
      count: _mangaPageLimit,
      russianOnly: _mangaRussianOnly,
    );

    if (isClosed || gen != _mangaRequestGen) return;

    if (loadMore) {
      final seenIds = _mangaItems.map((e) => e.id).toSet();
      final merged = List<MangaDexManga>.from(_mangaItems);
      for (final item in fetched) {
        if (seenIds.add(item.id)) {
          merged.add(item);
        }
      }
      _mangaItems = merged;
      _mangaPage = nextPage;
      _isMangaLoadingMore = false;
      _hasMoreManga = fetched.length >= _mangaPageLimit;
    } else {
      _mangaItems = fetched;
      _mangaPage = 1;
      _isMangaLoading = false;
      _hasMoreManga = fetched.length >= _mangaPageLimit;
    }
    _emitMangaFields();
  }

  void toggleViewMode() {
    final newMode = _currentViewMode == CatalogViewMode.grid
        ? CatalogViewMode.list
        : CatalogViewMode.grid;
    setViewMode(newMode);
  }

  /// Циклическое переключение вида каталога: 2 в ряд -> 3 в ряд -> список -> 2 в ряд
  void cycleDisplayMode() {
    if (_currentViewMode == CatalogViewMode.list) {
      setViewMode(CatalogViewMode.grid);
      setGridDensity(CatalogGridDensity.standard);
    } else if (_currentGridDensity == CatalogGridDensity.standard) {
      setGridDensity(CatalogGridDensity.compact);
    } else {
      setViewMode(CatalogViewMode.list);
    }
  }

  void setViewMode(CatalogViewMode mode) {
    _currentViewMode = mode;
    prefs?.setString('catalog_view_mode', mode.name);
    if (state is CatalogLoaded) {
      emit((state as CatalogLoaded).copyWith(viewMode: mode));
    }
  }

  void setGridDensity(CatalogGridDensity density) {
    _currentGridDensity = density;
    prefs?.setInt('grid_columns_count', density.mobileColumns);
    prefs?.setInt('catalog_grid_density', density.mobileColumns);
    prefs?.setInt('saved_anime_grid_columns', density.mobileColumns);
    if (state is CatalogLoaded) {
      emit((state as CatalogLoaded).copyWith(gridDensity: density));
    }
  }

  void onSearchQueryChanged(String query) {
    _searchDebounceTimer?.cancel();
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      if (state is CatalogLoaded) {
        final current = state as CatalogLoaded;
        final filtered = _applyFiltersAndSorting(
          _cachedUpdates,
          genres: current.selectedGenres,
          sortBy: current.sortBy,
          matchAll: current.matchAllGenres,
          statusFilter: current.statusFilter,
        );
        emit(current.copyWith(
          searchQuery: '',
          isSearching: false,
          isLoadingMore: false,
          hasMore: _hasMoreMap['Все'] ?? (_cachedUpdates.length >= 10),
          filteredTitles: filtered,
          titles: _cachedUpdates,
        ));
      }
      return;
    }

    _searchDebounceTimer = Timer(const Duration(milliseconds: 800), () async {
      await performSearch(trimmed);
    });
  }

  Future<void> performSearch(String query) async {
    final requestId = ++_requestId;
    final currentGeneration = ++_loadGeneration;
    final cancelToken = _resetForegroundCancelToken('Search query');
    if (state is CatalogLoaded) {
      emit((state as CatalogLoaded).copyWith(
        isSearching: true,
        isLoadingMore: false,
        hasMore: false,
        searchQuery: query,
      ));
    } else {
      emit(const CatalogLoading());
    }

    try {
      List<AnimeTitle> results = [];
      final useCase = searchCatalogUseCase ??
          (getIt.isRegistered<SearchCatalogUseCase>() ? getIt<SearchCatalogUseCase>() : null);

      if (useCase != null) {
        try {
          final entities = await useCase(
            query,
            limit: 40,
            cancelToken: cancelToken,
          );
          if (entities.isNotEmpty) {
            results = entities.map((e) => e.toAnimeTitle()).toList();
          }
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) return;
        }
      }

      if (results.isEmpty && !cancelToken.isCancelled) {
        results = await searchTitles(query, limit: 40);
      }

      if (requestId != _requestId ||
          currentGeneration != _loadGeneration ||
          cancelToken.isCancelled ||
          isClosed) {
        if (currentGeneration != _loadGeneration) {
          debugPrint('[CatalogCubit] Discarded stale search response (gen=$currentGeneration, active=$_loadGeneration)');
        }
        return;
      }

      final current = state is CatalogLoaded ? (state as CatalogLoaded) : null;
      final genres = current?.selectedGenres ?? const {};
      final sort = current?.sortBy ?? CatalogSort.updates;
      final matchAll = current?.matchAllGenres ?? false;
      final status = current?.statusFilter;

      final filtered = _applyFiltersAndSorting(
        results,
        genres: genres,
        sortBy: sort,
        matchAll: matchAll,
        statusFilter: status,
      );

      emit(CatalogLoaded(
        titles: results,
        filteredTitles: filtered,
        selectedGenres: genres,
        sortBy: sort,
        matchAllGenres: matchAll,
        statusFilter: status,
        searchQuery: query,
        isSearching: false,
        hasMore: false,
        isLoadingMore: false,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
      ));
    } catch (e) {
      if (requestId != _requestId ||
          currentGeneration != _loadGeneration ||
          cancelToken.isCancelled ||
          isClosed) {
        if (currentGeneration != _loadGeneration) {
          debugPrint('[CatalogCubit] Discarded stale search error (gen=$currentGeneration, active=$_loadGeneration)');
        }
        return;
      }
      emit(CatalogError('Поиск не удался: $e'));
    } finally {
      if (!isClosed &&
          requestId == _requestId &&
          !cancelToken.isCancelled &&
          state is CatalogLoaded) {
        final cur = state as CatalogLoaded;
        if (cur.isSearching || cur.isLoadingMore || cur.hasMore) {
          emit(cur.copyWith(
            isSearching: false,
            isLoadingMore: false,
            hasMore: false,
          ));
        }
      }
      if (identical(_foregroundCancelToken, cancelToken)) {
        _foregroundCancelToken = null;
      }
    }
  }

  Future<void> _fetchFilteredCatalog({
    required Set<String> genres,
    required CatalogSort sortBy,
    String? statusFilter,
    String? typeFilter,
    bool matchAll = false,
    bool isLoadMore = false,
  }) async {
    final requestFilterKey = _buildFilterKey(
      genres: genres,
      sortBy: sortBy,
      statusFilter: statusFilter,
      typeFilter: typeFilter,
      matchAll: matchAll,
    );
    _activeFilterKey = requestFilterKey;

    // 0. Если это сброс на дефолт (без жанров, свежие обновления, статус Все, тип Все) и есть кэш — отдаем сразу
    if (!isLoadMore &&
        genres.isEmpty &&
        sortBy == CatalogSort.updates &&
        statusFilter == null &&
        typeFilter == null &&
        _cache.containsKey('Все') &&
        _cache['Все']!.isNotEmpty) {
      final cached = _cache['Все']!;
      _cachedUpdates = cached;
      emit(CatalogLoaded(
        titles: cached,
        filteredTitles: cached,
        selectedGenres: const {},
        sortBy: CatalogSort.updates,
        matchAllGenres: false,
        statusFilter: null,
        typeFilter: null,
        searchQuery: '',
        isSearching: false,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: _pageMap['Все'] ?? 1,
        hasMore: _hasMoreMap['Все'] ?? true,
        isLoadingMore: false,
      ));
      return;
    }

    final genreStr = _formatGenres(genres);
    final cacheKey = _buildCacheKey(
      genres: genreStr,
      sort: sortBy,
      status: statusFilter,
      type: typeFilter,
    );

    // 1. Быстрое чтение из изолированного по вкладкам In-Memory кэша (только при первичном переключении)
    final tabCached = _tabMemoryCache[requestFilterKey] ?? _pageCache[cacheKey];
    if (!isLoadMore && tabCached != null && tabCached.isNotEmpty) {
      _cachedUpdates = tabCached;
      emit(CatalogLoaded(
        titles: tabCached,
        filteredTitles: tabCached,
        selectedGenres: genres,
        sortBy: sortBy,
        matchAllGenres: matchAll,
        statusFilter: statusFilter,
        typeFilter: typeFilter,
        searchQuery: '',
        isSearching: false,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: _pageMap[cacheKey] ?? 1,
        hasMore: _hasMoreMap[cacheKey] ?? (tabCached.length >= 12),
        isLoadingMore: false,
      ));
      return;
    }

    if (isLoadMore) {
      if (_isLoadingMore) return;
      _isLoadingMore = true;
    }

    final cancelToken = isLoadMore
        ? (_foregroundCancelToken != null && !_foregroundCancelToken!.isCancelled
            ? _foregroundCancelToken!
            : _resetForegroundCancelToken('Load more filtered catalog'))
        : _resetForegroundCancelToken('Filter changed');
    final requestId = ++_requestId;
    final currentGeneration = ++_loadGeneration;

    List<AnimeTitle> queryLocalMatches() {
      if (genres.length == 1) {
        return CatalogPersistentStore.instance.queryLocal(
          genre: genres.first,
          status: statusFilter,
          type: typeFilter,
          sort: sortBy.name,
        );
      }
      final base = CatalogPersistentStore.instance.queryLocal(
        status: statusFilter,
        type: typeFilter,
        sort: sortBy.name,
        limit: 80,
      );
      if (genres.isEmpty) return base;
      return base
          .where((t) => matchAll
              ? genres.every((g) => matchesGenreOrAlias(t, g))
              : genres.any((g) => matchesGenreOrAlias(t, g)))
          .toList();
    }

    if (state is CatalogLoaded) {
      final current = state as CatalogLoaded;
      final localInstant = !isLoadMore ? queryLocalMatches() : const <AnimeTitle>[];
      // Никогда не подмешиваем элементы из предыдущей вкладки («Все») при переключении фильтра
      final instantFiltered = !isLoadMore
          ? _applyFiltersAndSorting(
              localInstant,
              genres: genres,
              sortBy: sortBy,
              matchAll: matchAll,
              statusFilter: statusFilter,
              typeFilter: typeFilter,
            )
          : current.filteredTitles;
      emit(current.copyWith(
        selectedGenres: genres,
        sortBy: sortBy,
        matchAllGenres: matchAll,
        statusFilter: statusFilter,
        clearStatusFilter: statusFilter == null,
        typeFilter: typeFilter,
        clearTypeFilter: typeFilter == null,
        searchQuery: '',
        isSearching: false,
        titles: isLoadMore ? current.titles : instantFiltered,
        filteredTitles: instantFiltered,
        isLoadingMore: true,
      ));
    } else {
      emit(const CatalogLoading());
    }

    try {
      int page = isLoadMore ? (_pageMap[cacheKey] ?? 1) + 1 : 1;
      final List<AnimeTitle> accumulated = isLoadMore
          ? List<AnimeTitle>.from(
              _tabMemoryCache[requestFilterKey] ??
                  _pageCache[cacheKey] ??
                  (state is CatalogLoaded ? (state as CatalogLoaded).titles : const []),
            )
          : <AnimeTitle>[];
      final existingIds = accumulated.map((t) => t.id).toSet();

      bool hasMore = true;
      List<AnimeTitle> filtered = [];
      int pagesFetched = 0;
      final bool isFilteredQuery =
          genres.isNotEmpty || statusFilter != null || typeFilter != null;
      final int maxPagesToFetch = (!isLoadMore && isFilteredQuery) ? 3 : 1;

      while (pagesFetched < maxPagesToFetch && hasMore) {
        final pageItems = await _fetchSingleCatalogPage(
          page: page,
          genreParam: genreStr,
          sortBy: sortBy,
          statusFilter: statusFilter,
          typeFilter: typeFilter,
          cancelToken: cancelToken,
        );

        if (requestId != _requestId ||
            requestFilterKey != _activeFilterKey ||
            cancelToken.isCancelled ||
            isClosed) {
          return;
        }

        pagesFetched++;
        hasMore = pageItems.isNotEmpty && pageItems.length >= 10;

        for (final item in pageItems) {
          if (existingIds.add(item.id)) {
            accumulated.add(item);
          }
        }

        filtered = _applyFiltersAndSorting(
          accumulated,
          genres: genres,
          sortBy: sortBy,
          matchAll: matchAll,
          statusFilter: statusFilter,
          typeFilter: typeFilter,
        );

        if (!isFilteredQuery || filtered.length >= 12 || !hasMore || pagesFetched >= maxPagesToFetch) {
          break;
        }
        page++;
      }

      if (requestId != _requestId ||
          currentGeneration != _loadGeneration ||
          requestFilterKey != _activeFilterKey ||
          cancelToken.isCancelled ||
          isClosed) {
        if (currentGeneration != _loadGeneration) {
          debugPrint('[CatalogCubit] Discarded stale filtered response (gen=$currentGeneration, active=$_loadGeneration)');
        }
        return;
      }

      final prevLoaded = state is CatalogLoaded ? (state as CatalogLoaded) : null;
      final sameVisibleScope = prevLoaded != null &&
          (prevLoaded.titles.length >= 12 || _scrollOffset > 40.0) &&
          prevLoaded.searchQuery.isEmpty &&
          prevLoaded.sortBy == sortBy &&
          prevLoaded.statusFilter == statusFilter &&
          prevLoaded.typeFilter == typeFilter &&
          prevLoaded.selectedGenres.length == genres.length &&
          prevLoaded.selectedGenres.containsAll(genres);

      final List<AnimeTitle> stableTitles =
          (sameVisibleScope || _scrollOffset > 40.0 && sameVisibleScope)
              ? mergePreservingVisibleOrder(
                  currentVisible: prevLoaded.titles,
                  incoming: accumulated,
                )
              : accumulated;
      final List<AnimeTitle> stableFiltered = _applyFiltersAndSorting(
        stableTitles,
        genres: genres,
        sortBy: sortBy,
        matchAll: matchAll,
        statusFilter: statusFilter,
        typeFilter: typeFilter,
      );

      _cachedUpdates = stableFiltered;
      _pageMap[cacheKey] = page;
      _hasMoreMap[cacheKey] = hasMore;
      if (stableFiltered.isNotEmpty) {
        _pageCache[cacheKey] = stableFiltered;
        _tabMemoryCache[requestFilterKey] = stableFiltered;
        CatalogPrefetchService.instance.putCache(cacheKey, stableFiltered);
        unawaited(CatalogPersistentStore.instance.mergeAndPersist(stableTitles));
      }

      emit(CatalogLoaded(
        titles: stableTitles,
        filteredTitles: stableFiltered,
        selectedGenres: genres,
        sortBy: sortBy,
        matchAllGenres: matchAll,
        statusFilter: statusFilter,
        typeFilter: typeFilter,
        searchQuery: '',
        isSearching: false,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: page,
        hasMore: hasMore,
        isLoadingMore: false,
        isMangaMode: _isMangaMode,
        mangaItems: _mangaItems,
        mangaTab: _mangaTab,
        mangaRussianOnly: _mangaRussianOnly,
        isMangaLoading: _isMangaLoading,
        isMangaLoadingMore: _isMangaLoadingMore,
        hasMoreManga: _hasMoreManga,
        mangaSearchQuery: _mangaSearchQuery,
      ));
      _scheduleMangaPrefetch();
    } catch (e) {
      if (requestId != _requestId ||
          currentGeneration != _loadGeneration ||
          requestFilterKey != _activeFilterKey ||
          cancelToken.isCancelled ||
          isClosed) {
        if (currentGeneration != _loadGeneration) {
          debugPrint('[CatalogCubit] Discarded stale filtered response (gen=$currentGeneration, active=$_loadGeneration)');
        }
        return;
      }
      final localFallback = queryLocalMatches();
      final fallbackFiltered = _applyFiltersAndSorting(
        localFallback,
        genres: genres,
        sortBy: sortBy,
        matchAll: matchAll,
        statusFilter: statusFilter,
        typeFilter: typeFilter,
      );
      if (isLoadMore && state is CatalogLoaded) {
        emit((state as CatalogLoaded).copyWith(isLoadingMore: false));
      } else {
        // Никогда не показываем CatalogError при переключении вкладок/жанров:
        // отдаем локальный кэш или пустой список с кнопкой «Сбросить фильтры».
        emit(CatalogLoaded(
          titles: localFallback,
          filteredTitles: fallbackFiltered,
          selectedGenres: genres,
          sortBy: sortBy,
          matchAllGenres: matchAll,
          statusFilter: statusFilter,
          typeFilter: typeFilter,
          searchQuery: '',
          isSearching: false,
          viewMode: _currentViewMode,
          gridDensity: _currentGridDensity,
          currentPage: 1,
          hasMore: false,
          isLoadingMore: false,
        ));
      }
    } finally {
      if (isLoadMore) {
        _isLoadingMore = false;
      }
      if (!isClosed &&
          requestId == _requestId &&
          !cancelToken.isCancelled &&
          state is CatalogLoaded &&
          (state as CatalogLoaded).isLoadingMore) {
        emit((state as CatalogLoaded).copyWith(isLoadingMore: false));
      }
      if (identical(_foregroundCancelToken, cancelToken)) {
        _foregroundCancelToken = null;
      }
    }
  }

  /// Переключение конкретного жанра в мульти-выборе
  void toggleGenre(String genre) {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;

    final nextGenres = Set<String>.from(current.selectedGenres);
    if (nextGenres.contains(genre)) {
      nextGenres.remove(genre);
    } else {
      nextGenres.add(genre);
    }

    if (current.searchQuery.isNotEmpty) {
      final filtered = _applyFiltersAndSorting(
        current.titles,
        genres: nextGenres,
        sortBy: current.sortBy,
        matchAll: current.matchAllGenres,
        statusFilter: current.statusFilter,
      );
      emit(current.copyWith(
        selectedGenres: nextGenres,
        filteredTitles: filtered,
      ));
    } else {
      _fetchFilteredCatalog(
        genres: nextGenres,
        sortBy: current.sortBy,
        statusFilter: current.statusFilter,
        typeFilter: current.typeFilter,
        matchAll: current.matchAllGenres,
      );
    }
  }

  /// Быстрое переключение вкладок каталога (Все / Онгоинги / Популярное / Завершённые / Фильмы / Анонсы / Расписание)
  void selectQuickTab(String tabId) {
    if (tabId == 'anons' || tabId == 'schedule') {
      final source = quickTabSources[tabId];
      if (source != null) {
        unawaited(loadSource(source, page: 1, refresh: true));
      }
      return;
    }

    CatalogSort sort = CatalogSort.updates;
    String? statusFilter;
    String? typeFilter;

    switch (tabId) {
      case 'ongoing':
        statusFilter = 'ongoing';
        break;
      case 'popular':
        sort = CatalogSort.rating;
        break;
      case 'released':
        statusFilter = 'released';
        break;
      case 'movies':
        typeFilter = 'MOVIE';
        sort = CatalogSort.rating;
        break;
      case 'all':
      default:
        break;
    }

    _fetchFilteredCatalog(
      genres: const {},
      sortBy: sort,
      statusFilter: statusFilter,
      typeFilter: typeFilter,
      matchAll: false,
    );
  }

  /// Полный сброс всех фильтров (жанры, статус, формат, сортировка, поиск) к вкладке «Все»
  void resetAllFilters() {
    selectQuickTab('all');
  }

  /// Единовременное пакетное применение всех параметров фильтрации из шторки (Filter Sheet)
  void applyFilterSheet({
    required Set<String> genres,
    required CatalogSort sortBy,
    required bool matchAll,
    String? statusFilter,
    String? typeFilter,
  }) {
    if (state is! CatalogLoaded) return;
    final cleanGenres = genres
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty && g.toLowerCase() != 'все')
        .toSet();

    _fetchFilteredCatalog(
      genres: cleanGenres,
      sortBy: sortBy,
      statusFilter: statusFilter,
      typeFilter: typeFilter,
      matchAll: matchAll,
    );
  }

  /// Одиночный выбор жанра (для совместимости)
  void selectGenre(String? genre) => onCategoryChanged(genre);

  /// Очистить все фильтры жанров
  void clearGenres() => onCategoryChanged('Все');

  /// Установить сортировку каталога
  void setSortBy(CatalogSort sort) {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;

    if (current.searchQuery.isNotEmpty) {
      final filtered = _applyFiltersAndSorting(
        current.titles,
        genres: current.selectedGenres,
        sortBy: sort,
        matchAll: current.matchAllGenres,
        statusFilter: current.statusFilter,
        typeFilter: current.typeFilter,
      );
      emit(current.copyWith(
        sortBy: sort,
        filteredTitles: filtered,
      ));
    } else {
      _fetchFilteredCatalog(
        genres: current.selectedGenres,
        sortBy: sort,
        statusFilter: current.statusFilter,
        typeFilter: current.typeFilter,
        matchAll: current.matchAllGenres,
      );
    }
  }

  /// Переключить режим совпадения: все выбранные жанры или хотя бы один
  void setMatchAllGenres(bool matchAll) {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;

    final filtered = _applyFiltersAndSorting(
      current.titles,
      genres: current.selectedGenres,
      sortBy: current.sortBy,
      matchAll: matchAll,
      statusFilter: current.statusFilter,
      typeFilter: current.typeFilter,
    );

    emit(current.copyWith(
      matchAllGenres: matchAll,
      filteredTitles: filtered,
    ));
  }

  /// Установить фильтр статуса: 'ongoing', 'released', 'anons' или null
  void setStatusFilter(String? status) {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;

    if (current.searchQuery.isNotEmpty) {
      final filtered = _applyFiltersAndSorting(
        current.titles,
        genres: current.selectedGenres,
        sortBy: current.sortBy,
        matchAll: current.matchAllGenres,
        statusFilter: status,
        typeFilter: current.typeFilter,
      );
      emit(current.copyWith(
        statusFilter: status,
        clearStatusFilter: status == null,
        filteredTitles: filtered,
      ));
    } else {
      _fetchFilteredCatalog(
        genres: current.selectedGenres,
        sortBy: current.sortBy,
        statusFilter: status,
        typeFilter: current.typeFilter,
        matchAll: current.matchAllGenres,
      );
    }
  }

  /// Гибридная проверка жанра/тега по жанрам, описанию и алиасам (Сёнен, Сэйнэн, Исекай, Школа, Мистика).
  static bool matchesGenreOrAlias(AnimeTitle title, String rawGenre) {
    String norm(String s) => s.toLowerCase().replaceAll('ё', 'е').replaceAll('-', ' ').trim();
    final g = norm(rawGenre);
    if (g.isEmpty || g == 'все') return true;

    final titleGenres = title.genres.map(norm).toList();
    final desc = norm(title.description);

    const aliases = <String, List<String>>{
      'сенен': ['сенен', 'shounen', 'shonen'],
      'сэйнэн': ['сэйнэн', 'сейнен', 'seinen'],
      'сейнен': ['сэйнэн', 'сейнен', 'seinen'],
      'седзе': ['седзе', 'shoujo', 'романтика', 'драма'],
      'дзесей': ['дзесей', 'josei', 'драма', 'повседневность'],
      'исекай': ['исекай', 'isekai', 'другой мир', 'перерожд'],
      'школа': ['школа', 'школьн', 'академ'],
      'мистика': ['мистика', 'сверхъестеств', 'призрак', 'демон'],
      'психология': ['психология', 'психологическое'],
      'психологическое': ['психология', 'психологическое'],
    };

    if (g == 'сенен') {
      final hasAction = titleGenres.any((tg) => tg.contains('экшен') || tg.contains('экшн'));
      final hasBattleBuddy = titleGenres.any((tg) =>
          tg.contains('приключения') ||
          tg.contains('сверхъестеств') ||
          tg.contains('боевые искусства') ||
          tg.contains('фэнтези') ||
          tg.contains('магия') ||
          tg.contains('демон') ||
          tg.contains('супер'));
      if (hasAction && hasBattleBuddy) {
        return true;
      }
    }

    final keywords = aliases[g] ?? [g];
    for (final kw in keywords) {
      if (titleGenres.any((tg) => tg.contains(kw) || kw.contains(tg))) {
        return true;
      }
      if (desc.isNotEmpty && desc.contains(kw)) {
        return true;
      }
    }
    return false;
  }

  /// Комплексный движок фильтрации и сортировки
  List<AnimeTitle> _applyFiltersAndSorting(
    List<AnimeTitle> list, {
    required Set<String> genres,
    required CatalogSort sortBy,
    required bool matchAll,
    String? statusFilter,
    String? typeFilter,
  }) {
    var result = List<AnimeTitle>.from(list);

    String norm(String s) => s.toLowerCase().replaceAll('ё', 'е').replaceAll('-', ' ').trim();

    // 1. Фильтр по жанрам (с учётом алиасов и ключевых слов для демографических тегов)
    if (genres.isNotEmpty) {
      final cleanGenres = genres.map(norm).toSet();
      result = result.where((title) {
        if (title.genres.isEmpty && title.description.isEmpty) {
          // Если у тайтла нет локальных жанров и описания, доверяем серверному ответу AniLibria
          return true;
        }
        if (matchAll) {
          return cleanGenres.every((sg) => matchesGenreOrAlias(title, sg));
        } else {
          return cleanGenres.any((sg) => matchesGenreOrAlias(title, sg));
        }
      }).toList();
    }

    // 2. Строгий фильтр по формату (Фильмы)
    if (typeFilter != null && typeFilter.isNotEmpty) {
      final wanted = typeFilter.trim().toLowerCase();
      result = result.where((t) {
        final kind = (t.kind ?? '').trim().toLowerCase();
        if (kind.isEmpty) return false;
        if (wanted == 'movie') {
          return kind == 'movie' ||
              kind.contains('movie') ||
              kind.contains('фильм');
        }
        return kind == wanted || kind.contains(wanted);
      }).toList();
    }

    // 3. Строгий фильтр по статусу
    if (statusFilter != null && statusFilter.isNotEmpty) {
      bool isOngoingTitle(AnimeTitle t) {
        final s = t.status.toLowerCase();
        return s.contains('онгоинг') ||
            s.contains('выходит') ||
            s.contains('ongoing') ||
            s.contains('в работе') ||
            s.contains('процесс');
      }

      bool isAnnouncedTitle(AnimeTitle t) {
        final s = t.status.toLowerCase();
        return s.contains('анонс') ||
            s.contains('anons') ||
            s.contains('скоро') ||
            s.contains('in_production');
      }

      if (statusFilter == 'ongoing') {
        result = result
            .where((t) => isOngoingTitle(t) && !isAnnouncedTitle(t))
            .toList();
      } else if (statusFilter == 'released') {
        result = result
            .where((t) => !isOngoingTitle(t) && !isAnnouncedTitle(t))
            .toList();
      } else if (statusFilter == 'anons' || statusFilter == 'anonses') {
        result = result
            .where((t) =>
                isAnnouncedTitle(t) ||
                (t.episodes.isEmpty && (t.episodesTotal ?? 0) == 0))
            .toList();
      }
    }

    // 4. Сортировка
    switch (sortBy) {
      case CatalogSort.updates:
        // Сохраняем порядок обновлений AniLibria
        break;
      case CatalogSort.yearDesc:
        result.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        break;
      case CatalogSort.yearAsc:
        result.sort((a, b) {
          final yA = a.year ?? 9999;
          final yB = b.year ?? 9999;
          return yA.compareTo(yB);
        });
        break;
      case CatalogSort.episodes:
        result.sort((a, b) {
          final epA = a.latestEpisode ?? a.episodesTotal ?? 0;
          final epB = b.latestEpisode ?? b.episodesTotal ?? 0;
          return epB.compareTo(epA);
        });
        break;
      case CatalogSort.rating:
        // Если оценки заполнены (например, из кэша/Shikimori), сортируем по рейтингу; иначе сохраняем RATING_DESC порядок сервера
        final hasScores = result.any((t) => (t.score ?? 0) > 0);
        if (hasScores) {
          result.sort((a, b) {
            final cmp = (b.score ?? 0).compareTo(a.score ?? 0);
            if (cmp != 0) return cmp;
            final scA = (a.episodes.length * 10) + (a.episodesTotal ?? 0);
            final scB = (b.episodes.length * 10) + (b.episodesTotal ?? 0);
            return scB.compareTo(scA);
          });
        }
        break;
      case CatalogSort.alphabetical:
        result.sort((a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        break;
    }

    return result;
  }

  @override
  Future<void> close() {
    _loadGeneration = -1;
    for (final token in _inFlight.values) {
      if (!token.isCancelled) {
        token.cancel('CatalogCubit closed');
      }
    }
    _inFlight.clear();
    _inFlightFutures.clear();
    _searchDebounceTimer?.cancel();
    _filterDebounceTimer?.cancel();
    _mangaSearchDebounce?.cancel();
    if (_foregroundCancelToken != null && !_foregroundCancelToken!.isCancelled) {
      _foregroundCancelToken!.cancel('Cubit closed');
    }
    _foregroundCancelToken = null;
    return super.close();
  }
}
