import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  /// Получение каталога напрямую через AniLiberty (AniLibria v1) API / Supabase anime_catalog
  Future<List<AnimeCatalogModel>> getCatalog({
    int page = 1,
    int limit = 40,
    String? genres,
    String? year,
    String? sort,
    String? status,
    CancelToken? cancelToken,
  });

  /// Поиск по аниме через AniLiberty (AniLibria v1) API
  Future<List<AnimeCatalogModel>> searchCatalog(
    String query, {
    int limit = 20,
    CancelToken? cancelToken,
  });

  /// Получение прямых ссылок и озвучек напрямую через AniLiberty API
  Future<AnimePlayerDataModel> getPlayerLinks(int releaseId, {String? title});
}

class _CachedCatalogPage {
  final List<AnimeCatalogModel> items;
  final DateTime cachedAt;

  const _CachedCatalogPage({
    required this.items,
    required this.cachedAt,
  });
}

class AniLibertyAnimeRemoteDataSourceImpl implements AnimeRemoteDataSource {
  final Dio _dio;

  static const Duration _catalogCacheTtl = Duration(minutes: 2);
  final Map<String, Future<List<AnimeCatalogModel>>> _inFlightRequests = {};
  final Map<String, _CachedCatalogPage> _catalogCache = {};

  static const String _catalogUrl = 'https://anilibria.top/api/v1/anime/catalog/releases';
  static const String _genresReferenceUrl = 'https://anilibria.top/api/v1/anime/catalog/references/genres';
  static const String _searchUrl = 'https://anilibria.top/api/v1/app/search/releases';
  static const String _releaseUrl = 'https://anilibria.top/api/v1/anime/releases';

  static const String _fallbackCatalogUrl = 'https://api.anilibria.app/api/v1/anime/catalog/releases';
  static const String _fallbackGenresReferenceUrl = 'https://api.anilibria.app/api/v1/anime/catalog/references/genres';
  static const String _fallbackSearchUrl = 'https://api.anilibria.app/api/v1/app/search/releases';
  static const String _fallbackReleaseUrl = 'https://api.anilibria.app/api/v1/anime/releases';

  static const String _prefGenresKey = 'anilibria_genre_references_v1';
  static const String _prefGenresTsKey = 'anilibria_genre_references_ts_v1';
  static const Duration _genresCacheTtl = Duration(days: 7);

  final Map<String, int> _liveGenreNameToId = {};
  bool _hasLiveGenreReferences = false;
  Future<void>? _genresSyncInFlight;

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

  static String normalizeGenreKey(String raw) =>
      raw.trim().toLowerCase().replaceAll('ё', 'е').replaceAll('э', 'е');

  /// Синхронизация актуального справочника жанров AniLibria (кэш 7 дней в SharedPreferences).
  Future<void> syncGenreReferences({bool force = false}) {
    if (_genresSyncInFlight != null && !force) return _genresSyncInFlight!;
    final future = _syncGenreReferencesInternal(force: force).whenComplete(() {
      _genresSyncInFlight = null;
    });
    _genresSyncInFlight = future;
    return future;
  }

  Future<void> _syncGenreReferencesInternal({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!force) {
        final rawJson = prefs.getString(_prefGenresKey);
        final ts = prefs.getInt(_prefGenresTsKey) ?? 0;
        final isFresh = DateTime.now().millisecondsSinceEpoch - ts <
            _genresCacheTtl.inMilliseconds;
        if (rawJson != null && rawJson.isNotEmpty && isFresh) {
          final decoded = jsonDecode(rawJson);
          if (decoded is Map) {
            _liveGenreNameToId.clear();
            for (final entry in decoded.entries) {
              final id = int.tryParse('${entry.value}');
              if (id != null) {
                _liveGenreNameToId[normalizeGenreKey('${entry.key}')] = id;
              }
            }
            if (_liveGenreNameToId.isNotEmpty) {
              _hasLiveGenreReferences = true;
              return;
            }
          }
        }
      }

      dynamic data;
      try {
        final res = await _dio
            .get(_genresReferenceUrl)
            .timeout(const Duration(seconds: 6));
        data = res.data;
      } catch (_) {
        final fallback = await _dio
            .get(_fallbackGenresReferenceUrl)
            .timeout(const Duration(seconds: 6));
        data = fallback.data;
      }

      final List<dynamic> list = data is List
          ? data
          : (data is Map && data['data'] is List ? data['data'] as List : const []);
      final parsed = <String, int>{};
      for (final item in list) {
        if (item is Map) {
          final id = (item['id'] as num?)?.toInt();
          final name = item['name']?.toString() ?? '';
          if (id != null && name.trim().isNotEmpty) {
            parsed[normalizeGenreKey(name)] = id;
          }
        }
      }
      if (parsed.isNotEmpty) {
        _liveGenreNameToId
          ..clear()
          ..addAll(parsed);
        _hasLiveGenreReferences = true;
        await prefs.setString(_prefGenresKey, jsonEncode(parsed));
        await prefs.setInt(
          _prefGenresTsKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (_) {
      // В оффлайне используем встроенный fallback-словарь _genreNameToId
    }
  }

  /// Разрешение ID жанра: при наличии живого справочника берём только валидные серверные ID,
  /// чтобы не отправлять несуществующий ID (например, для «Исекай»).
  int? resolveGenreId(String rawGenre) {
    final key = normalizeGenreKey(rawGenre);
    if (_hasLiveGenreReferences) {
      return _liveGenreNameToId[key] ?? int.tryParse(key);
    }
    return _genreNameToId[key] ?? int.tryParse(key);
  }

  @visibleForTesting
  void setLiveGenreReferencesForTest(Map<String, int> map) {
    _liveGenreNameToId
      ..clear()
      ..addEntries(map.entries.map((e) => MapEntry(normalizeGenreKey(e.key), e.value)));
    _hasLiveGenreReferences = true;
  }

  @visibleForTesting
  void clearCatalogRequestCache() {
    _inFlightRequests.clear();
    _catalogCache.clear();
  }

  @override
  Future<List<AnimeCatalogModel>> getCatalog({
    int page = 1,
    int limit = 40,
    String? genres,
    String? year,
    String? sort,
    String? status,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken != null && cancelToken.isCancelled) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: _catalogUrl),
        reason: cancelToken.cancelError,
      );
    }

