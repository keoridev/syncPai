import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../domain/entities/manga_bridge.dart';

/// Первичный русскоязычный источник манхвы и популярной манги (ReManga public API).
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
                  'Referer': 'https://remanga.org/',
                  'Origin': 'https://remanga.org',
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
                },
              ),
            );

  String _normalizeCover(dynamic imgField) {
    String raw = '';
    if (imgField is Map) {
      raw = (imgField['high'] ?? imgField['mid'] ?? imgField['low'] ?? '')
          .toString()
          .trim();
    } else if (imgField != null) {
      raw = imgField.toString().trim();
    }
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) return 'https://api.remanga.org$raw';
    return 'https://api.remanga.org/$raw';
  }

  String _mapTypeIdToOrigLang(dynamic typeField) {
    int? typeId;
    if (typeField is Map) {
      typeId = (typeField['id'] as num?)?.toInt();
    } else if (typeField is num) {
      typeId = typeField.toInt();
    }
    // ReManga: 1 = Манхва, 2 = Маньхуа, 0 = Манга
    if (typeId == 1) return 'ko';
    if (typeId == 2) return 'zh';
    return 'ja';
  }

  MangaDexManga? _parseCatalogItem(Map item) {
    final dir = (item['dir'] ?? '').toString().trim();
    if (dir.isEmpty) return null;
    final rus = (item['rus_name'] ?? '').toString().trim();
    final en = (item['en_name'] ?? item['main_name'] ?? '').toString().trim();
    final title = rus.isNotEmpty ? rus : en;
    if (title.isEmpty) return null;

    final rating = double.tryParse((item['avg_rating'] ?? '').toString());
    final countChapters = (item['count_chapters'] as num?)?.toInt();

    return MangaDexManga(
      id: 'remanga:$dir',
      title: title,
      originalTitle: en.isNotEmpty ? en : null,
      coverUrl: _normalizeCover(item['img']),
      originalLanguage: _mapTypeIdToOrigLang(item['type']),
      availableTranslatedLanguages: const ['ru'],
      rating: rating,
      chaptersCount: countChapters,
      source: 'Remanga',
    );
  }

  Future<List<MangaDexManga>> browseCatalog({
    int page = 1,
    int count = 30,
    String ordering = '-rating',
    int? type,
  }) async {
    try {
      final params = <String, dynamic>{
        'page': page,
        'count': count,
        'ordering': ordering,
      };
      if (type != null) {
        params['types'] = type;
      }
      final res = await _dio.get('/search/catalog/', queryParameters: params);
      final body = res.data;
      final content = body is Map ? body['content'] : null;
      if (content is! List) return const [];

      final out = <MangaDexManga>[];
      for (final item in content) {
        if (item is! Map) continue;
        final parsed = _parseCatalogItem(item);
        if (parsed != null) out.add(parsed);
      }
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReManga] browseCatalog error: $e');
      }
      return const [];
    }
  }

  Future<List<MangaDexManga>> searchCatalog(
    String query, {
    int count = 25,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final res = await _dio.get(
        '/search/',
        queryParameters: {'query': q, 'count': count},
      );
      final body = res.data;
      final content = body is Map ? body['content'] : null;
      if (content is! List) return const [];

      final out = <MangaDexManga>[];
      for (final item in content) {
        if (item is! Map) continue;
        final parsed = _parseCatalogItem(item);
        if (parsed != null) out.add(parsed);
      }
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReManga] browseCatalog error: $e');
      }
      return const [];
    }
  }

  Future<MangaDexManga?> getTitleDetails(String idOrDir) async {
    final dir = idOrDir.replaceFirst('remanga:', '').trim();
    if (dir.isEmpty) return null;
    try {
      final res = await _dio.get('/titles/$dir/');
      final body = res.data;
      final content = body is Map ? body['content'] : null;
      if (content is! Map) return null;
      final base = _parseCatalogItem(content);
      if (base == null) return null;
      final desc = (content['description'] ?? '').toString().trim();
      final statusName = content['status'] is Map
          ? (content['status']['name'] ?? '').toString().toLowerCase()
          : '';
      return MangaDexManga(
        id: base.id,
        title: base.title,
        originalTitle: base.originalTitle,
        coverUrl: base.coverUrl,
        originalLanguage: base.originalLanguage,
        availableTranslatedLanguages: const ['ru'],
        description: desc.isNotEmpty ? desc : null,
        status: statusName.contains('законч') || statusName.contains('заверш')
            ? 'completed'
            : (statusName.isNotEmpty ? 'ongoing' : null),
        rating: base.rating,
        chaptersCount: base.chaptersCount,
        source: 'Remanga',
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<MangaDexChapter>> getChaptersByDir(String idOrDir) async {
    final dir = idOrDir.replaceFirst('remanga:', '').trim();
    if (dir.isEmpty) return const [];
    try {
      final titleRes = await _dio.get('/titles/$dir/');
      final titleBody = titleRes.data;
      final titleContent = titleBody is Map ? titleBody['content'] : null;
      if (titleContent is! Map) return const [];

      final branches = titleContent['branches'];
      if (branches is! List || branches.isEmpty) return const [];

      final branchIds = <int>[];
      for (final b in branches) {
        if (b is! Map) continue;
        final bId = (b['id'] as num?)?.toInt();
        if (bId != null) branchIds.add(bId);
      }
      if (branchIds.isEmpty) return const [];

      Future<List<MangaDexChapter>> fetchBranch(int branchId) async {
        try {
          final chapRes = await _dio.get(
            '/v2/titles/chapters/',
            queryParameters: {
              'branch_id': branchId,
              'ordering': 'index',
              'count': 500,
            },
          );
          final chapBody = chapRes.data;
          final chapContent = chapBody is Map ? chapBody['content'] : null;
          if (chapContent is! List || chapContent.isEmpty) return const [];

          final list = <MangaDexChapter>[];
          for (var i = 0; i < chapContent.length; i++) {
            final item = chapContent[i];
            if (item is! Map) continue;
            final id = (item['id'] ?? '').toString().trim();
            if (id.isEmpty) continue;
            final isPaid = item['is_paid'] == true;

            final tome = (item['tome'] ?? '').toString().trim();
            final chapStr = (item['chapter'] ?? '').toString().trim();
            final chapNum = double.tryParse(chapStr);
            final name = (item['name'] ?? '').toString().trim();
            final publishers = item['publishers'];
            String? groupName;
            if (publishers is List &&
                publishers.isNotEmpty &&
                publishers.first is Map) {
              groupName = (publishers.first['name'] ?? '').toString().trim();
            }

            list.add(
              MangaDexChapter(
                id: 'remanga:$id',
                volume: tome.isNotEmpty && tome != '0' ? tome : null,
                chapterNumber: chapNum,
                chapterLabel: chapStr.isNotEmpty ? chapStr : '${i + 1}',
                title: name,
                translatedLanguage: 'ru',
                pagesCount: (item['count_pages'] as num?)?.toInt() ?? 0,
                translatorGroup: (groupName != null && groupName.isNotEmpty)
                    ? groupName
                    : 'Remanga',
                source: 'Remanga',
                isPaid: isPaid,
              ),
            );
          }

          list.sort((a, b) {
            final na = a.chapterNumber ?? 999999.0;
            final nb = b.chapterNumber ?? 999999.0;
            return na.compareTo(nb);
          });
          return list;
        } catch (_) {
          return const [];
        }
      }

      final branchResults = await Future.wait(branchIds.map(fetchBranch));

      List<MangaDexChapter> bestChapters = const [];
      int bestFreeCount = 0;
      for (final branchList in branchResults) {
        if (branchList.isEmpty) continue;
        final freeCount = branchList.where((c) => !c.isPaid).length;
        if (freeCount > bestFreeCount) {
          bestFreeCount = freeCount;
          bestChapters = branchList;
        }
      }

      if (bestFreeCount == 0) {
        // Все ветки на ReManga платные/заблокированы — пусть сработает fallback на Desu.uno.
        return const [];
      }

      return bestChapters;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReManga] getChaptersByDir($dir) error: $e');
      }
      return const [];
    }
  }

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
      final matches = await searchCatalog(q, count: 10);
      for (final match in matches.take(3)) {
        final chapters = await getChaptersByDir(match.id);
        if (chapters.isNotEmpty) return chapters;
      }
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
