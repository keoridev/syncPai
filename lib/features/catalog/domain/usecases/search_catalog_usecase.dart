import 'package:dio/dio.dart';
import '../entities/anime_entity.dart';
import '../repositories/anime_catalog_repository.dart';

class SearchCatalogUseCase {
  final AnimeCatalogRepository repository;

  const SearchCatalogUseCase(this.repository);

  Future<List<AnimeEntity>> call(
    String query, {
    int limit = 30,
    CancelToken? cancelToken,
  }) {
    return repository.searchCatalog(
      query,
      limit: limit,
      cancelToken: cancelToken,
    );
  }
}

