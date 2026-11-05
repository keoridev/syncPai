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

      emit(current.copyWith(
        titles: combined,
        filteredTitles: _filterByGenreList(combined, current.selectedGenre),
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
        emit(current.copyWith(
          searchQuery: '',
          isSearching: false,
          filteredTitles: _filterByGenreList(_cachedUpdates, current.selectedGenre),
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
      final results = await searchTitles(query, limit: 30);
      final currentGenre = (state is CatalogLoaded) ? (state as CatalogLoaded).selectedGenre : null;
      emit(CatalogLoaded(
        titles: results,
        filteredTitles: _filterByGenreList(results, currentGenre),
        selectedGenre: currentGenre,
        searchQuery: query,
        isSearching: false,
        viewMode: _currentViewMode,
        gridDensity: _currentGridDensity,
      ));
    } catch (e) {
      emit(CatalogError('Поиск не удался: $e'));
    }
  }

  void selectGenre(String? genre) {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;

    final newGenre = current.selectedGenre == genre ? null : genre;
    final filtered = _filterByGenreList(current.titles, newGenre);

    emit(current.copyWith(
      selectedGenre: newGenre,
      clearGenre: newGenre == null,
      filteredTitles: filtered,
    ));
  }

  List<AnimeTitle> _filterByGenreList(List<AnimeTitle> list, String? genre) {
    if (genre == null || genre.isEmpty || genre == 'Все') {
      return list;
    }
    return list.where((title) => title.genres.any(
      (g) => g.toLowerCase().contains(genre.toLowerCase())
    )).toList();
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
