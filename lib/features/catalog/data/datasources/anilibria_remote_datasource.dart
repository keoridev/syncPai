import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../models/anime_title_dto.dart';

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
    // 1. Попытка запросить глобальный каталог релизов AniLibria (содержит тысячи тайтлов за все годы)
    try {
      final response = await client.get(
        ApiConstants.catalogReleases,
        queryParameters: {
          'limit': limit,
          'page': page,
        },
      );

      final list = _parseList(response.data);
      if (list.isNotEmpty) {
        return list
            .whereType<Map<String, dynamic>>()
            .map((item) => AnimeTitleDto.fromJson(item))
            .toList();
      }
    } catch (_) {
      // Фолбек на ленту последних релизов
    }

    // 2. Фолбек на ленту свежих релизов
    try {
      final response = await client.get(
        ApiConstants.latestReleases,
        queryParameters: {
          'limit': limit,
          'page': page,
        },
      );

      final list = _parseList(response.data);
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => AnimeTitleDto.fromJson(item))
          .toList();
    } catch (e) {
      if (e is ServerException || e is NetworkException) rethrow;
      throw ParsingException('Не удалось разобрать список релизов: $e');
    }
  }

  List<dynamic> _parseList(dynamic data) {
    if (data is List) {
      return data;
    } else if (data is Map<String, dynamic>) {
      if (data['data'] is List) return data['data'] as List;
      if (data['list'] is List) return data['list'] as List;
      if (data['items'] is List) return data['items'] as List;
    }
    return [];
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
    } catch (e) {
      if (e is ServerException || e is NetworkException) rethrow;
      throw ParsingException('Не удалось выполнить поиск: $e');
    }
  }

  @override
  Future<AnimeTitleDto> getTitleDetails({int? id, String? code}) async {
    try {
      final hasValidCode = code != null && code.trim().isNotEmpty && !code.startsWith('saved_');
      final target = id != null ? '$id' : (code ?? '');
      final path = '${ApiConstants.releaseDetails}/$target';

      dynamic response;
      try {
        response = await client.get(path);
      } catch (err) {
        // Если по ID вернулась 404 ошибка (например, ID из Anixart/Shikimori не совпадает с AniLibria),
        // пробуем запросить по коду/slug тайтла (если он есть)
        if (hasValidCode && target != code) {
          try {
            response = await client.get('${ApiConstants.releaseDetails}/$code');
          } catch (_) {
            // Если прямой запрос по слагу тоже вернул 404, пробуем найти через поисковый эндпоинт
            try {
              final searchResults = await searchTitles(code);
              if (searchResults.isNotEmpty) {
                return searchResults.first;
              }
            } catch (_) {}
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      if (response.data is Map<String, dynamic>) {
        final map = response.data as Map<String, dynamic>;
        final releaseData = map.containsKey('data') && map['data'] is Map<String, dynamic>
            ? map['data'] as Map<String, dynamic>
            : map;
        return AnimeTitleDto.fromJson(releaseData);
      }
      throw const ParsingException('Некорректный формат ответа тайтла');
    } catch (e) {
      if (e is ServerException || e is NetworkException) rethrow;
      throw ParsingException('Не удалось загрузить данные тайтла: $e');
    }
  }
}
