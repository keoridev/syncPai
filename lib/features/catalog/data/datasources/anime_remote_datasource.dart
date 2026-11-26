import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/catalog_filter.dart';
import '../../domain/entities/catalog_filter_query.dart';
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

class CatalogGenreRef {
  final int id;
  final String name;

  const CatalogGenreRef({
    required this.id,
    required this.name,
  });

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory CatalogGenreRef.fromJson(Map<String, dynamic> json) {
    return CatalogGenreRef(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString().trim(),
    );
  }
}

abstract class AnimeRemoteDataSource {
  /// Живой список жанров AniLibria, отсортированный по русскому алфавиту
  List<CatalogGenreRef> get liveGenres;

  /// Загрузка и кэширование справочника жанров AniLibria (`/api/v1/anime/catalog/references/genres`)
  Future<List<CatalogGenreRef>> syncGenreReferences({bool force = false});

  /// Получение каталога по декларативному фильтру AniLibria v1
  Future<List<AnimeCatalogModel>> getReleases({
    required CatalogFilter filter,
    int page = 1,
    int limit = 40,
    CancelToken? cancelToken,
  });

  /// Получение недельного расписания `/api/v1/anime/schedule/week`
  Future<List<AnimeCatalogModel>> getScheduleWeek({
    CancelToken? cancelToken,
  });

