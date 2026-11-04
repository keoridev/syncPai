import '../entities/anime_title.dart';
import '../repositories/catalog_repository.dart';

class GetUpdates {
  final CatalogRepository repository;

  const GetUpdates(this.repository);

  Future<List<AnimeTitle>> call({int page = 1, int limit = 20}) {
    return repository.getUpdates(page: page, limit: limit);
  }
}

