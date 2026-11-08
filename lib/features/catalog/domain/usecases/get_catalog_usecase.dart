import '../entities/anime_entity.dart';
import '../repositories/anime_catalog_repository.dart';

class GetCatalogUseCase {
  final AnimeCatalogRepository repository;

  const GetCatalogUseCase(this.repository);

  Future<List<AnimeEntity>> call({
    int page = 1,
    int limit = 30,
    String? order,
    String? status,
    String? genre,
  }) {
    return repository.getCatalog(
      page: page,
      limit: limit,
      order: order,
      status: status,
      genre: genre,
    );
  }
}

