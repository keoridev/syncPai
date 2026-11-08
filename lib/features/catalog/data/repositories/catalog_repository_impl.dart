import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/repositories/anime_catalog_repository.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../datasources/anilibria_remote_datasource.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  final AnilibriaRemoteDataSource remoteDataSource;
  final AnimeCatalogRepository? animeCatalogRepository;

  CatalogRepositoryImpl(
    this.remoteDataSource, {
    this.animeCatalogRepository,
  });

  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async {
    if (animeCatalogRepository != null) {
      try {
        final list = await animeCatalogRepository!.getCatalog(page: page, limit: limit);
        if (list.isNotEmpty) {
          return list.map((e) => e.toAnimeTitle()).toList();
        }
      } catch (_) {}
    }

    try {
      final dtos = await remoteDataSource.getUpdates(page: page, limit: limit);
      return dtos.map((dto) => dto.toDomain()).toList();
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
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20}) async {
    if (animeCatalogRepository != null) {
      try {
        final list = await animeCatalogRepository!.searchCatalog(query, limit: limit);
        if (list.isNotEmpty) {
          return list.map((e) => e.toAnimeTitle()).toList();
        }
      } catch (_) {}
    }

    try {
      final dtos = await remoteDataSource.searchTitles(query, limit: limit);
      return dtos.map((dto) => dto.toDomain()).toList();
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
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) async {
    try {
      final dto = await remoteDataSource.getTitleDetails(id: id, code: code);
      return dto.toDomain();
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

