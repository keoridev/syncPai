import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../domain/entities/manga_bridge.dart';

/// Полноценный русскоязычный источник манги и манхвы (`https://desu.uno/manga/api`)
/// и зеркало для бесплатного чтения платных глав ReManga.
class DesuDataSource {
  final Dio _dio;

  static const String _baseUrl = 'https://desu.uno/manga/api';
  static bool _isEndpointGone = false;

  DesuDataSource({Dio? customDio})
      : _dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 8),
                headers: const {
                  'Accept': 'application/json',
                  'Referer': 'https://desu.uno/',
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
                },
              ),
            );

  String _mapKindToOrigLang(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('manhwa') || k.contains('web')) return 'ko';
    if (k.contains('manhua')) return 'zh';
    return 'ja';
  }

  Future<List<MangaDexManga>> browseCatalog({
    int page = 1,
    int limit = 30,
    String order = 'popular',
    String? kinds,
    String? search,
  }) async {
    if (_isEndpointGone) return const [];
    try {
      final params = <String, dynamic>{
        'limit': limit,
        'page': page,
        'order': order,
      };
      if (kinds != null && kinds.isNotEmpty) {
        params['kinds'] = kinds;
      }
      if (search != null && search.trim().isNotEmpty) {
        params['search'] = search.trim();
      }
      final res = await _dio.get('/', queryParameters: params);
      final body = res.data;
      final list = body is Map ? body['response'] : null;
      if (list is! List) return const [];

      final results = <MangaDexManga>[];
      for (final item in list) {
        if (item is! Map) continue;
        final rawId = (item['id'] ?? '').toString().trim();
        if (rawId.isEmpty) continue;

        final rus = (item['russian'] ?? '').toString().trim();
        final eng = (item['name'] ?? '').toString().trim();
        final title = rus.isNotEmpty ? rus : eng;
        if (title.isEmpty) continue;

        final imgMap = item['image'] is Map ? item['image'] as Map : null;
        final coverUrl =
            (imgMap?['original'] ?? imgMap?['preview'] ?? '').toString().trim();
        final kind = (item['kind'] ?? 'manga').toString();
        final score = (item['score'] as num?)?.toDouble();

        results.add(
          MangaDexManga(
            id: 'desu:$rawId',
            title: title,
            originalTitle: eng.isNotEmpty ? eng : null,
            coverUrl: coverUrl,
            originalLanguage: _mapKindToOrigLang(kind),
            availableTranslatedLanguages: const ['ru'],
            description: (item['description'] ?? '').toString().trim().isNotEmpty
                ? (item['description'] ?? '').toString().trim()
                : null,
            status: (item['status'] ?? '').toString().trim().isNotEmpty
                ? (item['status'] ?? '').toString().trim()
                : null,
            rating: score,
            source: 'Desu',
          ),
        );
      }
      return results;
    } on DioException catch (e) {
      if (e.response?.statusCode == 410) {
        _isEndpointGone = true;
        return const [];
      }
      if (kDebugMode) {
        debugPrint('[Desu] browseCatalog error ($search): $e');
      }
      return const [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Desu] browseCatalog error ($search): $e');
      }
      return const [];
    }
  }

  Future<List<MangaDexChapter>> getChapters(String mangaId) async {
    if (_isEndpointGone) return const [];
    final cleanId = mangaId.replaceFirst('desu:', '').trim();
    if (cleanId.isEmpty) return const [];
    try {
      final res = await _dio.get('/$cleanId');
      final body = res.data;
      final resp = body is Map ? body['response'] : null;
      if (resp is! Map) return const [];
      final chaptersObj = resp['chapters'];
      final list = chaptersObj is Map ? chaptersObj['list'] : null;
      if (list is! List) return const [];

      final out = <MangaDexChapter>[];
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is! Map) continue;
        final chapId = (item['id'] ?? '').toString().trim();
        if (chapId.isEmpty) continue;
        final vol = (item['vol'] ?? '').toString().trim();
        final chStr = (item['ch'] ?? '').toString().trim();
        final chNum = double.tryParse(chStr);
        final title = (item['title'] ?? '').toString().trim();

        out.add(
          MangaDexChapter(
            id: 'desu:$cleanId:$chapId',
            volume: vol.isNotEmpty && vol != '0' ? vol : null,
            chapterNumber: chNum,
            chapterLabel: chStr.isNotEmpty ? chStr : '${i + 1}',
            title: title,
            translatedLanguage: 'ru',
            pagesCount: 0,
            translatorGroup: 'Desu.uno',
            source: 'Desu',
          ),
        );
      }

      out.sort((a, b) {
        final na = a.chapterNumber ?? 999999.0;
        final nb = b.chapterNumber ?? 999999.0;
        return na.compareTo(nb);
      });
      return out;
    } on DioException catch (e) {
      if (e.response?.statusCode == 410) {
        _isEndpointGone = true;
        return const [];
      }
      if (kDebugMode) {
        debugPrint('[Desu] getChapters($cleanId) error: $e');
      }
      return const [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Desu] getChapters($cleanId) error: $e');
      }
      return const [];
    }
  }

  Future<List<String>> getChapterPages(String compositeChapterId) async {
    if (_isEndpointGone) return const [];
    final clean = compositeChapterId.replaceFirst('desu:', '').trim();
    final parts = clean.split(':');
    if (parts.length < 2) return const [];
    final mangaId = parts[0];
    final chapId = parts[1];
    try {
      final res = await _dio.get('/$mangaId/chapter/$chapId');
      final body = res.data;
      final resp = body is Map ? body['response'] : null;
      if (resp is! Map) return const [];
      final pagesObj = resp['pages'];
      final list = pagesObj is Map ? pagesObj['list'] : null;
      if (list is! List) return const [];

      final urls = <String>[];
      for (final p in list) {
        if (p is! Map) continue;
        final img = (p['img'] ?? '').toString().trim();
        if (img.isNotEmpty) {
          urls.add(img);
        }
      }
      return urls;
    } on DioException catch (e) {
      if (e.response?.statusCode == 410) {
        _isEndpointGone = true;
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }
}

