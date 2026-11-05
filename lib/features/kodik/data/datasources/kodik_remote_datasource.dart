import 'package:dio/dio.dart';
import '../../domain/entities/kodik_translation.dart';

abstract class KodikRemoteDataSource {
  Future<List<KodikTranslation>> getTranslationsForAnime({
    int? shikimoriId,
    String? title,
  });
}

class KodikRemoteDataSourceImpl implements KodikRemoteDataSource {
  final Dio _dio;
  final String _token;

  static const String defaultToken = '41639d67da34440c94a97ee73b7543a5';
  static const String backupToken = '0994545e1a18db10b9f7053096704124';
  static const String baseUrl = 'https://kodikapi.com';

  KodikRemoteDataSourceImpl({
    Dio? dio,
    String? token,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                headers: {
                  'Accept': 'application/json',
                },
              ),
            ),
        _token = token ?? defaultToken;

  @override
  Future<List<KodikTranslation>> getTranslationsForAnime({
    int? shikimoriId,
    String? title,
  }) async {
    final results = <KodikTranslation>[];

    // 1. Попытка запроса по shikimori_id (наиболее точный и быстрый способ)
    if (shikimoriId != null && shikimoriId > 0) {
      try {
        final res = await _dio.get(
          '/search',
          queryParameters: {
            'token': _token,
            'shikimori_id': shikimoriId,
            'with_episodes': 'true',
          },
        );

        if (res.statusCode == 200 && res.data is Map) {
          final data = res.data as Map<String, dynamic>;
          final list = data['results'] as List?;
          if (list != null && list.isNotEmpty) {
            final seenStudios = <String>{};
            for (final item in list) {
              if (item is! Map<String, dynamic>) continue;
              final tr = KodikTranslation.fromJson(item);
              if (tr.title.isNotEmpty && !seenStudios.contains(tr.title.toLowerCase())) {
                seenStudios.add(tr.title.toLowerCase());
                results.add(tr);
              }
            }
          }
        }
      } catch (_) {}
    }

    // 2. Если по Shikimori ID ничего не найдено или ID не указан, ищем по названию тайтла
    if (results.isEmpty && title != null && title.trim().isNotEmpty) {
      try {
        final res = await _dio.get(
          '/search',
          queryParameters: {
            'token': _token,
            'title': title.trim(),
            'with_episodes': 'true',
            'limit': 15,
          },
        );

        if (res.statusCode == 200 && res.data is Map) {
          final data = res.data as Map<String, dynamic>;
          final list = data['results'] as List?;
          if (list != null && list.isNotEmpty) {
            final seenStudios = <String>{};
            for (final item in list) {
              if (item is! Map<String, dynamic>) continue;
              final tr = KodikTranslation.fromJson(item);
              if (tr.title.isNotEmpty && !seenStudios.contains(tr.title.toLowerCase())) {
                seenStudios.add(tr.title.toLowerCase());
                results.add(tr);
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Fallback: если сеть недоступна или тайтл новый, предоставляем список популярных студий Kodik
    if (results.isEmpty) {
      results.addAll(_generateFallbackTranslations());
    }

    return results;
  }

  /// Набор популярных студий озвучки из базы Kodik в случае отсутствия интернета
  List<KodikTranslation> _generateFallbackTranslations() {
    return const [
      KodikTranslation(
        id: 1002,
        title: 'Dream Cast',
        type: 'voice',
        episodesCount: 12,
      ),
      KodikTranslation(
        id: 609,
        title: 'StudioBand',
        type: 'voice',
        episodesCount: 12,
      ),
      KodikTranslation(
        id: 720,
        title: 'AniDUB',
        type: 'voice',
        episodesCount: 12,
      ),
      KodikTranslation(
        id: 840,
        title: 'SHIZA Project',
        type: 'voice',
        episodesCount: 12,
      ),
      KodikTranslation(
        id: 10,
        title: 'Субтитры (Shikimori)',
        type: 'subtitles',
        episodesCount: 12,
      ),
    ];
  }
}