    if (!_hasLiveGenreReferences &&
        genres != null &&
        genres.trim().isNotEmpty &&
        genres.trim() != 'Все') {
      await syncGenreReferences();
    }

    // Нормализуем стандартные запросы (limit <= 40) к единому пулу limit=40,
    // чтобы дедуплицировать одновременные запросы виджетов и предзагрузки.
    final int fetchLimit = limit <= 40 ? 40 : limit;
    final String normalizedSort =
        (sort == null || sort.trim().isEmpty) ? 'updates' : sort.trim();

    final queryParams = <String, dynamic>{
      'page': page,
      'limit': fetchLimit,
    };
    if (genres != null && genres.trim().isNotEmpty && genres.trim() != 'Все') {
      final parts = genres
          .split(RegExp(r'[,;]+'))
          .map(normalizeGenreKey)
          .where((s) => s.isNotEmpty);
      final ids = <int>[];
      for (final p in parts) {
        final id = resolveGenreId(p);
        if (id != null && !ids.contains(id)) {
          ids.add(id);
        }
      }
      if (ids.isNotEmpty) {
        // AniLibria v1 expects f[genres] as comma-separated IDs (e.g. f[genres]=4 or f[genres]=4,14)
        queryParams['f[genres]'] = ids.join(',');
      }
    }
    if (year != null && year.trim().isNotEmpty) {
      queryParams['f[years][from_year]'] = year.trim();
      queryParams['f[years][to_year]'] = year.trim();
    }
    switch (normalizedSort) {
      case 'yearDesc':
        queryParams['f[sorting]'] = 'YEAR_DESC';
        break;
      case 'yearAsc':
        queryParams['f[sorting]'] = 'YEAR_ASC';
        break;
      case 'rating':
        queryParams['f[sorting]'] = 'RATING_DESC';
        break;
      case 'updates':
      default:
        queryParams['f[sorting]'] = 'FRESH_AT_DESC';
        break;
    }
    if (status != null && status.isNotEmpty) {
      if (status == 'ongoing') {
        queryParams['f[publish_statuses]'] = 'IS_ONGOING';
      } else if (status == 'released') {
        queryParams['f[publish_statuses]'] = 'IS_NOT_ONGOING';
      }
    }

    final dedupKey = 'p=$page|l=$fetchLimit'
        '|g=${queryParams['f[genres]'] ?? ''}'
        '|y=${queryParams['f[years][from_year]'] ?? ''}'
        '|s=${queryParams['f[sorting]'] ?? ''}'
        '|st=${queryParams['f[publish_statuses]'] ?? ''}';

