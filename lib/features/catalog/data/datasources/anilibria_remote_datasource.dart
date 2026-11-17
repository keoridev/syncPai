import 'dart:io';
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

  AnilibriaRemoteDataSourceImpl(this.client);

  @override
  Future<List<AnimeTitleDto>> getUpdates({int page = 1, int limit = 40}) async {
    // Клиентский слой больше не обращается к anilibria.top для списков аниме (каталог работает через Shikimori)
    return const [];
  }

  @override
  Future<List<AnimeTitleDto>> searchTitles(String query, {int limit = 30}) async {
    try {
      final response = await client.get(
        ApiConstants.searchReleases,
        queryParameters: {
          'query': query,
        },
      );

      final data = response.data;
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

  static final Map<int, int> _shikimoriToAnilibriaIdCache = {};

  @override
  Future<AnimeTitleDto> getTitleDetails({int? id, String? code}) async {
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

      final isShikimoriCode = rawCode.startsWith('shikimori_');
      final resolvedId = (id != null && _shikimoriToAnilibriaIdCache.containsKey(id))
          ? _shikimoriToAnilibriaIdCache[id]
          : id;

      // Если код вида shikimori_<id> ещё не сопоставлен с AniLibria ID — не делаем заведомый 404-запрос
      if (isShikimoriCode &&
          (id == null || !_shikimoriToAnilibriaIdCache.containsKey(id))) {
        return _buildFallbackShikimoriDto(id: id, code: rawCode);
      }

      final hasValidCode =
          rawCode.isNotEmpty && !rawCode.startsWith('saved_') && !isShikimoriCode;
      final target = resolvedId != null ? '$resolvedId' : rawCode;
      final path = '${ApiConstants.releaseDetails}/$target';

      dynamic response;
      try {
        response = await client.get(path);
      } catch (err) {
        if (hasValidCode && target != rawCode) {
          try {
            response = await client.get('${ApiConstants.releaseDetails}/$rawCode');
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
          return _buildFallbackShikimoriDto(id: id, code: rawCode);
        }
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
