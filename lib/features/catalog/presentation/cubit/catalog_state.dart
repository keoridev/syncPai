import 'package:equatable/equatable.dart';
import '../../domain/entities/anime_title.dart';

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

  const CatalogLoaded({
    required this.titles,
    required this.filteredTitles,
    this.selectedGenre,
    this.searchQuery = '',
    this.isSearching = false,
  });

  CatalogLoaded copyWith({
    List<AnimeTitle>? titles,
    List<AnimeTitle>? filteredTitles,
    String? selectedGenre,
    bool clearGenre = false,
    String? searchQuery,
    bool? isSearching,
  }) {
    return CatalogLoaded(
      titles: titles ?? this.titles,
      filteredTitles: filteredTitles ?? this.filteredTitles,
      selectedGenre: clearGenre ? null : (selectedGenre ?? this.selectedGenre),
      searchQuery: searchQuery ?? this.searchQuery,
      isSearching: isSearching ?? this.isSearching,
    );
  }

  @override
  List<Object?> get props => [titles, filteredTitles, selectedGenre, searchQuery, isSearching];
}

class CatalogError extends CatalogState {
  final String message;

  const CatalogError(this.message);

  @override
  List<Object?> get props => [message];
}
