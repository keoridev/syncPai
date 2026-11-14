import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/episode_item.dart';
import '../models/anime_catalog_model.dart';
import '../models/anime_player_data_model.dart';
import '../models/episode_model.dart';
import '../models/translation_model.dart';

/// Top-level функция для парсинга больших списков релизов в отдельном изоляте через compute()
List<AnimeCatalogModel> parseAnimeCatalogReleasesInIsolate(dynamic data) {
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

  static const Map<String, int> _genreNameToId = {
    'комедия': 1,
    'меха': 2,
    'романтика': 3,
    'сенен': 4,
    'сёнэн': 4,
    'сейнен': 5,
    'сэйнэн': 5,
    'триллер': 6,
    'школа': 7,
    'драма': 8,
    'мистика': 9,
    'музыка': 10,
    'повседневность': 11,
    'спорт': 12,
    'ужасы': 13,
    'экшен': 14,
    'экшн': 14,
    'боевые искусства': 15,
    'демоны': 16,
    'игры': 17,
    'игра': 17,
    'магия': 18,
    'психологическое': 19,
    'психология': 19,
    'военное': 20,
    'супер сила': 21,
    'суперсила': 21,
    'фантастика': 22,
    'этти': 23,
    'вампиры': 24,
    'детектив': 25,
    'исторический': 26,
    'история': 26,
    'приключения': 27,
    'сверхъестественное': 28,
    'фэнтези': 29,
    'киберпанк': 30,
    'седзе': 31,
    'сёдзё': 31,
    'гарем': 32,
    'дзесей': 33,
    'дзёсей': 33,
    'исекай': 34,
    'самураи': 35,
  };

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
    if (genres != null && genres.trim().isNotEmpty && genres.trim() != 'Все') {
      final parts = genres
          .split(RegExp(r'[,;]+'))
          .map((s) => s.trim().toLowerCase().replaceAll('ё', 'е'))
          .where((s) => s.isNotEmpty);
      final ids = <int>[];
      for (final p in parts) {
        final id = _genreNameToId[p] ?? int.tryParse(p);
        if (id != null && !ids.contains(id)) {
          ids.add(id);
        }
      }
      if (ids.isNotEmpty) {
        queryParams['f[genres][]'] = ids.length == 1 ? ids.first : ids;
      }
    }
    if (year != null && year.trim().isNotEmpty) {
      queryParams['years'] = year.trim();
    }

    try {
      final response = await _dio.get(
        _catalogUrl,
        queryParameters: queryParams,
      );
      return await _parseReleasesAsync(response.data);
    } catch (_) {
      try {
        final fallbackRes = await _dio.get(
          _fallbackCatalogUrl,
          queryParameters: queryParams,
        );
        return await _parseReleasesAsync(fallbackRes.data);
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
      return await _parseReleasesAsync(response.data);
    } catch (_) {
      try {
        final fallbackRes = await _dio.get(
          _fallbackSearchUrl,
          queryParameters: {
            'query': clean,
          },
        );
        return await _parseReleasesAsync(fallbackRes.data);
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

              String? previewPath;
              if (e['preview'] is Map) {
                final pMap = e['preview'] as Map;
                previewPath = (pMap['src'] ??
                        pMap['optimized']?['src'] ??
                        pMap['preview'] ??
                        pMap['thumbnail'])
                    ?.toString();
              } else if (e['preview'] is String && (e['preview'] as String).isNotEmpty) {
                previewPath = e['preview'] as String;
              } else if (e['thumbnail'] is String && (e['thumbnail'] as String).isNotEmpty) {
                previewPath = e['thumbnail'] as String;
              } else if (e['poster'] is Map) {
                final pMap = e['poster'] as Map;
                previewPath = (pMap['src'] ?? pMap['preview'] ?? pMap['thumbnail'])?.toString();
              }

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

  bool get _isTestEnv {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
    } catch (_) {}
    return false;
  }

  Future<List<AnimeCatalogModel>> _parseReleasesAsync(dynamic data) async {
    if (_isTestEnv) {
      return parseAnimeCatalogReleasesInIsolate(data);
    }
    return compute(parseAnimeCatalogReleasesInIsolate, data);
  }

  List<AnimeCatalogModel> _parseReleases(dynamic data) {
    return parseAnimeCatalogReleasesInIsolate(data);
  }
}

typedef ShikimoriAnimeRemoteDataSourceImpl = AniLibertyAnimeRemoteDataSourceImpl;
typedef SupabaseAnimeRemoteDataSourceImpl = AniLibertyAnimeRemoteDataSourceImpl;
