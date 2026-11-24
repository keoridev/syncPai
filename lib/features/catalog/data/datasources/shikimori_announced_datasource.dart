import 'package:dio/dio.dart';
import '../../domain/entities/anime_title.dart';

/// Вычисляет код следующего сезона для Shikimori GraphQL (например, `spring_2027`).
String computeNextShikimoriSeason([DateTime? now]) {
  final dt = now ?? DateTime.now();
  final m = dt.month;
  final y = dt.year;
  // winter (1-3) -> spring_Y; spring (4-6) -> summer_Y; summer (7-9) -> autumn_Y; autumn (10-12) -> winter_{Y+1}
  if (m <= 3) return 'spring_$y';
  if (m <= 6) return 'summer_$y';
  if (m <= 9) return 'autumn_$y';
  return 'winter_${y + 1}';
}

/// Источник реальных анонсов через Shikimori GraphQL (`https://shikimori.io/api/graphql`).
/// Строго использует домен `shikimori.io` (без `shikimori.one` / `.me`, которые отдают 308).
abstract class ShikimoriAnnouncedDataSource {
  Future<List<AnimeTitle>> fetchAnnounced({
    required String season,
    int limit = 40,
    CancelToken? cancelToken,
  });
}

class ShikimoriAnnouncedDataSourceImpl implements ShikimoriAnnouncedDataSource {
  final Dio _dio;

  static const String graphqlUrl = 'https://shikimori.io/api/graphql';

  static const String _query = r'''
query ($season: String, $limit: Int) {
  animes(status: "anons,planned", season: $season, limit: $limit, order: popularity) {
    id
    name
    russian
    kind
    status
    season
    poster {
      originalUrl
      mainUrl
    }
  }
}
''';

  const ShikimoriAnnouncedDataSourceImpl(this._dio);

  @override
  Future<List<AnimeTitle>> fetchAnnounced({
    required String season,
    int limit = 40,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio
        .post(
          graphqlUrl,
          data: {
            'query': _query,
            'variables': {
              'season': season,
              'limit': limit,
            },
          },
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
          cancelToken: cancelToken,
        )
        .timeout(const Duration(seconds: 10));

    final body = response.data;
    if (body is! Map) return const [];
    final data = body['data'];
    if (data is! Map || data['animes'] is! List) return const [];

    final rawList = data['animes'] as List;
    final results = <AnimeTitle>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
      if (id <= 0) continue;

      final en = (item['name'] ?? '').toString().trim();
      final ru = (item['russian'] ?? '').toString().trim();
      final kind = (item['kind'] ?? '').toString().trim().toUpperCase();
      final seasonStr = (item['season'] ?? season).toString().trim();
      final posterMap = item['poster'] is Map ? item['poster'] as Map : null;
      final orig = (posterMap?['originalUrl'] ?? '').toString().trim();
      final main = (posterMap?['mainUrl'] ?? orig).toString().trim();

      String normalizeUrl(String url) {
        if (url.isEmpty) return '';
        if (url.startsWith('//')) return 'https:$url';
        if (!url.startsWith('http')) return 'https://shikimori.io$url';
        return url;
      }

      final posterOrig = normalizeUrl(orig);
      final posterMain = normalizeUrl(main);

      results.add(
        AnimeTitle(
          id: id,
          shikimoriId: id,
          code: 'shiki_$id',
          russianTitle: ru.isNotEmpty ? ru : en,
          englishTitle: en,
          posterSmall: posterMain,
          posterMedium: posterMain,
          posterOriginal: posterOrig.isNotEmpty ? posterOrig : posterMain,
          kind: kind.isEmpty ? null : kind,
          season: seasonStr,
          genres: const [],
          description: '',
          status: 'Анонс',
          episodesTotal: 0,
          episodes: const [],
          shikimoriUrl: 'https://shikimori.io/animes/$id',
        ),
      );
    }

    return results;
  }
}