  /// Получение каталога напрямую через AniLiberty (AniLibria v1) API / Supabase anime_catalog
  Future<List<AnimeCatalogModel>> getCatalog({
    int page = 1,
    int limit = 40,
    String? genres,
    String? year,
    String? sort,
    String? status,
    String? types,
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
  static const String _scheduleWeekUrl = 'https://anilibria.top/api/v1/anime/schedule/week';
  static const String _genresReferenceUrl = 'https://anilibria.top/api/v1/anime/catalog/references/genres';
  static const String _searchUrl = 'https://anilibria.top/api/v1/app/search/releases';
  static const String _releaseUrl = 'https://anilibria.top/api/v1/anime/releases';

  static const String _fallbackCatalogUrl = 'https://api.anilibria.app/api/v1/anime/catalog/releases';
  static const String _fallbackScheduleWeekUrl = 'https://api.anilibria.app/api/v1/anime/schedule/week';
  static const String _fallbackGenresReferenceUrl = 'https://api.anilibria.app/api/v1/anime/catalog/references/genres';
  static const String _fallbackSearchUrl = 'https://api.anilibria.app/api/v1/app/search/releases';
  static const String _fallbackReleaseUrl = 'https://api.anilibria.app/api/v1/anime/releases';

  static const String _prefGenresKey = 'anilibria_genre_references_v1';
  static const String _prefGenresListKey = 'anilibria_genre_references_list_v2';
  static const String _prefGenresTsKey = 'anilibria_genre_references_ts_v1';
  static const Duration _genresCacheTtl = Duration(days: 7);

  final Map<String, int> _liveGenreNameToId = {};
  final List<CatalogGenreRef> _liveGenreEntries = [];
  bool _hasLiveGenreReferences = false;
  Future<List<CatalogGenreRef>>? _genresSyncInFlight;

  @override
  List<CatalogGenreRef> get liveGenres => List.unmodifiable(_liveGenreEntries);

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

  static const Set<String> virtualDemographicTags = {
    'сенен',
    'сейнен',
    'сейдзе',
    'седзе',
    'дзесей',
    'исекай',
  };

  static String normalizeGenreKey(String raw) =>
      raw.trim().toLowerCase().replaceAll('ё', 'е').replaceAll('э', 'е');

  static int _compareRussianNames(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  void _applyGenreEntries(List<CatalogGenreRef> entries) {
    final dedupById = <int, CatalogGenreRef>{};
    for (final entry in entries) {
      if (entry.id > 0 && entry.name.trim().isNotEmpty) {
        dedupById[entry.id] = CatalogGenreRef(
          id: entry.id,
          name: entry.name.trim(),
        );
      }
    }
    final sorted = dedupById.values.toList()
      ..sort((a, b) => _compareRussianNames(a.name, b.name));

    _liveGenreEntries
      ..clear()
      ..addAll(sorted);
    _liveGenreNameToId.clear();
    for (final item in sorted) {
      _liveGenreNameToId[normalizeGenreKey(item.name)] = item.id;
    }
    _hasLiveGenreReferences = sorted.isNotEmpty;
  }

  /// Синхронизация актуального справочника жанров AniLibria (кэш 7 дней в SharedPreferences).
  @override
  Future<List<CatalogGenreRef>> syncGenreReferences({bool force = false}) {
    if (_genresSyncInFlight != null && !force) return _genresSyncInFlight!;
    final future = _syncGenreReferencesInternal(force: force).whenComplete(() {
      _genresSyncInFlight = null;
    });
    _genresSyncInFlight = future;
    return future;
  }

  Future<List<CatalogGenreRef>> _syncGenreReferencesInternal({
    bool force = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!force) {
        final ts = prefs.getInt(_prefGenresTsKey) ?? 0;
        final isFresh = DateTime.now().millisecondsSinceEpoch - ts <
            _genresCacheTtl.inMilliseconds;
        final rawListJson = prefs.getString(_prefGenresListKey);
        if (rawListJson != null && rawListJson.isNotEmpty && isFresh) {
          final decoded = jsonDecode(rawListJson);
          if (decoded is List) {
            final restored = decoded
                .whereType<Map>()
                .map((m) => CatalogGenreRef.fromJson(Map<String, dynamic>.from(m)))
                .where((r) => r.id > 0 && r.name.isNotEmpty)
                .toList();
            if (restored.isNotEmpty) {
              _applyGenreEntries(restored);
              return liveGenres;
            }
          }
        }
        final rawJson = prefs.getString(_prefGenresKey);
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
              // Если старый формат кэша не хранил display name, подгружаем полный список ниже
              if (_liveGenreEntries.isNotEmpty) {
                return liveGenres;
              }
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
      final parsedEntries = <CatalogGenreRef>[];
      for (final item in list) {
        if (item is Map) {
          final id = (item['id'] as num?)?.toInt();
          final name = item['name']?.toString().trim() ?? '';
          if (id != null && name.isNotEmpty) {
            parsedEntries.add(CatalogGenreRef(id: id, name: name));
          }
        }
      }
      if (parsedEntries.isNotEmpty) {
        _applyGenreEntries(parsedEntries);
        await prefs.setString(
          _prefGenresListKey,
          jsonEncode(_liveGenreEntries.map((e) => e.toJson()).toList()),
        );
        await prefs.setString(_prefGenresKey, jsonEncode(_liveGenreNameToId));
        await prefs.setInt(
          _prefGenresTsKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (_) {
      // В оффлайне используем встроенный fallback-словарь _genreNameToId
    }
    return liveGenres;
  }

  /// Разрешение ID жанра: для виртуальных/демографических тегов («Сёнен», «Сэйнэн», «Сёдзё»,
  /// «Дзёсэй», «Исекай») возвращаем null, чтобы не отправлять невалидный `f[genres]` (422) на AniLibria.
  int? resolveGenreId(String rawGenre) {
    final key = normalizeGenreKey(rawGenre);
    if (virtualDemographicTags.contains(key)) {
      return null;
    }
    if (_hasLiveGenreReferences) {
      return _liveGenreNameToId[key] ?? int.tryParse(key);
    }
    return _genreNameToId[key] ?? int.tryParse(key);
  }

  @visibleForTesting
  void setLiveGenreReferencesForTest(Map<String, int> map) {
    final entries = <CatalogGenreRef>[
      for (final e in map.entries)
        CatalogGenreRef(id: e.value, name: e.key.trim()),
    ];
    _applyGenreEntries(entries);
    _liveGenreNameToId
      ..clear()
      ..addEntries(
        map.entries.map((e) => MapEntry(normalizeGenreKey(e.key), e.value)),
      );
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
    String? types,
    CancelToken? cancelToken,
  }) async {
    if (!_hasLiveGenreReferences &&
        genres != null &&
        genres.trim().isNotEmpty &&
        genres.trim() != 'Все') {
      await syncGenreReferences();
    }

    final genreIds = <int>[];
    if (genres != null && genres.trim().isNotEmpty && genres.trim() != 'Все') {
      final parts = genres
          .split(RegExp(r'[,;]+'))
          .map(normalizeGenreKey)
          .where((s) => s.isNotEmpty);
      for (final p in parts) {
        final id = resolveGenreId(p);
        if (id != null && !genreIds.contains(id)) {
          genreIds.add(id);
        }
      }
    }

    final parsedYear =
        (year != null && year.trim().isNotEmpty) ? int.tryParse(year.trim()) : null;

    final CatalogSorting sorting;
    switch ((sort ?? '').trim()) {
      case 'yearDesc':
        sorting = CatalogSorting.yearDesc;
        break;
      case 'yearAsc':
        sorting = CatalogSorting.yearAsc;
        break;
      case 'rating':
        sorting = CatalogSorting.ratingDesc;
        break;
      case 'updates':
      default:
        sorting = CatalogSorting.freshAtDesc;
        break;
    }

    final publishStatuses = <PublishStatus>[];
    final productionStatuses = <ProductionStatus>[];
    if (status != null && status.isNotEmpty) {
      if (status == 'ongoing') {
        publishStatuses.add(PublishStatus.isOngoing);
      } else if (status == 'released') {
        publishStatuses.add(PublishStatus.isNotOngoing);
      } else if (status == 'anons' || status == 'anonses') {
        productionStatuses.add(ProductionStatus.isInProduction);
      }
    }

    final parsedTypes = <ReleaseType>[];
    if (types != null && types.trim().isNotEmpty) {
      for (final part in types.split(',')) {
        final t = ReleaseType.fromApi(part);
        if (t != null && !parsedTypes.contains(t)) {
          parsedTypes.add(t);
        }
      }
    }

    final filter = CatalogFilter(
      sorting: sorting,
      genres: genreIds,
      types: parsedTypes,
      publishStatuses: publishStatuses,
      productionStatuses: productionStatuses,
      yearFrom: parsedYear,
      yearTo: parsedYear,
    );

    return getReleases(
      filter: filter,
      page: page,
      limit: limit,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<List<AnimeCatalogModel>> getReleases({
    required CatalogFilter filter,
    int page = 1,
    int limit = 40,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken != null && cancelToken.isCancelled) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: _catalogUrl),
        reason: cancelToken.cancelError,
      );
    }

    // Нормализуем стандартные запросы (limit <= 40) к единому пулу limit=40,
    // чтобы дедуплицировать одновременные запросы виджетов и предзагрузки.
    final int fetchLimit = limit <= 40 ? 40 : limit;
    final queryParams = filter.toQueryParameters(page: page, limit: fetchLimit);
    final dedupKey = '${filter.signature}|p=$page|l=$fetchLimit';

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

  bool _isEmptyBody(dynamic data) {
    if (data == null) return true;
    if (data is String && data.trim().isEmpty) return true;
    return false;
  }

  Future<List<AnimeCatalogModel>> _executeCatalogFetch(
    Map<String, dynamic> queryParams,
  ) async {
    Future<List<AnimeCatalogModel>> fetchWithParams(
      Map<String, dynamic> params,
    ) async {
      try {
        final response = await _dio
            .get(_catalogUrl, queryParameters: params)
            .timeout(const Duration(seconds: 10));
        if (!_isEmptyBody(response.data)) {
          final parsed = await _parseReleasesAsync(response.data);
          if (parsed.isNotEmpty) {
            return parsed;
          }
        }
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
      } catch (_) {}

      final fallbackRes = await _dio
          .get(_fallbackCatalogUrl, queryParameters: params)
          .timeout(const Duration(seconds: 10));
      if (_isEmptyBody(fallbackRes.data)) return const [];
      return await _parseReleasesAsync(fallbackRes.data);
    }

    try {
      return await fetchWithParams(queryParams);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw ServerException('Ошибка загрузки каталога AniLiberty: $e');
    } catch (e) {
      throw ServerException('Ошибка загрузки каталога AniLiberty: $e');
    }
  }

  @override
  Future<List<AnimeCatalogModel>> getScheduleWeek({
    CancelToken? cancelToken,
  }) async {
    if (cancelToken != null && cancelToken.isCancelled) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: _scheduleWeekUrl),
        reason: cancelToken.cancelError,
      );
    }

    const dedupKey = _scheduleWeekUrl;
    final cached = _catalogCache[dedupKey];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _catalogCacheTtl) {
      return cached.items;
    }

    Future<List<AnimeCatalogModel>> parseSchedule(dynamic raw) async {
      if (_isEmptyBody(raw)) return const [];
      final list = raw is List
          ? raw
          : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
      final items = <Map<String, dynamic>>[];
      for (final entry in list) {
        if (entry is Map && entry['release'] is Map) {
          items.add(Map<String, dynamic>.from(entry['release'] as Map));
        } else if (entry is Map<String, dynamic>) {
          items.add(entry);
        }
      }
      return items.map((j) => AnimeCatalogModel.fromJson(j)).toList();
    }

    final inFlightFuture = _inFlightRequests.putIfAbsent(dedupKey, () {
      return () async {
        try {
          final response = await _dio
              .get(_scheduleWeekUrl)
              .timeout(const Duration(seconds: 10));
          final parsed = await parseSchedule(response.data);
          if (parsed.isNotEmpty) {
            _catalogCache[dedupKey] = _CachedCatalogPage(
              items: parsed,
              cachedAt: DateTime.now(),
            );
            return parsed;
          }
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) rethrow;
        } catch (_) {}

        final fallback = await _dio
            .get(_fallbackScheduleWeekUrl)
            .timeout(const Duration(seconds: 10));
        final parsed = await parseSchedule(fallback.data);
        if (parsed.isNotEmpty) {
          _catalogCache[dedupKey] = _CachedCatalogPage(
            items: parsed,
            cachedAt: DateTime.now(),
          );
        }
        return parsed;
      }()
          .whenComplete(() {
        _inFlightRequests.remove(dedupKey);
      });
    });

    if (cancelToken != null) {
      return Future.any([
        inFlightFuture,
        cancelToken.whenCancel.then((err) => throw err),
      ]);
    }
    return inFlightFuture;
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

    return _searchReleasesDeduplicated(clean, cancelToken: cancelToken);
  }

