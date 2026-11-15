import 'package:dio/dio.dart';
import '../entities/anime_entity.dart';
import '../repositories/anime_catalog_repository.dart';

class GetCatalogUseCase {
  final AnimeCatalogRepository repository;

  const GetCatalogUseCase(this.repository);

  Future<List<AnimeEntity>> call({
    int page = 1,
    int limit = 40,
    String? genres,
    String? year,
    String? sort,
    String? status,
    CancelToken? cancelToken,
  }) {
    return repository.getCatalog(
      page: page,
      limit: limit,
      genres: genres,
      year: year,
      sort: sort,
      status: status,
      cancelToken: cancelToken,
    );
  }
}

