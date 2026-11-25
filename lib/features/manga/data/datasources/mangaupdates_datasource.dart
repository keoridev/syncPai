import 'package:dio/dio.dart';

/// Источник данных MangaUpdates API v1 для определения точной главы,
/// на которой закончилась аниме-экранизация (`anime.end`).
class MangaUpdatesDataSource {
  final Dio _dio;

  static const String _baseUrl = 'https://api.mangaupdates.com/v1';

  static final RegExp _chapRegex = RegExp(
    r'Chap\s*(\d+)',
    caseSensitive: false,
  );

  MangaUpdatesDataSource({Dio? customDio})
      : _dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 6),
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );

  /// Парсит строку `anime.end` (например, `"Chap 34"` или `"Vol 4, Chap 34"`).
  static int? parseEndChapter(String? rawEnd) {
    if (rawEnd == null || rawEnd.trim().isEmpty) return null;
    final match = _chapRegex.firstMatch(rawEnd);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  /// Ищет серию по английскому названию и возвращает номер последней экранизированной главы.
  Future<int?> getAnimeEndChapter(String englishTitle) async {
    final query = englishTitle.trim();
    if (query.isEmpty) return null;

    try {
      final searchRes = await _dio.post(
        '/series/search',
        data: {
          'search': query,
          'perpage': 5,
        },
      );

      final searchData = searchRes.data;
      if (searchData is! Map) return null;
      final results = searchData['results'];
      if (results is! List || results.isEmpty) return null;

      int? seriesId;
      final queryLower = query.toLowerCase();
      for (final item in results) {
        if (item is! Map) continue;
        final record = item['record'];
        if (record is! Map) continue;
        final id = (record['series_id'] as num?)?.toInt();
        final title = (record['title'] ?? '').toString().toLowerCase().trim();
        if (id != null && title == queryLower) {
          seriesId = id;
          break;
        }
        seriesId ??= id;
      }
      if (seriesId == null || seriesId <= 0) return null;

      final detailRes = await _dio.get('/series/$seriesId');
      final detailData = detailRes.data;
      if (detailData is! Map) return null;
      final animeObj = detailData['anime'];
      if (animeObj is! Map) return null;

      final rawEnd = animeObj['end']?.toString();
      return parseEndChapter(rawEnd);
    } catch (_) {
      return null;
    }
  }
}

