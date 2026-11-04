import '../entities/anime_title.dart';
import '../repositories/catalog_repository.dart';

class SearchTitles {
  final CatalogRepository repository;

  const SearchTitles(this.repository);

  Future<List<AnimeTitle>> call(String query, {int limit = 20}) {
    return repository.searchTitles(query, limit: limit);
  }
}

