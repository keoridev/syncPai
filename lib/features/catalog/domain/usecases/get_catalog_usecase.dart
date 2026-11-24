import 'package:dio/dio.dart';
import '../entities/anime_entity.dart';
import '../entities/catalog_filter.dart';
import '../repositories/anime_catalog_repository.dart';

class GetCatalogUseCase {
  final AnimeCatalogRepository repository;

  const GetCatalogUseCase(this.repository);

  Future<CatalogPage> getReleases({
    required CatalogFilter filter,
    int page = 1,
    int limit = 40,
    CancelToken? cancelToken,
  }) {
    return repository.getReleases(
      filter: filter,
      page: page,
      limit: limit,
      cancelToken: cancelToken,
    );
  }

  Future<List<AnimeEntity>> getSchedule({
    CancelToken? cancelToken,
  }) {
    return repository.getSchedule(cancelToken: cancelToken);
  }

  Future<List<AnimeEntity>> call({
    int page = 1,
    int limit = 40,
    String? genres,
    String? year,
    String? sort,
    String? status,
    String? types,
    CancelToken? cancelToken,
  }) {
    return repository.getCatalog(
      page: page,
      limit: limit,
      genres: genres,
      year: year,
      sort: sort,
      status: status,
      types: types,
      cancelToken: cancelToken,
    );
  }
}

