import 'package:dio/dio.dart';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/episode_item.dart';
import '../models/anime_catalog_model.dart';
import '../models/anime_player_data_model.dart';
import '../models/episode_model.dart';
import '../models/translation_model.dart';

abstract class AnimeRemoteDataSource {
  /// Получение каталога напрямую через AniLiberty (AniLibria v1) API
  Future<List<AnimeCatalogModel>> getCatalog({
    int page = 1,
    int limit = 40,
    String? genres,
    String? year,
  });

  /// Поиск по аниме через AniLiberty (AniLibria v1) API
  Future<List<AnimeCatalogModel>> searchCatalog(String query, {int limit = 20});

  /// Получение прямых ссылок и озвучек напрямую через AniLiberty API
  Future<AnimePlayerDataModel> getPlayerLinks(int releaseId, {String? title});
}

class AniLibertyAnimeRemoteDataSourceImpl implements AnimeRemoteDataSource {
  final Dio _dio;

  static const String _catalogUrl = 'https://anilibria.top/api/v1/anime/catalog/releases';
  static const String _searchUrl = 'https://anilibria.top/api/v1/app/search/releases';
  static const String _releaseUrl = 'https://anilibria.top/api/v1/anime/releases';

  static const String _fallbackCatalogUrl = 'https://api.anilibria.app/api/v1/anime/catalog/releases';
  static const String _fallbackSearchUrl = 'https://api.anilibria.app/api/v1/app/search/releases';
  static const String _fallbackReleaseUrl = 'https://api.anilibria.app/api/v1/anime/releases';

