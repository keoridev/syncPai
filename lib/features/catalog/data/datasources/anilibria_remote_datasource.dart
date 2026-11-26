import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../models/anime_title_dto.dart';

/// Top-level функция для парсинга списка релизов AniLibria в изоляте через compute()
List<AnimeTitleDto> parseAnilibriaDtosInIsolate(dynamic data) {
  final List<dynamic> list;
  if (data is List) {
    list = data;
  } else if (data is Map<String, dynamic> && data['data'] is List) {
    list = data['data'] as List;
  } else {
    list = [];
  }
  return list
      .whereType<Map<String, dynamic>>()
      .map((item) => AnimeTitleDto.fromJson(item))
      .toList();
}

/// Top-level функция для парсинга полного релиза с эпизодами в изоляте через compute()
AnimeTitleDto parseSingleAnilibriaDtoInIsolate(Map<String, dynamic> map) {
  final releaseData = map.containsKey('data') && map['data'] is Map<String, dynamic>
      ? map['data'] as Map<String, dynamic>
      : map;
  return AnimeTitleDto.fromJson(releaseData);
}

abstract class AnilibriaRemoteDataSource {
  Future<List<AnimeTitleDto>> getUpdates({int page = 1, int limit = 30});
  Future<List<AnimeTitleDto>> searchTitles(String query, {int limit = 30});
  Future<AnimeTitleDto> getTitleDetails({int? id, String? code});
}

class AnilibriaRemoteDataSourceImpl implements AnilibriaRemoteDataSource {
  final DioClient client;
  final Map<String, Future<Response<dynamic>>> _inFlightQueries = {};

  AnilibriaRemoteDataSourceImpl(this.client);

  bool _isEmptyBody(dynamic data) {
    if (data == null) return true;
    if (data is String && data.trim().isEmpty) return true;
    return false;
  }

  String _buildDedupKey(String path, Map<String, dynamic>? queryParameters) {
    if (queryParameters == null || queryParameters.isEmpty) {
      return '${ApiConstants.baseUrl}$path';
    }
    final sortedKeys = queryParameters.keys.toList()..sort();
    final queryStr = sortedKeys
        .map((k) => '$k=${queryParameters[k]}')
        .join('&');
    return '${ApiConstants.baseUrl}$path?$queryStr';
  }

  Future<Response<dynamic>> _getWithMirrorFailover(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    final dedupKey = _buildDedupKey(path, queryParameters);
    return _inFlightQueries.putIfAbsent(dedupKey, () async {
      try {
        Response<dynamic> response;
        try {
          response = await client.get(
            path,
            queryParameters: queryParameters,
          );
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (e is FormatException ||
              msg.contains('the document is empty') ||
              msg.contains('formatexception')) {
            return await client.get(
              '${ApiConstants.fallbackBaseUrl}$path',
              queryParameters: queryParameters,
              options: Options(extra: const {'disable_mirror_rewrite': true}),
            );
          }
          rethrow;
        }

        if (_isEmptyBody(response.data)) {
          final fallbackResponse = await client.get(
            '${ApiConstants.fallbackBaseUrl}$path',
            queryParameters: queryParameters,
            options: Options(extra: const {'disable_mirror_rewrite': true}),
          );
          return fallbackResponse;
        }

        return response;
      } finally {
        _inFlightQueries.remove(dedupKey);
      }
    });
  }

  @override
  Future<List<AnimeTitleDto>> getUpdates({int page = 1, int limit = 40}) async {
    // Клиентский слой больше не обращается к anilibria.top для списков аниме (каталог работает через Shikimori)
    return const [];
  }

  static final RegExp _placeholderTitleRegex = RegExp(r'^Аниме #\d+$');
  static final Map<int, int> _shikimoriToAnilibriaIdCache = {};
  static final Map<int, Future<AnimeTitleDto>> _inFlightReleaseRequests = {};
  static final Map<int, AnimeTitleDto> _releaseCache = {};
  static final Set<int> _missingReleaseIds = {};
  static final Map<String, Future<List<AnimeTitleDto>>> _inFlightSearchRequests = {};
  static final Map<String, List<AnimeTitleDto>> _searchCache = {};
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