    // 1. Мгновенная отдача из единого 40-элементного кэша (в 0мс)
    final cached = _catalogCache[dedupKey];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _catalogCacheTtl) {
      final items = cached.items;
      return limit < items.length ? items.take(limit).toList() : items;
    }

    // 2. Дедупликация активного in-flight запроса с изолированной обработкой CancelToken
    final Future<List<AnimeCatalogModel>> inFlightFuture =
        _inFlightRequests.putIfAbsent(dedupKey, () {
      return _executeCatalogFetch(queryParams).then((items) {
        if (items.isNotEmpty) {
          _catalogCache[dedupKey] = _CachedCatalogPage(
            items: items,
            cachedAt: DateTime.now(),
          );
        }
        return items;
      }).whenComplete(() {
        _inFlightRequests.remove(dedupKey);
      });
    });

    final List<AnimeCatalogModel> result;
    if (cancelToken != null) {
      result = await Future.any([
        inFlightFuture,
        cancelToken.whenCancel.then((err) => throw err),
      ]);
    } else {
      result = await inFlightFuture;
    }

    return limit < result.length ? result.take(limit).toList() : result;
  }

  Future<List<AnimeCatalogModel>> _executeCatalogFetch(
    Map<String, dynamic> queryParams,
  ) async {
    try {
      final response = await _dio
          .get(
            _catalogUrl,
            queryParameters: queryParams,
          )
          .timeout(const Duration(seconds: 10));
      final parsed = await _parseReleasesAsync(response.data);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
    } catch (_) {}

    try {
      final fallbackRes = await _dio
          .get(
            _fallbackCatalogUrl,
            queryParameters: queryParams,
          )
          .timeout(const Duration(seconds: 10));
      return await _parseReleasesAsync(fallbackRes.data);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw ServerException('Ошибка загрузки каталога AniLiberty: $e');
    } catch (e) {
      throw ServerException('Ошибка загрузки каталога AniLiberty: $e');
    }
  }

  @override
  Future<List<AnimeCatalogModel>> searchCatalog(
    String query, {
    int limit = 20,
    CancelToken? cancelToken,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return getCatalog(page: 1, limit: limit, cancelToken: cancelToken);
    }

    try {
      final response = await _dio.get(
        _searchUrl,
        queryParameters: {
          'query': clean,
        },
        cancelToken: cancelToken,
      );
      return await _parseReleasesAsync(response.data);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      try {
        final fallbackRes = await _dio.get(
          _fallbackSearchUrl,
          queryParameters: {
            'query': clean,
          },
          cancelToken: cancelToken,
        );
        return await _parseReleasesAsync(fallbackRes.data);
      } catch (e2) {
        throw ServerException('Ошибка поиска AniLiberty: $e2');
      }
    } catch (_) {
      try {
        final fallbackRes = await _dio.get(
          _fallbackSearchUrl,
          queryParameters: {
            'query': clean,
          },
          cancelToken: cancelToken,
        );
        return await _parseReleasesAsync(fallbackRes.data);
      } catch (e) {
        throw ServerException('Ошибка поиска AniLiberty: $e');
      }
    }
  }

  static final Map<int, String> _externalIdToReleaseIdCache = {};
  static final Map<String, String> _titleToReleaseIdCache = {};

  @override
  Future<AnimePlayerDataModel> getPlayerLinks(int releaseId, {String? title}) async {
    try {
      Response? res;
      final rawTitle = title?.trim() ?? '';
      final cleanTitle = rawTitle.startsWith('search:')
          ? rawTitle.substring('search:'.length).trim()
          : rawTitle;
      final normalizedTitleKey = cleanTitle.toLowerCase();

      final mappedId = _externalIdToReleaseIdCache[releaseId] ??
          (normalizedTitleKey.isNotEmpty ? _titleToReleaseIdCache[normalizedTitleKey] : null);

      // Если есть закэшированный маппинг или обычный AniLibria ID (> 0 и без search:), пробуем прямой запрос
      final effectiveId = mappedId ?? '$releaseId';
      final skipDirectIdLookup =
          (mappedId == null && releaseId <= 0) || rawTitle.startsWith('search:');

      if (!skipDirectIdLookup) {
        try {
          res = await _dio.get('$_releaseUrl/$effectiveId');
        } catch (_) {
          res = null;
        }
      }

      if (res == null && cleanTitle.isNotEmpty) {
        try {
          final sRes = await _dio.get(
            _searchUrl,
            queryParameters: {'query': cleanTitle},
          );
          final items = _parseReleases(sRes.data);
          if (items.isNotEmpty) {
            final relId = items.first.id;
            if (releaseId > 0) _externalIdToReleaseIdCache[releaseId] = relId;
            if (normalizedTitleKey.isNotEmpty) {
              _titleToReleaseIdCache[normalizedTitleKey] = relId;
            }
            res = await _dio.get('$_releaseUrl/$relId');
          }
        } catch (_) {}
      }

      if (res == null && cleanTitle.isNotEmpty) {
        try {
          final fallbackSRes = await _dio.get(
            _fallbackSearchUrl,
            queryParameters: {'query': cleanTitle},
          );
          final items = _parseReleases(fallbackSRes.data);
          if (items.isNotEmpty) {
            final relId = items.first.id;
            if (releaseId > 0) _externalIdToReleaseIdCache[releaseId] = relId;
            if (normalizedTitleKey.isNotEmpty) {
              _titleToReleaseIdCache[normalizedTitleKey] = relId;
            }
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