  AniLibertyAnimeRemoteDataSourceImpl({
    Dio? customDio,
    dynamic customClient,
  }) : _dio = customDio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 5),
                sendTimeout: const Duration(seconds: 4),
                headers: const {
                  'Accept': 'application/json',
                  'User-Agent': 'SyncPai-App/1.0',
                },
              ),
            );

  @override
  Future<List<AnimeCatalogModel>> getCatalog({
    int page = 1,
    int limit = 40,
    String? genres,
    String? year,
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'limit': limit,
    };
    if (genres != null && genres.trim().isNotEmpty) {
      queryParams['genres'] = genres.trim();
    }
    if (year != null && year.trim().isNotEmpty) {
      queryParams['years'] = year.trim();
    }

    try {
      final response = await _dio.get(
        _catalogUrl,
        queryParameters: queryParams,
      );
      return _parseReleases(response.data);
    } catch (_) {
      try {
        final fallbackRes = await _dio.get(
          _fallbackCatalogUrl,
          queryParameters: queryParams,
        );
        return _parseReleases(fallbackRes.data);
      } catch (e) {
        throw ServerException('Ошибка загрузки каталога AniLiberty: $e');
      }
    }
  }

  @override
  Future<List<AnimeCatalogModel>> searchCatalog(String query, {int limit = 20}) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return getCatalog(page: 1, limit: limit);
    }

    try {
      final response = await _dio.get(
        _searchUrl,
        queryParameters: {
          'query': clean,
        },
      );
      return _parseReleases(response.data);
    } catch (_) {
      try {
        final fallbackRes = await _dio.get(
          _fallbackSearchUrl,
          queryParameters: {
            'query': clean,
          },
        );
        return _parseReleases(fallbackRes.data);
      } catch (e) {
        throw ServerException('Ошибка поиска AniLiberty: $e');
      }
    }
  }

  @override
  Future<AnimePlayerDataModel> getPlayerLinks(int releaseId, {String? title}) async {
    try {
      Response? res;
      try {
        res = await _dio.get('$_releaseUrl/$releaseId');
      } catch (_) {
        if (title != null && title.trim().isNotEmpty) {
          try {
            final sRes = await _dio.get(
              _searchUrl,
              queryParameters: {'query': title.trim()},
            );
            final items = _parseReleases(sRes.data);
            if (items.isNotEmpty) {
              final relId = items.first.id;
              res = await _dio.get('$_releaseUrl/$relId');
            }
          } catch (_) {}
        }
      }

      if (res == null && title != null && title.trim().isNotEmpty) {
        try {
          final fallbackSRes = await _dio.get(
            _fallbackSearchUrl,
            queryParameters: {'query': title.trim()},
          );
          final items = _parseReleases(fallbackSRes.data);
          if (items.isNotEmpty) {
            final relId = items.first.id;
            res = await _dio.get('$_fallbackReleaseUrl/$relId');
          }
        } catch (_) {}
      }

      if (res != null && res.data != null) {
        final dynamic relData = (res.data is Map && res.data['data'] is Map)
            ? res.data['data']
            : res.data;
        if (relData is Map<String, dynamic>) {
          final List<EpisodeModel> directEpisodes = [];
          final rawEps = (relData['episodes'] as List? ?? []);
          for (final e in rawEps) {
            if (e is Map<String, dynamic>) {
              final epNum = (e['episode'] ?? e['ordinal'] as num?)?.toInt() ?? 1;
              final fhd = e['fhd'] ?? e['hls_1080'] as String?;
              final hd = e['hd'] ?? e['hls_720'] as String?;
              final sd = e['sd'] ?? e['hls_480'] as String?;
              final link = fhd ?? hd ?? sd ?? (e['link'] as String? ?? '');

              TimecodeRange? opRange;
              TimecodeRange? edRange;
              if (e['opening'] is Map) {
                final op = e['opening'] as Map;
                if (op['start'] != null && op['stop'] != null) {
                  opRange = TimecodeRange(
                    start: (op['start'] as num).toInt(),
                    stop: (op['stop'] as num).toInt(),
                  );
                }
              }
              if (e['ending'] is Map) {
                final ed = e['ending'] as Map;
                if (ed['start'] != null && ed['stop'] != null) {
                  edRange = TimecodeRange(
                    start: (ed['start'] as num).toInt(),
                    stop: (ed['stop'] as num).toInt(),
                  );
                }
              }

              final previewPath = (e['preview'] ?? e['thumbnail'] ?? (e['poster'] is Map ? (e['poster']['preview'] ?? e['poster']['src']) : null))?.toString();
              final fullPreviewUrl = (previewPath != null && previewPath.isNotEmpty)
                  ? (previewPath.startsWith('http') ? previewPath : 'https://anilibria.top$previewPath')
                  : null;

              if (link.isNotEmpty) {
                directEpisodes.add(EpisodeModel(
                  episode: epNum,
                  link: link,
                  name: e['name'] as String?,
                  fhd: fhd,
                  hd: hd,
                  sd: sd,
                  preview: fullPreviewUrl,
                  opening: opRange,
                  ending: edRange,
                ));
              }
            }
          }
          final translations = [
            TranslationModel(
              studioName: 'AniLibria',
              translationType: 'voice',
              isDirectStream: true,
              episodes: directEpisodes,
            ),
          ];
          return AnimePlayerDataModel(
            shikimoriId: releaseId,
            source: 'anilibria',
            title: title,
            episodes: directEpisodes,
            translations: translations,
          );
        }
      }

      return AnimePlayerDataModel(
        shikimoriId: releaseId,
        source: 'anilibria',
        title: title,
        translations: const [],
      );
    } catch (_) {
      return AnimePlayerDataModel(
        shikimoriId: releaseId,
        source: 'anilibria',
        title: title,
        translations: const [],
      );
    }
  }

  List<AnimeCatalogModel> _parseReleases(dynamic data) {
    List<dynamic> items = [];
    if (data is Map && data['data'] is List) {
      items = data['data'] as List;
    } else if (data is List) {
      items = data;
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map((json) => AnimeCatalogModel.fromJson(json))
        .toList();
  }
}

typedef ShikimoriAnimeRemoteDataSourceImpl = AniLibertyAnimeRemoteDataSourceImpl;
typedef SupabaseAnimeRemoteDataSourceImpl = AniLibertyAnimeRemoteDataSourceImpl;
