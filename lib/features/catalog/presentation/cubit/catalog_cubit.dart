import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/di/injection.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/entities/catalog_settings.dart';
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

  Timer? _searchDebounceTimer;
  Timer? _filterDebounceTimer;
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
  int _requestId = 0;
  late CatalogViewMode _currentViewMode;
  late CatalogGridDensity _currentGridDensity;

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
  }) {
    return '${genres ?? "all"}_${sort.name}_${status ?? "all"}';
  }

  CatalogCubit({
    required this.getUpdates,
    required this.searchTitles,
    this.prefs,
    this.getCatalogUseCase,
    this.searchCatalogUseCase,
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
    if (refresh) {
      _cache.clear();
      _pageMap.clear();
      _hasMoreMap.clear();
      _pageCache.clear();
    } else if (state is CatalogLoaded && (state as CatalogLoaded).titles.isNotEmpty) {
      return;
    }

    final currentCategory = (state is CatalogLoaded && (state as CatalogLoaded).selectedGenres.isNotEmpty)
        ? (state as CatalogLoaded).selectedGenres.first
        : 'Все';

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

    // 1. Проверяем наличие в двухуровневом сервисе предзагрузки (In-Memory + Disk)
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
      ));

      // Если кэш устарел (> 15 минут), тихо обновляем его в фоне без сброса интерфейса
      if (CatalogPrefetchService.instance.isStale(cleanCategory)) {
        _fetchCatalog(category: cleanCategory, isLoadMore: false);
      }
      return;
    }

    // 0ms: мгновенно фильтруем уже загруженный кэш в памяти, пока API обновляется
    final genres = cleanCategory == 'Все' ? const <String>{} : {cleanCategory};
    if (state is CatalogLoaded) {
      final current = state as CatalogLoaded;
      final instantFiltered = _applyFiltersAndSorting(
        current.titles,
        genres: genres,
        sortBy: current.sortBy,
        matchAll: current.matchAllGenres,
        statusFilter: current.statusFilter,
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
    int page = isLoadMore ? (_pageMap[cleanCategory] ?? 1) + 1 : 1;
    final genreParam = cleanCategory == 'Все' ? null : cleanCategory;
    final current = state is CatalogLoaded ? (state as CatalogLoaded) : null;
    final sort = current?.sortBy ?? CatalogSort.updates;
    final statusFilter = current?.statusFilter;
    final matchAll = current?.matchAllGenres ?? false;
    final genres = cleanCategory == 'Все' ? const <String>{} : {cleanCategory};

    final List<AnimeTitle> accumulated = isLoadMore
        ? List<AnimeTitle>.from(_cache[cleanCategory] ?? [])
        : (cleanCategory != 'Все'
            ? CatalogPersistentStore.instance
                .queryLocal()
                .where((t) => matchesGenreOrAlias(t, cleanCategory))
                .toList()
            : <AnimeTitle>[]);
    final existingIds = accumulated.map((t) => t.id).toSet();

    try {

      bool hasMore = true;
      List<AnimeTitle> filtered = [];
      int pagesFetched = 0;
      final bool isFilteredQuery = genres.isNotEmpty ||
          statusFilter != null ||
          (current?.searchQuery.trim().isNotEmpty ?? false);
      final int maxPagesToFetch = (!isLoadMore && isFilteredQuery) ? 3 : 1;

      // Auto-Fill Viewport Loop: только когда активен фильтр жанра/статуса/поиска и после фильтрации < 12 карточек,
      // автоматически подгружаем следующие страницы (до 3 страниц подряд).
      // Для дефолтной вкладки «Все» без фильтрации грузим строго 1 страницу (page = 1, limit = 40).
      while (pagesFetched < maxPagesToFetch && hasMore) {
        final pageItems = await _fetchSingleCatalogPage(
          page: page,
          genreParam: genreParam,
          sortBy: sort,
          statusFilter: statusFilter,
          cancelToken: cancelToken,
        );

        if (requestId != _requestId || cancelToken.isCancelled) return;

        pagesFetched++;
        hasMore = pageItems.length >= 10;

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

      if (requestId != _requestId || cancelToken.isCancelled) return;

      _cache[cleanCategory] = accumulated;
      _pageMap[cleanCategory] = page;
      _hasMoreMap[cleanCategory] = hasMore;
      _cachedUpdates = filtered;

      CatalogPrefetchService.instance.putCache(cleanCategory, accumulated);
      unawaited(CatalogPersistentStore.instance.mergeAndPersist(accumulated));
      CatalogPrefetchService.instance.startPrefetchQueue();

      emit(CatalogLoaded(
        titles: accumulated,
        filteredTitles: filtered,
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
      ));
    } catch (e) {
      if (requestId != _requestId || cancelToken.isCancelled) return;
      final localFallback = cleanCategory != 'Все'
          ? CatalogPersistentStore.instance
              .queryLocal()
              .where((t) => matchesGenreOrAlias(t, cleanCategory))
              .toList()
          : CatalogPersistentStore.instance.queryLocal();
      final combinedFallback = accumulated.isNotEmpty ? accumulated : localFallback;
      if (combinedFallback.isNotEmpty) {
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
      if (identical(_foregroundCancelToken, cancelToken)) {
        _foregroundCancelToken = null;
      }
    }
  }

  /// Подгрузка следующей страницы каталога (AniLibria API v1) с pre-fetch
  Future<void> loadMore() async {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;
    if (_isLoadingMore || current.isLoadingMore || !current.hasMore || current.searchQuery.isNotEmpty) {
      return;
    }

    if (current.selectedGenres.length > 1 || current.statusFilter != null) {
      await _fetchFilteredCatalog(
        genres: current.selectedGenres,
        sortBy: current.sortBy,
        statusFilter: current.statusFilter,
        matchAll: current.matchAllGenres,
        isLoadMore: true,
      );
      return;
    }

    final category = current.selectedGenres.isNotEmpty ? current.selectedGenres.first : 'Все';
    await _fetchCatalog(category: category, isLoadMore: true);
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
    final cancelToken = _resetForegroundCancelToken('Search query');
    if (state is CatalogLoaded) {
      emit((state as CatalogLoaded).copyWith(isSearching: true, searchQuery: query));
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

      if (requestId != _requestId || cancelToken.isCancelled) return;

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
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
      ));
    } catch (e) {
      if (requestId != _requestId) return;
      emit(CatalogError('Поиск не удался: $e'));
    }
  }

  Future<void> _fetchFilteredCatalog({
    required Set<String> genres,
    required CatalogSort sortBy,
    String? statusFilter,
    bool matchAll = false,
    bool isLoadMore = false,
  }) async {
    // 0. Если это сброс на дефолт (без жанров, свежие обновления, статус Все) и есть кэш — отдаем сразу
    if (!isLoadMore &&
        genres.isEmpty &&
        sortBy == CatalogSort.updates &&
        statusFilter == null &&
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
    final cacheKey = _buildCacheKey(genres: genreStr, sort: sortBy, status: statusFilter);

    // 1. Быстрое чтение из In-Memory кэша (только при первичном переключении)
    if (!isLoadMore && _pageCache.containsKey(cacheKey) && _pageCache[cacheKey]!.isNotEmpty) {
      final cached = _pageCache[cacheKey]!;
      _cachedUpdates = cached;
      emit(CatalogLoaded(
        titles: cached,
        filteredTitles: cached,
        selectedGenres: genres,
        sortBy: sortBy,
        matchAllGenres: matchAll,
        statusFilter: statusFilter,
        searchQuery: '',
        isSearching: false,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: _pageMap[cacheKey] ?? 1,
        hasMore: _hasMoreMap[cacheKey] ?? (cached.length >= 12),
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
    if (state is CatalogLoaded) {
      final current = state as CatalogLoaded;
      final instantFiltered = !isLoadMore
          ? _applyFiltersAndSorting(
              current.titles,
              genres: genres,
              sortBy: sortBy,
              matchAll: matchAll,
              statusFilter: statusFilter,
            )
          : current.filteredTitles;
      emit(current.copyWith(
        selectedGenres: genres,
        sortBy: sortBy,
        matchAllGenres: matchAll,
        statusFilter: statusFilter,
        clearStatusFilter: statusFilter == null,
        filteredTitles: instantFiltered,
        isLoadingMore: true,
      ));
    } else {
      emit(const CatalogLoading());
    }

    try {
      int page = isLoadMore ? (_pageMap[cacheKey] ?? 1) + 1 : 1;
      final List<AnimeTitle> accumulated = isLoadMore
          ? List<AnimeTitle>.from(_pageCache[cacheKey] ?? [])
          : (genres.isNotEmpty
              ? CatalogPersistentStore.instance
                  .queryLocal()
                  .where((t) => matchAll
                      ? genres.every((g) => matchesGenreOrAlias(t, g))
                      : genres.any((g) => matchesGenreOrAlias(t, g)))
                  .toList()
              : CatalogPersistentStore.instance.queryLocal());
      final existingIds = accumulated.map((t) => t.id).toSet();

      bool hasMore = true;
      List<AnimeTitle> filtered = [];
      int pagesFetched = 0;
      final bool isFilteredQuery = genres.isNotEmpty || statusFilter != null;
      final int maxPagesToFetch = (!isLoadMore && isFilteredQuery) ? 3 : 1;

      while (pagesFetched < maxPagesToFetch && hasMore) {
        final pageItems = await _fetchSingleCatalogPage(
          page: page,
          genreParam: genreStr,
          sortBy: sortBy,
          statusFilter: statusFilter,
          cancelToken: cancelToken,
        );

        if (requestId != _requestId || cancelToken.isCancelled) return;

        pagesFetched++;
        hasMore = pageItems.length >= 10;

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
        );

        if (!isFilteredQuery || filtered.length >= 12 || !hasMore || pagesFetched >= maxPagesToFetch) {
          break;
        }
        page++;
      }

      if (requestId != _requestId || cancelToken.isCancelled) return;

      _cachedUpdates = filtered;
      _pageMap[cacheKey] = page;
      _hasMoreMap[cacheKey] = hasMore;
      if (filtered.isNotEmpty) {
        _pageCache[cacheKey] = filtered;
        CatalogPrefetchService.instance.putCache(cacheKey, filtered);
      }

      emit(CatalogLoaded(
        titles: accumulated,
        filteredTitles: filtered,
        selectedGenres: genres,
        sortBy: sortBy,
        matchAllGenres: matchAll,
        statusFilter: statusFilter,
        searchQuery: '',
        isSearching: false,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: page,
        hasMore: hasMore,
        isLoadingMore: false,
      ));
    } catch (e) {
      if (requestId != _requestId || cancelToken.isCancelled) return;
      final localFallback = genres.isNotEmpty
          ? CatalogPersistentStore.instance
              .queryLocal()
              .where((t) => matchAll
                  ? genres.every((g) => matchesGenreOrAlias(t, g))
                  : genres.any((g) => matchesGenreOrAlias(t, g)))
              .toList()
          : CatalogPersistentStore.instance.queryLocal();
      if (localFallback.isNotEmpty) {
        final fallbackFiltered = _applyFiltersAndSorting(
          localFallback,
          genres: genres,
          sortBy: sortBy,
          matchAll: matchAll,
          statusFilter: statusFilter,
        );
        emit(CatalogLoaded(
          titles: localFallback,
          filteredTitles: fallbackFiltered,
          selectedGenres: genres,
          sortBy: sortBy,
          matchAllGenres: matchAll,
          statusFilter: statusFilter,
          searchQuery: '',
          isSearching: false,
          viewMode: _currentViewMode,
          gridDensity: _currentGridDensity,
          currentPage: 1,
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
        matchAll: current.matchAllGenres,
      );
    }
  }

  /// Единовременное пакетное применение всех параметров фильтрации из шторки (Filter Sheet)
  void applyFilterSheet({
    required Set<String> genres,
    required CatalogSort sortBy,
    required bool matchAll,
    String? statusFilter,
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
      );
      emit(current.copyWith(
        sortBy: sort,
        filteredTitles: filtered,
      ));
    } else {
      // Моментальная выдача из кэша для «Популярное» (рейтинг)
      if (sort == CatalogSort.rating && current.selectedGenres.isEmpty && current.statusFilter == null) {
        final cached = CatalogPrefetchService.instance.getCached('popular');
        if (cached != null && cached.isNotEmpty) {
          emit(current.copyWith(
            sortBy: sort,
            filteredTitles: cached,
            titles: cached,
          ));
          if (CatalogPrefetchService.instance.isStale('popular')) {
            _fetchFilteredCatalog(
              genres: current.selectedGenres,
              sortBy: sort,
              statusFilter: current.statusFilter,
              matchAll: current.matchAllGenres,
            );
          }
          return;
        }
      }

      _fetchFilteredCatalog(
        genres: current.selectedGenres,
        sortBy: sort,
        statusFilter: current.statusFilter,
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
    );

    emit(current.copyWith(
      matchAllGenres: matchAll,
      filteredTitles: filtered,
    ));
  }

  /// Установить фильтр статуса: 'ongoing', 'released' или null
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
      );
      emit(current.copyWith(
        statusFilter: status,
        clearStatusFilter: status == null,
        filteredTitles: filtered,
      ));
    } else {
      // Моментальная выдача из кэша для онгоингов
      if (status == 'ongoing' && current.selectedGenres.isEmpty && current.sortBy == CatalogSort.updates) {
        final cached = CatalogPrefetchService.instance.getCached('ongoing');
        if (cached != null && cached.isNotEmpty) {
          emit(current.copyWith(
            statusFilter: status,
            filteredTitles: cached,
            titles: cached,
          ));
          if (CatalogPrefetchService.instance.isStale('ongoing')) {
            _fetchFilteredCatalog(
              genres: current.selectedGenres,
              sortBy: current.sortBy,
              statusFilter: status,
              matchAll: current.matchAllGenres,
            );
          }
          return;
        }
      }

      _fetchFilteredCatalog(
        genres: current.selectedGenres,
        sortBy: current.sortBy,
        statusFilter: status,
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

    // 2. Фильтр по статусу
    if (statusFilter != null && statusFilter.isNotEmpty) {
      if (statusFilter == 'ongoing') {
        result = result.where((t) {
          final s = t.status.toLowerCase();
          return s.contains('онгоинг') || s.contains('выходит') || s.contains('ongoing') || s.contains('процесс');
        }).toList();
      } else if (statusFilter == 'released') {
        result = result.where((t) {
          final s = t.status.toLowerCase();
          return s.contains('завершен') || s.contains('вышел') || s.contains('released') || s.contains('completed');
        }).toList();
      } else if (statusFilter == 'anons' || statusFilter == 'anonses') {
        result = result.where((t) {
          final s = t.status.toLowerCase();
          return s.contains('анонс') || s.contains('anons') || s.contains('скоро') || (t.episodes.isEmpty && (t.episodesTotal ?? 0) == 0);
        }).toList();
      }
    }

    // 3. Сортировка
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
        // Сортировка по количеству серий и полноте франшизы
        result.sort((a, b) {
          final scA = (a.episodes.length * 10) + (a.episodesTotal ?? 0);
          final scB = (b.episodes.length * 10) + (b.episodesTotal ?? 0);
          return scB.compareTo(scA);
        });
        break;
      case CatalogSort.alphabetical:
        result.sort((a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        break;
    }

    return result;
  }

  @override
  Future<void> close() {
    _searchDebounceTimer?.cancel();
    _filterDebounceTimer?.cancel();
    if (_foregroundCancelToken != null && !_foregroundCancelToken!.isCancelled) {
      _foregroundCancelToken!.cancel('Cubit closed');
    }
    _foregroundCancelToken = null;
    return super.close();
  }
}
