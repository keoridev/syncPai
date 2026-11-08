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
