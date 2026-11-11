import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/di/injection.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/entities/catalog_settings.dart';
import '../../domain/usecases/get_catalog_usecase.dart';
import '../../domain/usecases/get_updates.dart';
import '../../domain/usecases/search_catalog_usecase.dart';
import '../../domain/usecases/search_titles.dart';
import 'catalog_state.dart';

class CatalogCubit extends Cubit<CatalogState> {
  final GetUpdates getUpdates;
  final SearchTitles searchTitles;
  final SharedPreferences? prefs;
  final GetCatalogUseCase? getCatalogUseCase;
  final SearchCatalogUseCase? searchCatalogUseCase;

  Timer? _searchDebounceTimer;
  List<AnimeTitle> _cachedUpdates = [];

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
          current.selectedGenres.contains(cleanCategory)) {
        cleanCategory = 'Все';
      }
    }

    // Если данные для этого жанра уже есть в кэше — отдаем их моментально!
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
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: _pageMap[cleanCategory] ?? 1,
        hasMore: _hasMoreMap[cleanCategory] ?? true,
        isLoadingMore: false,
      ));
      return;
    }

    // Если нет — грузим первую страницу
    _pageMap[cleanCategory] = 1;
    _fetchCatalog(category: cleanCategory, isLoadMore: false);
  }

  /// Загрузка данных каталога для выбранной категории
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
      emit(const CatalogLoading());
    }

    final requestId = ++_requestId;
    try {
      final page = isLoadMore ? (_pageMap[cleanCategory] ?? 1) + 1 : 1;
      final genreParam = cleanCategory == 'Все' ? null : cleanCategory;

      List<AnimeTitle> fetchedTitles = [];
      final useCase = getCatalogUseCase ??
          (getIt.isRegistered<GetCatalogUseCase>() ? getIt<GetCatalogUseCase>() : null);

      if (useCase != null) {
        try {
          final entities = await useCase(
            page: page,
            limit: 40,
            genres: genreParam,
          );
          if (entities.isNotEmpty) {
            fetchedTitles = entities.map((e) => e.toAnimeTitle()).toList();
          }
        } catch (_) {}
      }

      if (fetchedTitles.isEmpty) {
        fetchedTitles = await getUpdates(page: page, limit: 40);
      }

      if (requestId != _requestId) return;

      final current = state is CatalogLoaded ? (state as CatalogLoaded) : null;
      final sort = current?.sortBy ?? CatalogSort.updates;
      final statusFilter = current?.statusFilter;
      final matchAll = current?.matchAllGenres ?? false;
      final genres = cleanCategory == 'Все' ? const <String>{} : {cleanCategory};

      if (isLoadMore) {
        final existingList = _cache[cleanCategory] ?? [];
        final existingIds = existingList.map((t) => t.id).toSet();
        final unique = fetchedTitles.where((t) => !existingIds.contains(t.id)).toList();

        final combined = List<AnimeTitle>.from(existingList)..addAll(unique);
        _cache[cleanCategory] = combined;
        _pageMap[cleanCategory] = page;
        _hasMoreMap[cleanCategory] = fetchedTitles.length >= 10;

        final filtered = _applyFiltersAndSorting(
          combined,
          genres: genres,
          sortBy: sort,
          matchAll: matchAll,
          statusFilter: statusFilter,
        );
        _cachedUpdates = filtered;

        emit(CatalogLoaded(
          titles: combined,
          filteredTitles: filtered,
          selectedGenres: genres,
          sortBy: sort,
          matchAllGenres: matchAll,
          statusFilter: statusFilter,
          viewMode: _currentViewMode,
          gridDensity: _currentGridDensity,
          currentPage: page,
          hasMore: _hasMoreMap[cleanCategory] ?? false,
          isLoadingMore: false,
        ));
      } else {
        _cache[cleanCategory] = fetchedTitles;
        _pageMap[cleanCategory] = 1;
        _hasMoreMap[cleanCategory] = fetchedTitles.length >= 15;

        final filtered = _applyFiltersAndSorting(
          fetchedTitles,
          genres: genres,
          sortBy: sort,
          matchAll: matchAll,
          statusFilter: statusFilter,
        );
        _cachedUpdates = filtered;

        emit(CatalogLoaded(
          titles: fetchedTitles,
          filteredTitles: filtered,
          selectedGenres: genres,
          sortBy: sort,
          matchAllGenres: matchAll,
          statusFilter: statusFilter,
          viewMode: _currentViewMode,
          gridDensity: _currentGridDensity,
          currentPage: 1,
          hasMore: _hasMoreMap[cleanCategory] ?? false,
          isLoadingMore: false,
        ));
      }
    } catch (e) {
      if (requestId != _requestId) return;
      if (isLoadMore && state is CatalogLoaded) {
        emit((state as CatalogLoaded).copyWith(isLoadingMore: false));
      } else {
        emit(CatalogError(e.toString()));
      }
    } finally {
      if (isLoadMore) {
        _isLoadingMore = false;
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

    final category = current.selectedGenres.isNotEmpty ? current.selectedGenres.first : 'Все';
    await _fetchCatalog(category: category, isLoadMore: true);
  }

  void toggleViewMode() {
    final newMode = _currentViewMode == CatalogViewMode.grid
        ? CatalogViewMode.list
        : CatalogViewMode.grid;
    setViewMode(newMode);
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

    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
      await performSearch(trimmed);
    });
  }

  Future<void> performSearch(String query) async {
    final requestId = ++_requestId;
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
          final entities = await useCase(query, limit: 40);
          if (entities.isNotEmpty) {
            results = entities.map((e) => e.toAnimeTitle()).toList();
          }
        } catch (_) {}
      }

      if (results.isEmpty) {
        results = await searchTitles(query, limit: 40);
      }

      if (requestId != _requestId) return;

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
  }) async {
    final genreStr = _formatGenres(genres);
    final cacheKey = _buildCacheKey(genres: genreStr, sort: sortBy, status: statusFilter);

    // 1. Быстрое чтение из In-Memory кэша
    if (_pageCache.containsKey(cacheKey) && _pageCache[cacheKey]!.isNotEmpty) {
      final cached = _pageCache[cacheKey]!;
      _cachedUpdates = cached;
      emit(CatalogLoaded(
        titles: cached,
        filteredTitles: cached,
        selectedGenres: genres,
        sortBy: sortBy,
        matchAllGenres: matchAll,
        statusFilter: statusFilter,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: 1,
        hasMore: cached.length >= 15,
        isLoadingMore: false,
      ));
      return;
    }

    final requestId = ++_requestId;
    if (state is CatalogLoaded) {
      final current = state as CatalogLoaded;
      emit(current.copyWith(
        selectedGenres: genres,
        sortBy: sortBy,
        matchAllGenres: matchAll,
        statusFilter: statusFilter,
        clearStatusFilter: statusFilter == null,
        isLoadingMore: true,
      ));
    } else {
      emit(const CatalogLoading());
    }

    try {
      List<AnimeTitle> titles = [];
      final useCase = getCatalogUseCase ??
          (getIt.isRegistered<GetCatalogUseCase>() ? getIt<GetCatalogUseCase>() : null);

      if (useCase != null) {
        try {
          final entities = await useCase(
            page: 1,
            limit: 40,
            genres: genreStr,
          );
          if (entities.isNotEmpty) {
            titles = entities.map((e) => e.toAnimeTitle()).toList();
          }
        } catch (_) {}
      }

      if (titles.isEmpty) {
        titles = await getUpdates(page: 1, limit: 40);
      }

      final filtered = _applyFiltersAndSorting(
        titles,
        genres: genres,
        sortBy: sortBy,
        matchAll: matchAll,
        statusFilter: statusFilter,
      );

      if (requestId != _requestId) return;

      _cachedUpdates = filtered;
      if (filtered.isNotEmpty) {
        _pageCache[cacheKey] = filtered;
      }

      emit(CatalogLoaded(
        titles: titles,
        filteredTitles: filtered,
        selectedGenres: genres,
        sortBy: sortBy,
        matchAllGenres: matchAll,
        statusFilter: statusFilter,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: 1,
        hasMore: titles.length >= 15,
        isLoadingMore: false,
      ));
    } catch (e) {
      if (requestId != _requestId) return;
      emit(CatalogError(e.toString()));
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
      _fetchFilteredCatalog(
        genres: current.selectedGenres,
        sortBy: current.sortBy,
        statusFilter: status,
        matchAll: current.matchAllGenres,
      );
    }
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

    // 1. Фильтр по жанрам
    if (genres.isNotEmpty) {
      final cleanGenres = genres.map((g) => g.toLowerCase().trim()).toSet();
      result = result.where((title) {
        final titleGenres = title.genres.map((g) => g.toLowerCase().trim()).toList();
        if (titleGenres.isEmpty) {
          // Если у тайтла не распарсен локальный список жанров, доверяем серверному ответу AniLibria
          return true;
        }
        if (matchAll) {
          return cleanGenres.every((sg) => titleGenres.any((tg) => tg.contains(sg) || sg.contains(tg)));
        } else {
          return cleanGenres.any((sg) => titleGenres.any((tg) => tg.contains(sg) || sg.contains(tg)));
        }
      }).toList();
    }

    // 2. Фильтр по статусу
    if (statusFilter != null && statusFilter.isNotEmpty) {
      if (statusFilter == 'ongoing') {
        result = result.where((t) {
          final s = t.status.toLowerCase();
          return s.contains('онгоинг') || s.contains('выходит') || s.contains('ongoing');
        }).toList();
      } else if (statusFilter == 'released') {
        result = result.where((t) {
          final s = t.status.toLowerCase();
          return s.contains('завершен') || s.contains('вышел') || s.contains('released');
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
    return super.close();
  }
}
