import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../domain/entities/manga_bridge.dart';

/// Русскоязычный источник манги и манхвы на базе публичного GraphQL API Senkuro (`https://api.senkuro.com/graphql`).
class SenkuroDataSource {
  final Dio _dio;
  final Map<String, List<String>> _chapterPagesCache = {};

  static const String _endpoint = 'https://api.senkuro.com/graphql';

  SenkuroDataSource({Dio? customDio})
      : _dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: _endpoint,
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 10),
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                  'Origin': 'https://senkuro.com',
                  'Referer': 'https://senkuro.com/',
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
                },
              ),
            );

  Future<Map<String, dynamic>?> _postGraphql(String query) async {
    final res = await _dio.post<dynamic>('', data: {'query': query});
    final body = res.data;
    if (body is Map<String, dynamic>) {
      return body['data'] as Map<String, dynamic>?;
    }
    if (body is Map) {
      final d = body['data'];
      if (d is Map) return Map<String, dynamic>.from(d);
    }
    return null;
  }

  static String _escapeGql(String raw) =>
      raw.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', ' ');

  Future<List<MangaDexManga>> searchManga(String query, {int first = 8}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final gql =
          '{ search(query: "${_escapeGql(trimmed)}", type: MANGA, first: $first) { '
          'edges { node { ... on SearchManga { id slug titles { lang content } cover { original { url } } } } } } }';
      final data = await _postGraphql(gql);
      final search = data?['search'];
      final edges = search is Map ? search['edges'] : null;
      if (edges is! List) return const [];

      final out = <MangaDexManga>[];
      for (final edge in edges) {
        final node = edge is Map ? edge['node'] : null;
        if (node is! Map) continue;
        final slug = (node['slug'] ?? '').toString().trim();
        if (slug.isEmpty) continue;

        String ruTitle = '';
        String enTitle = '';
        final titles = node['titles'];
        if (titles is List) {
          for (final t in titles) {
            if (t is! Map) continue;
            final lang = (t['lang'] ?? '').toString().toUpperCase();
            final content = (t['content'] ?? '').toString().trim();
            if (content.isEmpty) continue;
            if (lang == 'RU' && ruTitle.isEmpty) ruTitle = content;
            if ((lang == 'EN' || lang == 'ROMAJI') && enTitle.isEmpty) {
              enTitle = content;
            }
          }
        }
        final title = ruTitle.isNotEmpty ? ruTitle : enTitle;
        if (title.isEmpty) continue;

        final cover = node['cover'];
        final orig = cover is Map ? cover['original'] : null;
        final coverUrl =
            orig is Map ? (orig['url'] ?? '').toString().trim() : '';

        out.add(
          MangaDexManga(
            id: 'senkuro:$slug',
            title: title,
            originalTitle: enTitle.isNotEmpty ? enTitle : null,
            coverUrl: coverUrl,
            availableTranslatedLanguages: const ['ru'],
            source: 'Senkuro',
          ),
        );
      }
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Senkuro] searchManga("$trimmed") error: $e');
      }
      return const [];
    }
  }

  Future<List<MangaDexChapter>> getChapters(String slugOrId) async {
    final slug = slugOrId.replaceFirst('senkuro:', '').trim();
    if (slug.isEmpty) return const [];
    try {
      final branchGql =
          '{ manga(slug: "${_escapeGql(slug)}") { id slug branches { id lang chapters } } }';
      final mangaData = await _postGraphql(branchGql);
      final mangaObj = mangaData?['manga'];
      final branches = mangaObj is Map ? mangaObj['branches'] : null;
      if (branches is! List || branches.isEmpty) return const [];

      String? bestBranchId;
      int bestCount = -1;
      for (final b in branches) {
        if (b is! Map) continue;
        final lang = (b['lang'] ?? '').toString().toUpperCase();
        if (lang.isNotEmpty && lang != 'RU') continue;
        final bId = (b['id'] ?? '').toString().trim();
        final count = (b['chapters'] as num?)?.toInt() ?? 0;
        if (bId.isNotEmpty && count > bestCount) {
          bestCount = count;
          bestBranchId = bId;
        }
      }
      if (bestBranchId == null) {
        for (final b in branches) {
          if (b is! Map) continue;
          final bId = (b['id'] ?? '').toString().trim();
          final count = (b['chapters'] as num?)?.toInt() ?? 0;
          if (bId.isNotEmpty && count > bestCount) {
            bestCount = count;
            bestBranchId = bId;
          }
        }
      }
      if (bestBranchId == null) return const [];

      final chapters = <MangaDexChapter>[];
      String? afterCursor;
      var pageLoops = 0;
      while (pageLoops < 5) {
        pageLoops++;
        final afterClause =
            afterCursor != null ? ', after: "${_escapeGql(afterCursor)}"' : '';
        final chGql =
            '{ mangaChapters(branchId: "${_escapeGql(bestBranchId)}", first: 200$afterClause) { '
            'edges { node { id slug number volume name pages { image { original { url } } } } } '
            'pageInfo { hasNextPage endCursor } } }';
        final chData = await _postGraphql(chGql);
        final conn = chData?['mangaChapters'];
        if (conn is! Map) break;
        final edges = conn['edges'];
        if (edges is! List || edges.isEmpty) break;

        for (final edge in edges) {
          final node = edge is Map ? edge['node'] : null;
          if (node is! Map) continue;
          final rawId = (node['id'] ?? '').toString().trim();
          if (rawId.isEmpty) continue;
          final numStr = (node['number'] ?? '').toString().trim();
          final volStr = (node['volume'] ?? '').toString().trim();
          final name = (node['name'] ?? '').toString().trim();
          final chapNum = double.tryParse(numStr);

          final pagesRaw = node['pages'];
          final pageUrls = <String>[];
          if (pagesRaw is List) {
            for (final p in pagesRaw) {
              if (p is! Map) continue;
              final img = p['image'];
              final orig = img is Map ? img['original'] : null;
              final url =
                  orig is Map ? (orig['url'] ?? '').toString().trim() : '';
              if (url.isNotEmpty) pageUrls.add(url);
            }
          }
          final compositeId = 'senkuro:$rawId';
          if (pageUrls.isNotEmpty) {
            _chapterPagesCache[compositeId] = pageUrls;
          }

          chapters.add(
            MangaDexChapter(
              id: compositeId,
              volume: volStr.isNotEmpty && volStr != '0' ? volStr : null,
              chapterNumber: chapNum,
              chapterLabel: numStr.isNotEmpty ? numStr : '${chapters.length + 1}',
              title: name,
              translatedLanguage: 'ru',
              pagesCount: pageUrls.length,
              translatorGroup: 'Senkuro',
              source: 'Senkuro',
            ),
          );
        }

        final pageInfo = conn['pageInfo'];
        final hasNext = pageInfo is Map && pageInfo['hasNextPage'] == true;
        final endCursor =
            pageInfo is Map ? (pageInfo['endCursor'] ?? '').toString().trim() : '';
        if (!hasNext || endCursor.isEmpty) break;
        afterCursor = endCursor;
      }

      chapters.sort((a, b) {
        final na = a.chapterNumber ?? 999999.0;
        final nb = b.chapterNumber ?? 999999.0;
        return na.compareTo(nb);
      });
      return chapters;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Senkuro] getChapters("$slug") error: $e');
      }
      return const [];
    }
  }

  Future<List<String>> getChapterPages(String compositeChapterId) async {
    final cached = _chapterPagesCache[compositeChapterId];
    if (cached != null && cached.isNotEmpty) return cached;
    return const [];
  }
}

