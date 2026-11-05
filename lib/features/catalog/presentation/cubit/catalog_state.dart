import 'package:equatable/equatable.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/entities/catalog_settings.dart';

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
  final String? selectedGenre;
  final String searchQuery;
  final bool isSearching;
  final CatalogViewMode viewMode;
  final CatalogGridDensity gridDensity;
  final int currentPage;
  final bool hasMore;
  final bool isLoadingMore;

  const CatalogLoaded({
    required this.titles,
    required this.filteredTitles,
    this.selectedGenre,
    this.searchQuery = '',
    this.isSearching = false,
    this.viewMode = CatalogViewMode.grid,
    this.gridDensity = CatalogGridDensity.standard,
    this.currentPage = 1,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  CatalogLoaded copyWith({
    List<AnimeTitle>? titles,
    List<AnimeTitle>? filteredTitles,
    String? selectedGenre,
    bool clearGenre = false,
    String? searchQuery,
    bool? isSearching,
    CatalogViewMode? viewMode,
    CatalogGridDensity? gridDensity,
    int? currentPage,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return CatalogLoaded(
      titles: titles ?? this.titles,
      filteredTitles: filteredTitles ?? this.filteredTitles,
      selectedGenre: clearGenre ? null : (selectedGenre ?? this.selectedGenre),
      searchQuery: searchQuery ?? this.searchQuery,
      isSearching: isSearching ?? this.isSearching,
      viewMode: viewMode ?? this.viewMode,
      gridDensity: gridDensity ?? this.gridDensity,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => [
        titles,
        filteredTitles,
        selectedGenre,
        searchQuery,
        isSearching,
        viewMode,
        gridDensity,
        currentPage,
        hasMore,
        isLoadingMore,
      ];
}

class CatalogError extends CatalogState {
  final String message;

  const CatalogError(this.message);

  @override
  List<Object?> get props => [message];
}
