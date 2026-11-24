import 'package:dio/dio.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/anime_entity.dart';
import '../../domain/entities/catalog_filter.dart';
import '../../domain/entities/translation_entity.dart';
import '../../domain/repositories/anime_catalog_repository.dart';
import '../datasources/anime_remote_datasource.dart';

class AnimeCatalogRepositoryImpl implements AnimeCatalogRepository {
  final AnimeRemoteDataSource remoteDataSource;

  AnimeCatalogRepositoryImpl(this.remoteDataSource);

  @override
  Future<CatalogPage> getReleases({
    required CatalogFilter filter,
    required int page,
    int limit = 40,
    CancelToken? cancelToken,
  }) async {
    try {
      final models = await remoteDataSource.getReleases(
        filter: filter,
        page: page,
        limit: limit,
        cancelToken: cancelToken,
      );
      final items = models.map((m) => m.toDomain()).toList();
      return CatalogPage(
        items: items,
        page: page,
        hasMore: items.length >= 10,
      );
    } on NetworkException catch (e) {
      throw NetworkFailure(e.message);
    } on ServerException catch (e) {
      throw ServerFailure(e.message, e.statusCode);
    } on ParsingException catch (e) {
      throw ParsingFailure(e.message);
    } catch (e) {
      throw UnknownFailure(e.toString());
    }
  }

  @override
  Future<List<AnimeEntity>> getCatalog({
    int page = 1,
    int limit = 40,
    String? genres,
    String? year,
    String? sort,
    String? status,
    String? types,
    CancelToken? cancelToken,
  }) async {
    try {
      final models = await remoteDataSource.getCatalog(
        page: page,
        limit: limit,
        genres: genres,
        year: year,
        sort: sort,
        status: status,
        types: types,
        cancelToken: cancelToken,
      );
      return models.map((m) => m.toDomain()).toList();
    } on NetworkException catch (e) {
      throw NetworkFailure(e.message);
    } on ServerException catch (e) {
      throw ServerFailure(e.message, e.statusCode);
    } on ParsingException catch (e) {
      throw ParsingFailure(e.message);
    } catch (e) {
      throw UnknownFailure(e.toString());
    }
  }

  @override
  Future<List<AnimeEntity>> getSchedule({
    CancelToken? cancelToken,
  }) async {
    try {
      final models = await remoteDataSource.getScheduleWeek(
        cancelToken: cancelToken,
      );
      return models.map((m) => m.toDomain()).toList();
    } on NetworkException catch (e) {
      throw NetworkFailure(e.message);
    } on ServerException catch (e) {
      throw ServerFailure(e.message, e.statusCode);
    } on ParsingException catch (e) {
      throw ParsingFailure(e.message);
    } catch (e) {
      throw UnknownFailure(e.toString());
    }
  }

  @override
  Future<List<AnimeEntity>> searchCatalog(
    String query, {
    int limit = 30,
    CancelToken? cancelToken,
  }) async {
    try {
      final models = await remoteDataSource.searchCatalog(
        query,
        limit: limit,
        cancelToken: cancelToken,
      );
      return models.map((m) => m.toDomain()).toList();
    } on NetworkException catch (e) {
      throw NetworkFailure(e.message);
    } on ServerException catch (e) {
      throw ServerFailure(e.message, e.statusCode);
    } on ParsingException catch (e) {
      throw ParsingFailure(e.message);
    } catch (e) {
      throw UnknownFailure(e.toString());
    }
  }

  @override
  Future<List<TranslationEntity>> getPlayerLinks(int releaseId, {String? title}) async {
    try {
      final dataModel = await remoteDataSource.getPlayerLinks(releaseId, title: title);
      return dataModel.toDomain();
    } on NetworkException catch (e) {
      throw NetworkFailure(e.message);
    } on ServerException catch (e) {
      throw ServerFailure(e.message, e.statusCode);
    } on ParsingException catch (e) {
      throw ParsingFailure(e.message);
    } catch (e) {
      throw UnknownFailure(e.toString());
    }
  }
}