  static final RegExp _slugQueryRegex = RegExp(
    r'^(shiki|shikimori|mal|kodik|saved|rel)_\d*$',
    caseSensitive: false,
  );

  @override
  Future<List<AnimeTitleDto>> searchTitles(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty ||
        _slugQueryRegex.hasMatch(trimmed) ||
        _placeholderTitleRegex.hasMatch(trimmed)) {
      return const [];
    }
    final cacheKey = trimmed.toLowerCase();
    if (_emptySearchCache.contains(cacheKey)) return const [];
    final cached = _searchCache[cacheKey];
    if (cached != null) return cached;
    final inFlight = _inFlightSearchRequests[cacheKey];
    if (inFlight != null) return inFlight;

    final future = () async {
      var result = await _executeSearchTitles(trimmed);
      if (result.isEmpty) {
        final baseTitle = _stripSubtitle(trimmed);
        final baseKey = baseTitle.toLowerCase();
        if (baseTitle.isNotEmpty &&
            baseKey != cacheKey &&
            !_emptySearchCache.contains(baseKey)) {
          result = _searchCache[baseKey] ?? await _executeSearchTitles(baseTitle);
          if (result.isEmpty) {
            _emptySearchCache.add(baseKey);
          }
        }
      }
      if (result.isNotEmpty) {
        _searchCache[cacheKey] = result;
      } else {
        _emptySearchCache.add(cacheKey);
      }
      return result;
    }();

