import 'package:dio/dio.dart';

/// Загружает справочники допустимых значений фильтров AniLibria v1.
/// Пути используют дефис (`publish-statuses`, `production-statuses`, `age-ratings`).
abstract class CatalogReferencesDataSource {
  Future<Set<String>> fetchReferenceValues(String endpointSlug);
}

class CatalogReferencesDataSourceImpl implements CatalogReferencesDataSource {
  final Dio _dio;

  static const String _baseUrl =
      'https://anilibria.top/api/v1/anime/catalog/references';

  static const List<String> allReferenceSlugs = [
    'publish-statuses',
    'production-statuses',
    'types',
    'seasons',
    'age-ratings',
    'sorting',
  ];

  const CatalogReferencesDataSourceImpl(this._dio);

  @override
  Future<Set<String>> fetchReferenceValues(String endpointSlug) async {
    final response = await _dio
        .get('$_baseUrl/$endpointSlug')
        .timeout(const Duration(seconds: 8));
    final data = response.data;
    final List<dynamic> rawList;
    if (data is List) {
      rawList = data;
    } else if (data is Map && data['data'] is List) {
      rawList = data['data'] as List;
    } else {
      return const {};
    }

    final result = <String>{};
    for (final item in rawList) {
      if (item is String && item.trim().isNotEmpty) {
        result.add(item.trim());
      } else if (item is Map) {
        final val = (item['value'] ?? item['code'] ?? item['name'] ?? '')
            .toString()
            .trim();
        if (val.isNotEmpty) {
          result.add(val);
        }
      }
    }
    return result;
  }
}

