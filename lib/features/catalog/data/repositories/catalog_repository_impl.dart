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
    // 1. Сначала пробуем получить полные метаданные через AniLibria API (название, описание, жанры, год, постер)
    AnimeTitle? baseTitle;
    try {
      final dto = await remoteDataSource.getTitleDetails(id: id, code: code);
      baseTitle = dto.toDomain();
    } catch (_) {}

    // 2. Получаем прямые ссылки на видеопотоки эпизодов через getPlayerLinks
    if (animeCatalogRepository != null && id != null && id > 0) {
      try {
        final translations = await animeCatalogRepository!.getPlayerLinks(
          id,
          title: baseTitle?.displayTitle ?? code,
        );
        if (translations.isNotEmpty) {
          final direct = translations.where((t) => t.isDirectStream && t.episodes.isNotEmpty);
          if (direct.isNotEmpty) {
            final epList = direct.first.episodes.map((e) => e.toEpisodeItem()).toList();
            if (baseTitle != null) {
              return baseTitle.copyWith(
                episodes: epList,
                episodesTotal: epList.length,
              );
            }

            return AnimeTitle(
              id: id,
              code: code ?? 'shikimori-$id',
              russianTitle: code ?? '',
              englishTitle: code ?? '',
              posterSmall: 'https://shikimori.io/system/animes/original/$id.jpg',
              posterMedium: 'https://shikimori.io/system/animes/original/$id.jpg',
              posterOriginal: 'https://shikimori.io/system/animes/original/$id.jpg',
              fallbackPosterUrl: 'https://shikimori.io/system/animes/original/$id.jpg',
              episodesTotal: epList.length,
              genres: const [],
              description: '',
              status: 'Завершен',
              episodes: epList,
            );
          }
        }
      } catch (_) {}
    }

    if (baseTitle != null) {
      return baseTitle;
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

