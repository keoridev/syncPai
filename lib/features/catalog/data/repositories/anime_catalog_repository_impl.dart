import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/anime_entity.dart';
import '../../domain/entities/translation_entity.dart';
import '../../domain/repositories/anime_catalog_repository.dart';
import '../datasources/anime_remote_datasource.dart';

class AnimeCatalogRepositoryImpl implements AnimeCatalogRepository {
  final AnimeRemoteDataSource remoteDataSource;

  AnimeCatalogRepositoryImpl(this.remoteDataSource);

  @override
  Future<List<AnimeEntity>> getCatalog({int page = 1, int limit = 30}) async {
    try {
      final models = await remoteDataSource.getCatalog(page: page, limit: limit);
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
  Future<List<TranslationEntity>> getPlayerLinks(int shikimoriId, {String? title}) async {
    try {
      final dataModel = await remoteDataSource.getPlayerLinks(shikimoriId, title: title);
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
