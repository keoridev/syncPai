import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../domain/entities/manga_bridge.dart';

/// Русскоязычный источник манги и манхвы на базе публичного API MangaLib (`https://api.cdnlibs.org/api`).
class MangaLibDataSource {
  final Dio _dio;
  String _imageServerUrl = 'https://img2.imglib.info';
  bool _imageServerResolved = false;

  static const String _baseUrl = 'https://api.cdnlibs.org/api';

  MangaLibDataSource({Dio? customDio})
      : _dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 9),
                headers: const {
                  'Site-Id': '1',
                  'Referer': 'https://mangalib.me/',
                  'Origin': 'https://mangalib.me',
                  'Accept': 'application/json',
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
                },
              ),
            );

  Future<void> _ensureImageServer() async {
    if (_imageServerResolved) return;
    _imageServerResolved = true;
    try {
      final res = await _dio.get<dynamic>(
        '/constants',
        queryParameters: {'fields[]': 'imageServers'},
      );
      final body = res.data;
      final data = body is Map ? body['data'] : null;
      final servers = data is Map ? data['imageServers'] : null;
      if (servers is List) {
        for (final s in servers) {
          if (s is! Map) continue;
          final siteIds = s['site_ids'];
          final url = (s['url'] ?? '').toString().trim();
          if (url.isNotEmpty &&
              siteIds is List &&
              siteIds.contains(1) &&
              s['id'] == 'main') {
            _imageServerUrl = url.replaceAll(RegExp(r'/+$'), '');
            break;
          }
        }
      }
    } catch (_) {}
  }

  Future<List<MangaDexManga>> searchManga(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final res = await _dio.get<dynamic>(
        '/manga',
        queryParameters: {
          'q': trimmed,
          'site_id[]': 1,
        },
      );
      final body = res.data;
      final list = body is Map ? body['data'] : null;
      if (list is! List) return const [];

      final out = <MangaDexManga>[];
      for (final item in list) {
        if (item is! Map) continue;
        final slugUrl = (item['slug_url'] ?? item['slug'] ?? '').toString().trim();
        if (slugUrl.isEmpty) continue;
        final rus = (item['rus_name'] ?? '').toString().trim();
        final eng = (item['eng_name'] ?? item['name'] ?? '').toString().trim();
        final title = rus.isNotEmpty ? rus : eng;
        if (title.isEmpty) continue;

        final cover = item['cover'];
        final coverUrl = cover is Map
            ? (cover['default'] ?? cover['md'] ?? cover['thumbnail'] ?? '')
                .toString()
                .trim()
            : '';
        final typeLabel = item['type'] is Map
            ? (item['type']['label'] ?? '').toString().toLowerCase()
            : '';
        final origLang = typeLabel.contains('манхва')
            ? 'ko'
            : (typeLabel.contains('маньхуа') ? 'zh' : 'ja');
        final ratingRaw = item['rating'] is Map ? item['rating']['average'] : null;
        final rating = double.tryParse((ratingRaw ?? '').toString());

        out.add(
          MangaDexManga(
            id: 'mangalib:$slugUrl',
            title: title,
            originalTitle: eng.isNotEmpty ? eng : null,
            coverUrl: coverUrl,
            originalLanguage: origLang,
            availableTranslatedLanguages: const ['ru'],
            rating: rating,
            source: 'MangaLib',
          ),
        );
      }
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MangaLib] searchManga("$trimmed") error: $e');
      }
      return const [];
    }
  }

  Future<List<MangaDexChapter>> getChapters(String slugOrId) async {
    final slugUrl = slugOrId.replaceFirst('mangalib:', '').trim();
    if (slugUrl.isEmpty) return const [];
    try {
      final res = await _dio.get<dynamic>('/manga/$slugUrl/chapters');
      final body = res.data;
      final list = body is Map ? body['data'] : null;
      if (list is! List) return const [];

      final out = <MangaDexChapter>[];
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is! Map) continue;
        final vol = (item['volume'] ?? '1').toString().trim();
        final numStr = (item['number'] ?? '').toString().trim();
        if (numStr.isEmpty) continue;
        final chNum = double.tryParse(numStr);
        final name = (item['name'] ?? '').toString().trim();

        String? teamName;
        final branches = item['branches'];
        if (branches is List && branches.isNotEmpty && branches.first is Map) {
          final teams = branches.first['teams'];
          if (teams is List && teams.isNotEmpty && teams.first is Map) {
            teamName = (teams.first['name'] ?? '').toString().trim();
          }
        }

        out.add(
          MangaDexChapter(
            id: 'mangalib:$slugUrl|$vol|$numStr',
            volume: vol.isNotEmpty && vol != '0' ? vol : null,
            chapterNumber: chNum,
            chapterLabel: numStr,
            title: name,
            translatedLanguage: 'ru',
            pagesCount: 0,
            translatorGroup:
                (teamName != null && teamName.isNotEmpty) ? teamName : 'MangaLib',
            source: 'MangaLib',
          ),
        );
      }

      out.sort((a, b) {
        final na = a.chapterNumber ?? 999999.0;
        final nb = b.chapterNumber ?? 999999.0;
        return na.compareTo(nb);
      });
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MangaLib] getChapters("$slugUrl") error: $e');
      }
      return const [];
    }
  }

  Future<List<String>> getChapterPages(String compositeId) async {
    final clean = compositeId.replaceFirst('mangalib:', '').trim();
    final parts = clean.split('|');
    if (parts.length < 3) return const [];
    final slugUrl = parts[0];
    final volume = parts[1];
    final number = parts[2];

    try {
      await _ensureImageServer();
      final res = await _dio.get<dynamic>(
        '/manga/$slugUrl/chapter',
        queryParameters: {
          'number': number,
          'volume': volume,
        },
      );
      final body = res.data;
      final data = body is Map ? body['data'] : null;
      final pages = data is Map ? data['pages'] : null;
      if (pages is! List) return const [];

      final urls = <String>[];
      for (final p in pages) {
        if (p is! Map) continue;
        final rawUrl = (p['url'] ?? '').toString().trim();
        if (rawUrl.isEmpty) continue;
        if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
          urls.add(rawUrl);
        } else {
          final path = rawUrl.replaceFirst(RegExp(r'^/+'), '');
          urls.add('$_imageServerUrl/$path');
        }
      }
      return urls;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MangaLib] getChapterPages("$clean") error: $e');
      }
      return const [];
    }
  }
}

