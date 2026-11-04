import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/usecases/get_updates.dart';
import '../../domain/usecases/search_titles.dart';
import 'catalog_state.dart';

class CatalogCubit extends Cubit<CatalogState> {
  final GetUpdates getUpdates;
  final SearchTitles searchTitles;

  Timer? _debounceTimer;
  List<AnimeTitle> _cachedUpdates = [];

  CatalogCubit({
    required this.getUpdates,
    required this.searchTitles,
  }) : super(const CatalogInitial());

  Future<void> loadUpdates({bool refresh = false}) async {
    if (!refresh && state is CatalogLoaded && (state as CatalogLoaded).titles.isNotEmpty) {
      return;
    }

    emit(const CatalogLoading());
    try {
      final titles = await getUpdates(page: 1, limit: 30);
      _cachedUpdates = titles;
      emit(CatalogLoaded(
        titles: titles,
        filteredTitles: titles,
      ));
    } catch (e) {
      emit(CatalogError(e.toString()));
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
