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
  final Map<String, List<AnimeTitle>> _pageCache = {};
  bool _isFetchingMore = false;
  int _requestId = 0;
  late CatalogViewMode _currentViewMode;
  late CatalogGridDensity _currentGridDensity;

  static const Map<String, int> shikimoriGenreMap = {
    'экшен': 1,
    'action': 1,
    'приключения': 2,
    'adventure': 2,
    'комедия': 4,
    'comedy': 4,
    'детектив': 7,
    'mystery': 7,
    'мистика': 7,
    'драма': 8,
    'drama': 8,
    'фэнтези': 10,
    'fantasy': 10,
    'игры': 11,
    'game': 11,
    'исторический': 13,
    'historical': 13,
    'ужасы': 14,
    'horror': 14,
    'магия': 16,
    'magic': 16,
    'меха': 18,
    'mecha': 18,
    'музыка': 19,
    'music': 19,
    'романтика': 22,
    'romance': 22,
    'школа': 23,
    'school': 23,
    'фантастика': 24,
    'sci-fi': 24,
    'киберпанк': 24,
    'сёнэн': 27,
    'shounen': 27,
    'спорт': 30,
    'sports': 30,
    'повседневность': 36,
    'slice of life': 36,
    'сверхъестественное': 37,
    'supernatural': 37,
    'военное': 38,
    'military': 38,
    'психология': 40,
    'psychological': 40,
    'триллер': 41,
    'thriller': 41,
    'сэйнэн': 42,
    'seinen': 42,
  };

  String? _mapGenresToShikimori(Set<String> genres) {
    if (genres.isEmpty) return null;
    final ids = <int>{};
    for (final g in genres) {
      final key = g.toLowerCase().trim();
      final id = shikimoriGenreMap[key];
      if (id != null) {
        ids.add(id);
      }
    }
    return ids.isEmpty ? null : ids.join(',');
  }

  String _mapSortToOrder(CatalogSort sort) {
    switch (sort) {
      case CatalogSort.rating:
        return 'ranked';
      case CatalogSort.alphabetical:
        return 'name';
      case CatalogSort.yearDesc:
      case CatalogSort.yearAsc:
      case CatalogSort.updates:
        return 'aired_on';
      case CatalogSort.episodes:
        return 'popularity';
    }
  }

  String? _mapStatus(CatalogSort sort, String? statusFilter) {
    if (statusFilter != null && statusFilter.isNotEmpty) {
      return statusFilter;
    }
    if (sort == CatalogSort.updates) {
      return 'ongoing';
    }
    return null;
  }

  String _buildCacheKey({
    required String order,
    required String? status,
    required String? genre,
  }) {
    return '${order}_${status ?? "all"}_${genre ?? "all"}';
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
    final val = prefs?.getInt('catalog_grid_density');
    return val == 3 ? CatalogGridDensity.compact : CatalogGridDensity.standard;
  }

  Future<void> loadUpdates({bool refresh = false}) async {
    if (refresh) {
      _pageCache.clear();
    } else if (state is CatalogLoaded && (state as CatalogLoaded).titles.isNotEmpty) {
      return;
    }

    final requestId = ++_requestId;
    emit(const CatalogLoading());
    try {
      final current = state is CatalogLoaded ? (state as CatalogLoaded) : null;
      final sort = current?.sortBy ?? CatalogSort.updates;
      final genres = current?.selectedGenres ?? const <String>{};
      final statusFilter = current?.statusFilter;

      final order = _mapSortToOrder(sort);
      final status = _mapStatus(sort, statusFilter);
      final genreStr = _mapGenresToShikimori(genres);
      final cacheKey = _buildCacheKey(order: order, status: status, genre: genreStr);

      if (!refresh && _pageCache.containsKey(cacheKey) && _pageCache[cacheKey]!.isNotEmpty) {
        final cached = _pageCache[cacheKey]!;
        _cachedUpdates = cached;
        emit(CatalogLoaded(
          titles: cached,
          filteredTitles: cached,
          selectedGenres: genres,
          sortBy: sort,
          matchAllGenres: current?.matchAllGenres ?? false,
          statusFilter: statusFilter,
          viewMode: _currentViewMode,
          gridDensity: _currentGridDensity,
          currentPage: 1,
          hasMore: cached.length >= 15,
        ));
        return;
      }

      List<AnimeTitle> titles = [];
      final useCase = getCatalogUseCase ??
          (getIt.isRegistered<GetCatalogUseCase>() ? getIt<GetCatalogUseCase>() : null);

      if (useCase != null) {
        try {
          final entities = await useCase(
            page: 1,
            limit: 40,
            order: order,
            status: status,
            genre: genreStr,
          );
          if (entities.isNotEmpty) {
            titles = entities.map((e) => e.toAnimeTitle()).toList();
          }
        } catch (_) {}
      }

      if (titles.isEmpty) {
        titles = await getUpdates(page: 1, limit: 40);
        titles = _applyFiltersAndSorting(
          titles,
          genres: genres,
          sortBy: sort,
          matchAll: current?.matchAllGenres ?? false,
          statusFilter: statusFilter,
        );
      }

      if (requestId != _requestId) return;

      _cachedUpdates = titles;
      if (titles.isNotEmpty) {
        _pageCache[cacheKey] = titles;
      }

      emit(CatalogLoaded(
        titles: titles,
        filteredTitles: titles,
        selectedGenres: genres,
        sortBy: sort,
        matchAllGenres: current?.matchAllGenres ?? false,
        statusFilter: statusFilter,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: 1,
        hasMore: titles.length >= 15,
      ));
    } catch (e) {
      if (requestId != _requestId) return;
      emit(CatalogError(e.toString()));
    }
  }

  /// Подгрузка следующей страницы каталога (Supabase PostgreSQL / Shikimori BFF)
  Future<void> loadMore() async {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;
    if (_isFetchingMore || current.isLoadingMore || !current.hasMore || current.searchQuery.isNotEmpty) {
      return;
    }

    final requestId = _requestId;
    _isFetchingMore = true;
    emit(current.copyWith(isLoadingMore: true));
    try {
      final nextPage = current.currentPage + 1;
      final order = _mapSortToOrder(current.sortBy);
      final status = _mapStatus(current.sortBy, current.statusFilter);
      final genreStr = _mapGenresToShikimori(current.selectedGenres);

      List<AnimeTitle> newTitles = [];
      final useCase = getCatalogUseCase ??
          (getIt.isRegistered<GetCatalogUseCase>() ? getIt<GetCatalogUseCase>() : null);

      if (useCase != null) {
        try {
          final entities = await useCase(
            page: nextPage,
            limit: 40,
            order: order,
            status: status,
            genre: genreStr,
          );
          if (entities.isNotEmpty) {
            newTitles = entities.map((e) => e.toAnimeTitle()).toList();
          }
        } catch (_) {}
      }

      if (newTitles.isEmpty) {
        newTitles = await getUpdates(page: nextPage, limit: 40);
        newTitles = _applyFiltersAndSorting(
          newTitles,
          genres: current.selectedGenres,
          sortBy: current.sortBy,
          matchAll: current.matchAllGenres,
          statusFilter: current.statusFilter,
        );
      }

      if (requestId != _requestId) return;

      if (newTitles.isEmpty) {
        emit(current.copyWith(hasMore: false, isLoadingMore: false));
        return;
      }

      // Исключаем возможные дубликаты по ID тайтла
      final existingIds = current.titles.map((t) => t.id).toSet();
      final uniqueNew = newTitles.where((t) => !existingIds.contains(t.id)).toList();

      final combined = List<AnimeTitle>.from(current.titles)..addAll(uniqueNew);
      _cachedUpdates = combined;

      emit(current.copyWith(
        titles: combined,
        filteredTitles: combined,
        currentPage: nextPage,
        hasMore: newTitles.length >= 10,
        isLoadingMore: false,
      ));
    } catch (e) {
      if (requestId != _requestId) return;
      emit(current.copyWith(isLoadingMore: false));
    } finally {
      _isFetchingMore = false;
    }
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
    prefs?.setInt('catalog_grid_density', density.mobileColumns);
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
    final order = _mapSortToOrder(sortBy);
    final status = _mapStatus(sortBy, statusFilter);
    final genreStr = _mapGenresToShikimori(genres);
    final cacheKey = _buildCacheKey(order: order, status: status, genre: genreStr);

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
            order: order,
            status: status,
            genre: genreStr,
          );
          if (entities.isNotEmpty) {
            titles = entities.map((e) => e.toAnimeTitle()).toList();
          }
        } catch (_) {}
      }

      if (titles.isEmpty) {
        titles = await getUpdates(page: 1, limit: 40);
        titles = _applyFiltersAndSorting(
          titles,
          genres: genres,
          sortBy: sortBy,
          matchAll: matchAll,
          statusFilter: statusFilter,
        );
      }

      if (requestId != _requestId) return;

      _cachedUpdates = titles;
      if (titles.isNotEmpty) {
        _pageCache[cacheKey] = titles;
      }

      emit(CatalogLoaded(
        titles: titles,
        filteredTitles: titles,
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
  void selectGenre(String? genre) {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;

    Set<String> nextGenres;
    if (genre == null || genre.isEmpty || genre == 'Все') {
      nextGenres = const {};
    } else if (current.selectedGenres.contains(genre) && current.selectedGenres.length == 1) {
      nextGenres = const {};
    } else {
      nextGenres = {genre};
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
        clearGenre: nextGenres.isEmpty,
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

  /// Очистить все фильтры жанров
  void clearGenres() {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;

    if (current.searchQuery.isNotEmpty) {
      final filtered = _applyFiltersAndSorting(
        current.titles,
        genres: const {},
        sortBy: current.sortBy,
        matchAll: current.matchAllGenres,
        statusFilter: current.statusFilter,
      );
      emit(current.copyWith(
        selectedGenres: const {},
        clearGenre: true,
        filteredTitles: filtered,
      ));
    } else {
      _fetchFilteredCatalog(
        genres: const {},
        sortBy: current.sortBy,
        statusFilter: current.statusFilter,
        matchAll: current.matchAllGenres,
      );
    }
  }

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
