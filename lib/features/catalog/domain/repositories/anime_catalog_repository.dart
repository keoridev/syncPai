import 'package:dio/dio.dart';
import '../entities/anime_entity.dart';
import '../entities/catalog_filter.dart';
import '../entities/translation_entity.dart';

abstract class AnimeCatalogRepository {
  /// Получение страницы каталога по декларативному фильтру AniLibria API v1
  Future<CatalogPage> getReleases({
    required CatalogFilter filter,
    required int page,
    int limit = 40,
    CancelToken? cancelToken,
  });

  /// Получение каталога аниме с поддержкой пагинации и фильтрации AniLibria API v1
  Future<List<AnimeEntity>> getCatalog({
    int page = 1,
    int limit = 40,
    String? genres,
    String? year,
    String? sort,
    String? status,
    String? types,
    CancelToken? cancelToken,
  });

  /// Получение недельного расписания AniLibria `/api/v1/anime/schedule/week`
  Future<List<AnimeEntity>> getSchedule({
    CancelToken? cancelToken,
  });

  /// Поиск аниме через AniLibria API v1
  Future<List<AnimeEntity>> searchCatalog(
    String query, {
    int limit = 30,
    CancelToken? cancelToken,
  });

  /// Получение ссылок на видеопотоки и озвучки через AniLibria API
  Future<List<TranslationEntity>> getPlayerLinks(int releaseId, {String? title});
}

