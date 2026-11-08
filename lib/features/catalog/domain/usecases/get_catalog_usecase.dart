import '../entities/anime_entity.dart';
import '../repositories/anime_catalog_repository.dart';

class GetCatalogUseCase {
  final AnimeCatalogRepository repository;

  const GetCatalogUseCase(this.repository);

  Future<List<AnimeEntity>> call({int page = 1, int limit = 30}) {
    return repository.getCatalog(page: page, limit: limit);
  }
}
