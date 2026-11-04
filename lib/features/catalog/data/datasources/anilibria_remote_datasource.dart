import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../models/anime_title_dto.dart';

abstract class AnilibriaRemoteDataSource {
  Future<List<AnimeTitleDto>> getUpdates({int page = 1, int limit = 20});
  Future<List<AnimeTitleDto>> searchTitles(String query, {int limit = 20});
  Future<AnimeTitleDto> getTitleDetails({int? id, String? code});
}

class AnilibriaRemoteDataSourceImpl implements AnilibriaRemoteDataSource {
  final DioClient client;

  AnilibriaRemoteDataSourceImpl(this.client);

  @override
  Future<List<AnimeTitleDto>> getUpdates({int page = 1, int limit = 20}) async {
    try {
      final response = await client.get(
        ApiConstants.updates,
        queryParameters: {
          'playlist_type': 'array',
          'page': page,
          'items_per_page': limit,
        },
      );

      final data = response.data;
      final List<dynamic> list;

      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic> && data['list'] is List) {
        list = data['list'] as List;
      } else {
        list = [];
      }

      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => AnimeTitleDto.fromJson(item))
          .toList();
    } catch (e) {
      if (e is ServerException || e is NetworkException) rethrow;
      throw ParsingException('Не удалось разобрать список релизов: $e');
    }
  }

  @override
  Future<List<AnimeTitleDto>> searchTitles(String query, {int limit = 20}) async {
    try {
      final response = await client.get(
        ApiConstants.search,
        queryParameters: {
          'search': query,
          'playlist_type': 'array',
          'items_per_page': limit,
        },
      );

      final data = response.data;
      final List<dynamic> list;

      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic> && data['list'] is List) {
        list = data['list'] as List;
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
      final queryParams = <String, dynamic>{
        'playlist_type': 'array',
      };
      if (id != null) queryParams['id'] = id;
      if (code != null) queryParams['code'] = code;

      final response = await client.get(
        ApiConstants.title,
        queryParameters: queryParams,
      );

      if (response.data is Map<String, dynamic>) {
        return AnimeTitleDto.fromJson(response.data as Map<String, dynamic>);
      }
      throw const ParsingException('Некорректный формат ответа тайтла');
    } catch (e) {
      if (e is ServerException || e is NetworkException) rethrow;
      throw ParsingException('Не удалось загрузить данные тайтла: $e');
    }
  }
}