  static final Map<String, Future<List<AnimeCatalogModel>>> _inFlightSearches = {};
  static final Set<String> _emptySearchCache = {};

  static String _stripSubtitle(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '';

    final bangIdx = trimmed.indexOf('!');
    if (bangIdx != -1 && bangIdx < trimmed.length - 1) {
      return trimmed.substring(0, bangIdx + 1).trim();
    }
    for (final sep in [':', '~', '(']) {
      final idx = trimmed.indexOf(sep);
      if (idx > 2) {
        return trimmed.substring(0, idx).trim();
      }
    }
    return trimmed;
  }

  Future<List<AnimeCatalogModel>> _searchReleasesDeduplicated(
    String query, {
    CancelToken? cancelToken,
  }) {
    final clean = query.trim();
    final key = clean.toLowerCase();
    if (clean.isEmpty ||
        _placeholderTitleRegex.hasMatch(clean) ||
        _emptySearchCache.contains(key)) {
      return Future.value(const []);
    }

    final existing = _inFlightSearches[key];
    if (existing != null) {
      return existing;
    }

    final future = () async {
      try {
        var results = await _executeSingleSearch(clean, cancelToken: cancelToken);
        if (results.isEmpty) {
          final baseTitle = _stripSubtitle(clean);
          final baseKey = baseTitle.toLowerCase();
          if (baseTitle.isNotEmpty &&
              baseKey != key &&
              !_emptySearchCache.contains(baseKey)) {
            results = await _executeSingleSearch(baseTitle, cancelToken: cancelToken);
            if (results.isEmpty) {
              _emptySearchCache.add(baseKey);
            }
          }
        }
        if (results.isEmpty) {
          _emptySearchCache.add(key);
        }
        return results;
      } finally {
        _inFlightSearches.remove(key);
      }
    }();

    _inFlightSearches[key] = future;
    return future;
  }