    _inFlightSearchRequests[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inFlightSearchRequests.remove(cacheKey);
    }
  }

  Future<List<AnimeTitleDto>> _executeSearchTitles(String trimmed) async {
    if (trimmed.isEmpty ||
        _slugQueryRegex.hasMatch(trimmed) ||
        _placeholderTitleRegex.hasMatch(trimmed)) {
      return const [];
    }
    try {
      final response = await _getWithMirrorFailover(
        ApiConstants.searchReleases,
        queryParameters: {
          'query': trimmed,
        },
      );

      final data = response.data;
      if (_isEmptyBody(data)) {
        return const [];
      }
      final isTest = Platform.environment.containsKey('FLUTTER_TEST');
      if (isTest) {
        return parseAnilibriaDtosInIsolate(data);
      }
      return await compute(parseAnilibriaDtosInIsolate, data);
    } catch (e) {
      if (e is ServerException || e is NetworkException) rethrow;
      throw ParsingException('Не удалось выполнить поиск: $e');
    }
  }

  @override
  Future<AnimeTitleDto> getTitleDetails({int? id, String? code}) async {
    if (id != null && id > 0) {
      final cached = _releaseCache[id];
      if (cached != null) return cached;
      if (_missingReleaseIds.contains(id)) {
        return _buildFallbackShikimoriDto(id: id, code: code);
      }
      final inFlight = _inFlightReleaseRequests[id];
      if (inFlight != null) return inFlight;

      final future = _getTitleDetailsInternal(id: id, code: code);
      _inFlightReleaseRequests[id] = future;
      try {
        final result = await future;
        if (result.id > 0 && !_placeholderTitleRegex.hasMatch(result.russianTitle)) {
          _releaseCache[id] = result;
        }
        return result;
      } finally {
        _inFlightReleaseRequests.remove(id);
      }
    }
    return _getTitleDetailsInternal(id: id, code: code);
  }

  Future<AnimeTitleDto> _getTitleDetailsInternal({int? id, String? code}) async {
    try {
      final rawCode = code?.trim() ?? '';
      // 1. Если передан search:-токен — сразу снимаем префикс и идём в поиск без 404 по /releases/search:...
      if (rawCode.startsWith('search:')) {
        final cleanQuery = rawCode.substring('search:'.length).trim();
        if (cleanQuery.isNotEmpty) {
          final searchResults = await searchTitles(cleanQuery);
          if (searchResults.isNotEmpty) {
            if (id != null && id > 0) {
              _shikimoriToAnilibriaIdCache[id] = searchResults.first.id;
            }
            return searchResults.first;
          }
        }
        return _buildFallbackShikimoriDto(id: id, code: cleanQuery);
      }

      final isShikimoriCode =
          rawCode.startsWith('shikimori_') || rawCode.startsWith('shiki_');
      final resolvedId = (id != null && _shikimoriToAnilibriaIdCache.containsKey(id))
          ? _shikimoriToAnilibriaIdCache[id]
          : id;

      // Если код вида shikimori_<id> или внешний ID (> 12000) ещё не сопоставлен с AniLibria ID — не делаем заведомый 404-запрос
      final isUnmappedExternalId = id != null &&
          id > 12000 &&
          !_shikimoriToAnilibriaIdCache.containsKey(id);
      if ((isShikimoriCode &&
              (id == null || !_shikimoriToAnilibriaIdCache.containsKey(id))) ||
          isUnmappedExternalId) {
        return _buildFallbackShikimoriDto(id: id, code: rawCode);
      }

      final hasValidCode =
          rawCode.isNotEmpty && !rawCode.startsWith('saved_') && !isShikimoriCode;
      final target = resolvedId != null ? '$resolvedId' : rawCode;
      final path = '${ApiConstants.releaseDetails}/$target';

      Response<dynamic>? response;
      try {
        response = await _getWithMirrorFailover(path);
      } catch (err) {
        if (hasValidCode &&
            target != rawCode &&
            !_placeholderTitleRegex.hasMatch(rawCode)) {
          try {
            response = await _getWithMirrorFailover(
              '${ApiConstants.releaseDetails}/$rawCode',
            );
          } catch (_) {
            try {
              final searchResults = await searchTitles(rawCode);
              if (searchResults.isNotEmpty) {
                if (id != null && id > 0) {
                  _shikimoriToAnilibriaIdCache[id] = searchResults.first.id;
                }
                return searchResults.first;
              }
            } catch (_) {}
          }
        }

        if (response == null) {
          if (id != null && id > 0) {
            _missingReleaseIds.add(id);
          }
          return _buildFallbackShikimoriDto(id: id, code: rawCode);
        }
      }

      if (_isEmptyBody(response.data)) {
        return _buildFallbackShikimoriDto(id: id, code: rawCode);
      }

      if (response.data is Map<String, dynamic>) {
        final map = response.data as Map<String, dynamic>;
        final isTest = Platform.environment.containsKey('FLUTTER_TEST');
        if (isTest) {
          return parseSingleAnilibriaDtoInIsolate(map);
        }
        return await compute(parseSingleAnilibriaDtoInIsolate, map);
      }
      throw const ParsingException('Некорректный формат ответа тайтла');
    } catch (e) {
      if (e is ServerException || e is NetworkException) rethrow;
      throw ParsingException('Не удалось загрузить данные тайтла: $e');
    }
  }

  AnimeTitleDto _buildFallbackShikimoriDto({int? id, String? code}) {
    final poster = (id != null && id > 0)
        ? 'https://shikimori.io/system/animes/original/$id.jpg'
        : '';
    final cleanCode = (code != null && code.isNotEmpty) ? code : 'shikimori_${id ?? 0}';
    return AnimeTitleDto(
      id: id ?? 0,
      code: cleanCode,
      russianTitle: (code != null && code.isNotEmpty && !code.startsWith('shikimori_'))
          ? code
          : 'Аниме #${id ?? 0}',
      englishTitle: '',
      posterSmall: poster,
      posterMedium: poster,
      posterOriginal: poster,
      fallbackPosterUrl: poster,
      genres: const [],
      description: '',
      status: 'В эфире',
    );
  }
}
