import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/anime_title.dart';
import '../../domain/repositories/anime_catalog_repository.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../datasources/anilibria_remote_datasource.dart';

import '../../domain/entities/episode_item.dart';

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
        return list.map((e) => e.toAnimeTitle()).toList();
      } on NetworkException catch (e) {
        throw NetworkFailure(e.message);
      } on ServerException catch (e) {
        throw ServerFailure(e.message, e.statusCode);
      } catch (e) {
        throw ServerFailure('Ошибка загрузки каталога: $e');
      }
    }

    try {
      final dtos = await remoteDataSource.getUpdates(page: page, limit: limit);
      return dtos.map((dto) => dto.toDomain()).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20}) async {
    if (animeCatalogRepository != null) {
      try {
        final list = await animeCatalogRepository!.searchCatalog(query, limit: limit);
        return list.map((e) => e.toAnimeTitle()).toList();
      } on NetworkException catch (e) {
        throw NetworkFailure(e.message);
      } on ServerException catch (e) {
        throw ServerFailure(e.message, e.statusCode);
      } catch (e) {
        throw ServerFailure('Ошибка поиска: $e');
      }
    }

    try {
      final dtos = await remoteDataSource.searchTitles(query, limit: limit);
      return dtos.map((dto) => dto.toDomain()).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) async {
    // 1. Приоритетный источник: Supabase Edge Function get_anime_player_data (BFF)
    // Предотвращает каскадные 404 ошибки на клиенте по Shikimori ID
    if (animeCatalogRepository != null && id != null && id > 0) {
      try {
        final translations = await animeCatalogRepository!.getPlayerLinks(id, title: code);
        if (translations.isNotEmpty) {
          final direct = translations.where((t) => t.isDirectStream && t.episodes.isNotEmpty);
          final epList = direct.isNotEmpty
              ? direct.first.episodes
                  .map((e) => EpisodeItem(
                        episode: e.episode,
                        sdUrl: e.link,
                        hdUrl: e.link,
                        fhdUrl: e.link,
                      ))
                  .toList()
              : <EpisodeItem>[];

          return AnimeTitle(
            id: id,
            code: code ?? 'shikimori-$id',
            russianTitle: code ?? '',
            englishTitle: code ?? '',
            posterSmall: '',
            posterMedium: '',
            posterOriginal: '',
            episodesTotal: epList.length,
            genres: const [],
            description: '',
            status: 'Завершен',
            episodes: epList,
          );
        }
      } catch (_) {}
    }

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

