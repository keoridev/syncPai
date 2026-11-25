import 'package:dio/dio.dart';

import '../../domain/entities/manga_bridge.dart';

/// Вторичный русскоязычный источник манги и манхвы (Remanga public API)
/// для fallback при DMCA-удалениях или отсутствии русских глав на MangaDex.
class RemangaDataSource {
  final Dio _dio;

  static const String _baseUrl = 'https://api.remanga.org/api';

  RemangaDataSource({Dio? customDio})
      : _dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 7),
                headers: const {
                  'Accept': 'application/json',
                  'Referer': 'https://remanga.org',
                },
              ),
            );

  Future<List<MangaDexChapter>> getChaptersByTitle({
    String? title,
    String? originalTitle,
  }) async {
    final queries = <String>[
      if (title != null && title.trim().isNotEmpty) title.trim(),
      if (originalTitle != null &&
          originalTitle.trim().isNotEmpty &&
          originalTitle.trim() != title?.trim())
        originalTitle.trim(),
    ];
    if (queries.isEmpty) return const [];

    for (final q in queries) {
      try {
        final searchRes = await _dio.get(
          '/search/',
          queryParameters: {'query': q, 'count': 10},
        );
        final searchBody = searchRes.data;
        final content = searchBody is Map ? searchBody['content'] : null;
        if (content is! List || content.isEmpty) continue;

        final first = content.first;
        if (first is! Map) continue;
        final dir = (first['dir'] ?? '').toString().trim();
        if (dir.isEmpty) continue;

        final titleRes = await _dio.get('/titles/$dir/');
        final titleBody = titleRes.data;
        final titleContent = titleBody is Map ? titleBody['content'] : null;
        if (titleContent is! Map) continue;

        final branches = titleContent['branches'];
        if (branches is! List || branches.isEmpty) continue;

        int? bestBranchId;
        int bestCount = -1;
        for (final b in branches) {
          if (b is! Map) continue;
          final bId = (b['id'] as num?)?.toInt();
          final count = (b['count_chapters'] as num?)?.toInt() ?? 0;
          if (bId != null && count > bestCount) {
            bestCount = count;
            bestBranchId = bId;
          }
        }
        if (bestBranchId == null) continue;

        final chapRes = await _dio.get(
          '/titles/chapters/',
          queryParameters: {
            'branch_id': bestBranchId,
            'ordering': 'index',
            'count': 500,
          },
        );
        final chapBody = chapRes.data;
        final chapContent = chapBody is Map ? chapBody['content'] : null;
        if (chapContent is! List || chapContent.isEmpty) continue;

        final chapters = <MangaDexChapter>[];
        for (var i = 0; i < chapContent.length; i++) {
          final item = chapContent[i];
          if (item is! Map) continue;
          final id = (item['id'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          final isPaid = item['is_paid'] == true;
          if (isPaid) continue;

          final tome = (item['tome'] ?? '').toString().trim();
          final chapStr = (item['chapter'] ?? '').toString().trim();
          final chapNum = double.tryParse(chapStr);
          final name = (item['name'] ?? '').toString().trim();
          final publishers = item['publishers'];
          String? groupName;
          if (publishers is List && publishers.isNotEmpty && publishers.first is Map) {
            groupName = (publishers.first['name'] ?? '').toString().trim();
          }

          chapters.add(
            MangaDexChapter(
              id: 'remanga:$id',
              volume: tome.isNotEmpty && tome != '0' ? tome : null,
              chapterNumber: chapNum,
              chapterLabel: chapStr.isNotEmpty ? chapStr : '${i + 1}',
              title: name,
              translatedLanguage: 'ru',
              pagesCount: (item['count_pages'] as num?)?.toInt() ?? 0,
              translatorGroup:
                  (groupName != null && groupName.isNotEmpty) ? groupName : 'Remanga',
              source: 'Remanga',
            ),
          );
        }

        if (chapters.isNotEmpty) {
          chapters.sort((a, b) {
            final na = a.chapterNumber ?? 999999.0;
            final nb = b.chapterNumber ?? 999999.0;
            return na.compareTo(nb);
          });
          return chapters;
        }
      } catch (_) {}
    }
    return const [];
  }

  Future<List<String>> getChapterPages(String rawChapterId) async {
    final cleanId = rawChapterId.replaceFirst('remanga:', '').trim();
    if (cleanId.isEmpty) return const [];
    try {
      final res = await _dio.get('/titles/chapters/$cleanId/');
      final body = res.data;
      final content = body is Map ? body['content'] : null;
      if (content is! Map) return const [];
      final pagesRaw = content['pages'];
      if (pagesRaw is! List) return const [];

      final urls = <String>[];
      void collect(dynamic node) {
        if (node is List) {
          for (final item in node) {
            collect(item);
          }
        } else if (node is Map) {
          final link = (node['link'] ?? '').toString().trim();
          if (link.isNotEmpty) {
            if (link.startsWith('http://') || link.startsWith('https://')) {
              urls.add(link);
            } else if (link.startsWith('/')) {
              urls.add('https://remanga.org$link');
            } else {
              urls.add('https://remanga.org/$link');
            }
          }
        }
      }

      collect(pagesRaw);
      return urls;
    } catch (_) {
      return const [];
    }
  }
}

