import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/entities/catalog_settings.dart';
import '../../domain/usecases/get_updates.dart';
import '../../domain/usecases/search_titles.dart';
import 'catalog_state.dart';

class CatalogCubit extends Cubit<CatalogState> {
  final GetUpdates getUpdates;
  final SearchTitles searchTitles;
  final SharedPreferences? prefs;

  Timer? _debounceTimer;
  List<AnimeTitle> _cachedUpdates = [];
  bool _isFetchingMore = false;
  late CatalogViewMode _currentViewMode;
  late CatalogGridDensity _currentGridDensity;

  CatalogCubit({
    required this.getUpdates,
    required this.searchTitles,
    this.prefs,
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
    if (!refresh && state is CatalogLoaded && (state as CatalogLoaded).titles.isNotEmpty) {
      return;
    }

    emit(const CatalogLoading());
    try {
      final titles = await getUpdates(page: 1, limit: 40);
      _cachedUpdates = titles;
      emit(CatalogLoaded(
        titles: titles,
        filteredTitles: titles,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
        currentPage: 1,
        hasMore: titles.length >= 15,
      ));
    } catch (e) {
      emit(CatalogError(e.toString()));
    }
  }

  /// Подгрузка следующей страницы каталога AniLibria (бесконечный скролл)
  Future<void> loadMore() async {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;
    if (_isFetchingMore || current.isLoadingMore || !current.hasMore || current.searchQuery.isNotEmpty) {
      return;
    }

    _isFetchingMore = true;
    emit(current.copyWith(isLoadingMore: true));
    try {
      final nextPage = current.currentPage + 1;
      final newTitles = await getUpdates(page: nextPage, limit: 40);

      if (newTitles.isEmpty) {
        emit(current.copyWith(hasMore: false, isLoadingMore: false));
        return;
      }

      // Исключаем возможные дубликаты по ID тайтла
      final existingIds = current.titles.map((t) => t.id).toSet();
      final uniqueNew = newTitles.where((t) => !existingIds.contains(t.id)).toList();

      final combined = List<AnimeTitle>.from(current.titles)..addAll(uniqueNew);
      _cachedUpdates = combined;

      final filtered = _applyFiltersAndSorting(
        combined,
        genres: current.selectedGenres,
        sortBy: current.sortBy,
        matchAll: current.matchAllGenres,
        statusFilter: current.statusFilter,
      );

      emit(current.copyWith(
        titles: combined,
        filteredTitles: filtered,
        currentPage: nextPage,
        hasMore: newTitles.length >= 10,
        isLoadingMore: false,
      ));
    } catch (e) {
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
    _debounceTimer?.cancel();
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

    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      await performSearch(trimmed);
    });
  }

  Future<void> performSearch(String query) async {
    if (state is CatalogLoaded) {
      emit((state as CatalogLoaded).copyWith(isSearching: true, searchQuery: query));
    } else {
      emit(const CatalogLoading());
    }

    try {
      final results = await searchTitles(query, limit: 40);
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
      emit(CatalogError('Поиск не удался: $e'));
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
  }

  /// Очистить все фильтры жанров
  void clearGenres() {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;

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
  }

  /// Установить сортировку каталога
  void setSortBy(CatalogSort sort) {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;

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
    _debounceTimer?.cancel();
    return super.close();
  }
}