  Future<List<AnimeCatalogModel>> _executeSingleSearch(
    String clean, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get(
        _searchUrl,
        queryParameters: {'query': clean},
        cancelToken: cancelToken,
      );
      return await _parseReleasesAsync(response.data);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      try {
        final fallbackRes = await _dio.get(
          _fallbackSearchUrl,
          queryParameters: {'query': clean},
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
          queryParameters: {'query': clean},
          cancelToken: cancelToken,
        );
        return await _parseReleasesAsync(fallbackRes.data);
      } catch (e) {
        throw ServerException('Ошибка поиска AniLiberty: $e');
      }
    }
  }

  static final Map<int, String> _externalIdToReleaseIdCache = {};
  static final RegExp _placeholderTitleRegex = RegExp(
    r'^(Аниме #\d+|(?:shiki|shikimori|mal|kodik|saved|rel)_[\w-]*)$',
    caseSensitive: false,
  );

  static int? _extractSequelNumber(String raw) {
    final s = raw.toLowerCase().trim();
    if (s.isEmpty) return null;
    final explicit = RegExp(
      r'(?:сезон|season|часть|part|cour)\s*(\d+)|(\d+)\s*(?:сезон|season|nd\s*season|rd\s*season|th\s*season)',
    ).firstMatch(s);
    if (explicit != null) {
      return int.tryParse(explicit.group(1) ?? explicit.group(2) ?? '');
    }
    final trailingNum = RegExp(r'(?:^|\s)([2-9]|1\d)(?:\s|$)').firstMatch(s);
    if (trailingNum != null) {
      return int.tryParse(trailingNum.group(1) ?? '');
    }
    final roman = RegExp(r'\b(ii|iii|iv|v)\b$').firstMatch(s);
    if (roman != null) {
      switch (roman.group(1)) {
        case 'ii':
          return 2;
        case 'iii':
          return 3;
        case 'iv':
          return 4;
        case 'v':
          return 5;
      }
    }
    return null;
  }

  static bool _isMovieTitle(String raw) {
    final s = raw.toLowerCase();
    return s.contains('фильм') ||
        s.contains('movie') ||
        s.contains('gekijouban');
  }

  static int? _extractYearHint(String raw) {
    final m = RegExp(r'\b(19\d{2}|20[2-3]\d)\b').firstMatch(raw);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }
  static final Map<String, String> _titleToReleaseIdCache = {};
  static final Map<int, Future<AnimePlayerDataModel>> _inFlightPlayerLinks = {};
  static final Map<String, Future<AnimePlayerDataModel>> _inFlightPlayerLinksByKey = {};
  static final Map<int, AnimePlayerDataModel> _playerLinksCache = {};
  static final Map<String, AnimePlayerDataModel> _playerLinksCacheByKey = {};
  static final Set<int> _missingReleaseIds = {};

  @override
  Future<AnimePlayerDataModel> getPlayerLinks(int releaseId, {String? title}) async {
    if (releaseId > 0) {
      final cached = _playerLinksCache[releaseId];
      if (cached != null) return cached;
      final inFlight = _inFlightPlayerLinks[releaseId];
      if (inFlight != null) return inFlight;

      final future = _fetchPlayerLinksInternal(releaseId, title: title);
      _inFlightPlayerLinks[releaseId] = future;
      try {
        final result = await future;
        if (result.episodes.isNotEmpty) {
          _playerLinksCache[releaseId] = result;
        }
        return result;
      } finally {
        _inFlightPlayerLinks.remove(releaseId);
      }
    }

    final key = (title ?? '').trim().toLowerCase();
    if (key.isNotEmpty) {
      final cached = _playerLinksCacheByKey[key];
      if (cached != null) return cached;
      final inFlight = _inFlightPlayerLinksByKey[key];
      if (inFlight != null) return inFlight;
      final future = _fetchPlayerLinksInternal(releaseId, title: title);
      _inFlightPlayerLinksByKey[key] = future;
      try {
        final result = await future;
        if (result.episodes.isNotEmpty) {
          _playerLinksCacheByKey[key] = result;
        }
        return result;
      } finally {
        _inFlightPlayerLinksByKey.remove(key);
      }
    }

    return _fetchPlayerLinksInternal(releaseId, title: title);
  }

  Future<AnimePlayerDataModel> _fetchPlayerLinksInternal(
    int releaseId, {
    String? title,
  }) async {
    try {
      Response? res;
      final rawTitle = title?.trim() ?? '';
      final cleanTitle = rawTitle.startsWith('search:')
          ? rawTitle.substring('search:'.length).trim()
          : rawTitle;
      final isSearchableTitle =
          cleanTitle.isNotEmpty && !_placeholderTitleRegex.hasMatch(cleanTitle);
      final normalizedTitleKey = cleanTitle.toLowerCase();

      final mappedId = _externalIdToReleaseIdCache[releaseId] ??
          (normalizedTitleKey.isNotEmpty ? _titleToReleaseIdCache[normalizedTitleKey] : null);

      // Пропускаем прямой запрос, если это Shikimori ID (> 12000 без маппинга) или ID уже вернул 404
      final effectiveId = mappedId ?? '$releaseId';
      final isLikelyExternalShikimoriId =
          mappedId == null && releaseId > 12000 && isSearchableTitle;
      final skipDirectIdLookup =
          (mappedId == null && releaseId <= 0) ||
          rawTitle.startsWith('search:') ||
          isLikelyExternalShikimoriId ||
          (mappedId == null && _missingReleaseIds.contains(releaseId));

      if (!skipDirectIdLookup) {
        try {
          res = await _dio.get('$_releaseUrl/$effectiveId');
        } on DioException catch (e) {
          if (e.response?.statusCode == 404 && releaseId > 0 && mappedId == null) {
            _missingReleaseIds.add(releaseId);
          }
          res = null;
        } catch (_) {
          res = null;
        }
      }

      if (res == null && isSearchableTitle) {
        try {
          final items = await _searchReleasesDeduplicated(cleanTitle);
          AnimeCatalogModel? bestMatch;
          double bestScore = 0.0;
          final targetSeason = _extractSequelNumber(cleanTitle);
          final targetIsMovie = _isMovieTitle(cleanTitle);
          final targetYear = _extractYearHint(cleanTitle);
          final targetTokens = normalizedTitleKey
              .replaceAll('ё', 'е')
              .replaceAll(RegExp(r'[^a-zа-я0-9\s]'), ' ')
              .split(RegExp(r'\s+'))
              .where((w) => w.length >= 2)
              .toSet();
          for (final item in items) {
            final candRaw = '${item.titleRu} ${item.titleEn}'.trim();
            final candSeason = _extractSequelNumber(item.titleRu) ??
                _extractSequelNumber(item.titleEn);
            // Строгий фильтр сиквелов: 2-й+ сезон или фильм не должен матчиться на 1-й сезон
            if (targetSeason != null && targetSeason > 1) {
              if (candSeason != targetSeason) continue;
            } else if (targetSeason == null &&
                candSeason != null &&
                candSeason > 1) {
              continue;
            }
            if (targetIsMovie != _isMovieTitle(candRaw)) {
              continue;
            }
            if (targetYear != null &&
                item.year != null &&
                item.year! < targetYear) {
              continue;
            }
            final candNorm = candRaw
                .toLowerCase()
                .replaceAll('ё', 'е')
                .replaceAll(RegExp(r'[^a-zа-я0-9\s]'), ' ');
            final candTokens = candNorm
                .split(RegExp(r'\s+'))
                .where((w) => w.length >= 2)
                .toSet();
            if (targetTokens.isEmpty || candTokens.isEmpty) continue;
            final overlap = targetTokens.intersection(candTokens).length;
            final score = overlap / targetTokens.union(candTokens).length;
            if (score > bestScore) {
              bestScore = score;
              bestMatch = item;
            }
          }
          if (bestMatch != null && bestScore >= 0.45) {
            final relId = bestMatch.id.toString();
            if (releaseId > 0) _externalIdToReleaseIdCache[releaseId] = relId;
            if (normalizedTitleKey.isNotEmpty) {
              _titleToReleaseIdCache[normalizedTitleKey] = relId;
            }
            try {
              res = await _dio.get('$_releaseUrl/$relId');
            } catch (_) {
              res = await _dio.get('$_fallbackReleaseUrl/$relId');
            }
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
}

typedef ShikimoriAnimeRemoteDataSourceImpl = AniLibertyAnimeRemoteDataSourceImpl;
typedef SupabaseAnimeRemoteDataSourceImpl = AniLibertyAnimeRemoteDataSourceImpl;
