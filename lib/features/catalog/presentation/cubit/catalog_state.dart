import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import '../../../manga/domain/entities/manga_bridge.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/entities/catalog_settings.dart';

enum CatalogSort {
  updates('Свежие обновления', Icons.auto_awesome_rounded),
  rating('По отзывам и рейтингу', Icons.star_rounded),
  yearDesc('Сначала новинки (по году)', Icons.calendar_today_rounded),
  yearAsc('Сначала классика (по году)', Icons.history_toggle_off_rounded),
  episodes('По количеству серий', Icons.video_library_rounded),
  alphabetical('По названию (А-Я)', Icons.sort_by_alpha_rounded);

  final String label;
  final IconData icon;
  const CatalogSort(this.label, this.icon);
}

sealed class CatalogState extends Equatable {
  const CatalogState();

  @override
  List<Object?> get props => [];
}

class CatalogInitial extends CatalogState {
  const CatalogInitial();
}

class CatalogLoading extends CatalogState {
  const CatalogLoading();
}

class CatalogLoaded extends CatalogState {
  final List<AnimeTitle> titles;
  final List<AnimeTitle> filteredTitles;
  final Set<String> selectedGenres;
  final CatalogSort sortBy;
  final bool matchAllGenres;
  final String? statusFilter; // 'ongoing' | 'released' | 'anons' | null (все)
  final String? typeFilter; // 'MOVIE' | null (все)
  final String searchQuery;
  final bool isSearching;
  final CatalogViewMode viewMode;
  final CatalogGridDensity gridDensity;
  final int currentPage;
  final bool hasMore;
  final bool isLoadingMore;
  final String activeFilterKey;
  final bool isRefreshing;
  final bool isLoadingNextPage;
  final bool isMangaMode;
  final List<MangaDexManga> mangaItems;
  final String mangaTab;
  final bool mangaRussianOnly;
  final bool isMangaLoading;
  final bool isMangaLoadingMore;
  final bool hasMoreManga;
  final String mangaSearchQuery;

  const CatalogLoaded({
    required this.titles,
    required this.filteredTitles,
    this.selectedGenres = const {},
    this.sortBy = CatalogSort.updates,
    this.matchAllGenres = false,
    this.statusFilter,
    this.typeFilter,
    this.searchQuery = '',
    this.isSearching = false,
    this.viewMode = CatalogViewMode.grid,
    this.gridDensity = CatalogGridDensity.standard,
    this.currentPage = 1,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.activeFilterKey = '',
    this.isRefreshing = false,
    this.isLoadingNextPage = false,
    this.isMangaMode = false,
    this.mangaItems = const [],
    this.mangaTab = 'all',
    this.mangaRussianOnly = true,
    this.isMangaLoading = false,
    this.isMangaLoadingMore = false,
    this.hasMoreManga = true,
    this.mangaSearchQuery = '',
  });

  /// Геттер для обратной совместимости с существующим кодом
  String? get selectedGenre => selectedGenres.isNotEmpty ? selectedGenres.first : null;
  bool get hasReachedMax => !hasMore;

  CatalogLoaded copyWith({
    List<AnimeTitle>? titles,
    List<AnimeTitle>? filteredTitles,
    Set<String>? selectedGenres,
    String? selectedGenre,
    bool clearGenre = false,
    CatalogSort? sortBy,
    bool? matchAllGenres,
    String? statusFilter,
    bool clearStatusFilter = false,
    String? typeFilter,
    bool clearTypeFilter = false,
    String? searchQuery,
    bool? isSearching,
    CatalogViewMode? viewMode,
    CatalogGridDensity? gridDensity,
    int? currentPage,
    bool? hasMore,
    bool? isLoadingMore,
    String? activeFilterKey,
    bool? isRefreshing,
    bool? isLoadingNextPage,
    bool? isMangaMode,
    List<MangaDexManga>? mangaItems,
    String? mangaTab,
    bool? mangaRussianOnly,
    bool? isMangaLoading,
    bool? isMangaLoadingMore,
    bool? hasMoreManga,
    String? mangaSearchQuery,
  }) {
    Set<String> nextGenres;
    if (clearGenre) {
      nextGenres = const {};
    } else if (selectedGenres != null) {
      nextGenres = selectedGenres;
    } else if (selectedGenre != null) {
      nextGenres = {selectedGenre};
    } else {
      nextGenres = this.selectedGenres;
    }

    return CatalogLoaded(
      titles: titles ?? this.titles,
      filteredTitles: filteredTitles ?? this.filteredTitles,
      selectedGenres: nextGenres,
      sortBy: sortBy ?? this.sortBy,
      matchAllGenres: matchAllGenres ?? this.matchAllGenres,
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      isSearching: isSearching ?? this.isSearching,
      viewMode: viewMode ?? this.viewMode,
      gridDensity: gridDensity ?? this.gridDensity,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      activeFilterKey: activeFilterKey ?? this.activeFilterKey,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingNextPage: isLoadingNextPage ?? this.isLoadingNextPage,
      isMangaMode: isMangaMode ?? this.isMangaMode,
      mangaItems: mangaItems ?? this.mangaItems,
      mangaTab: mangaTab ?? this.mangaTab,
      mangaRussianOnly: mangaRussianOnly ?? this.mangaRussianOnly,
      isMangaLoading: isMangaLoading ?? this.isMangaLoading,
      isMangaLoadingMore: isMangaLoadingMore ?? this.isMangaLoadingMore,
      hasMoreManga: hasMoreManga ?? this.hasMoreManga,
      mangaSearchQuery: mangaSearchQuery ?? this.mangaSearchQuery,
    );
  }

  @override
  List<Object?> get props => [
        titles,
        filteredTitles,
        selectedGenres,
        sortBy,
        matchAllGenres,
        statusFilter,
        typeFilter,
        searchQuery,
        isSearching,
        viewMode,
        gridDensity,
        currentPage,
        hasMore,
        isLoadingMore,
        activeFilterKey,
        isRefreshing,
        isLoadingNextPage,
        isMangaMode,
        mangaItems,
        mangaTab,
        mangaRussianOnly,
        isMangaLoading,
        isMangaLoadingMore,
        hasMoreManga,
        mangaSearchQuery,
      ];
}

class CatalogError extends CatalogState {
  final String message;

  const CatalogError(this.message);

  @override
  List<Object?> get props => [message];
}
