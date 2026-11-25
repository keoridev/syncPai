import 'package:dio/dio.dart';

import '../../domain/entities/manga_bridge.dart';
import 'remanga_datasource.dart';

/// Источник данных MangaDex API v5 для поиска манги, списка глав и страниц
/// с автоматическим fallback на Remanga при отсутствии русских глав.
class MangaDexDataSource {
  final Dio _dio;
  final RemangaDataSource _remanga;

  static const String _baseUrl = 'https://api.mangadex.org';

  MangaDexDataSource({
    Dio? customDio,
    RemangaDataSource? remangaDataSource,
  })  : _remanga = remangaDataSource ?? RemangaDataSource(),
        _dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 8),
                headers: const {
                  'Accept': 'application/json',
                },
              ),
            );

  /// Поиск манги/манхвы по названию с обложкой (`cover_art`).
  Future<List<MangaDexManga>> searchManga(
    String title, {
    int limit = 40,
    int offset = 0,
  }) async {
    final query = title.trim();
    if (query.isEmpty) return const [];

    try {
      final res = await _dio.get(
        '/manga',
        queryParameters: {
          'title': query,
          'limit': limit,
          'offset': offset,
          'includes[]': 'cover_art',
          'contentRating[]': ['safe', 'suggestive'],
          'order[relevance]': 'desc',
        },
      );

      final body = res.data;
      if (body is! Map || body['data'] is! List) return const [];
      return _parseMangaList(body['data'] as List);
    } catch (_) {
      return const [];
    }
  }

  /// Получает список глав (`ru` приоритетно, fallback на Remanga, затем `en`).
  Future<List<MangaDexChapter>> getChapters(
    String mangaId, {
    String? title,
    String? originalTitle,
  }) async {
    if (mangaId.trim().isEmpty) return const [];

    Future<List<MangaDexChapter>> fetchForLang(String langCode) async {
      final res = await _dio.get(
        '/manga/$mangaId/feed',
        queryParameters: {
          'translatedLanguage[]': [langCode],
          'includes[]': ['scanlation_group'],
          'order[chapter]': 'asc',
          'limit': 500,
        },
      );

      final body = res.data;
      if (body is! Map || body['data'] is! List) return const [];

      final byChapterKey = <String, MangaDexChapter>{};
      final rawItems = body['data'] as List;
      for (var i = 0; i < rawItems.length; i++) {
        final item = rawItems[i];
        if (item is! Map) continue;
        final id = (item['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;

        final attrs = item['attributes'] is Map
            ? item['attributes'] as Map
            : const <String, dynamic>{};
        final pages = (attrs['pages'] as num?)?.toInt() ?? 0;
        if (pages <= 0) continue;

        final rawVol = (attrs['volume'] ?? '').toString().trim();
        final rawChap = (attrs['chapter'] ?? '').toString().trim();
        final chapNum = double.tryParse(rawChap);
        final lang = (attrs['translatedLanguage'] ?? langCode).toString().trim();
        final chapTitle = (attrs['title'] ?? '').toString().trim();

        String? translatorGroup;
        final rels = item['relationships'];
        if (rels is List) {
          for (final rel in rels) {
            if (rel is Map && rel['type'] == 'scanlation_group') {
              final relAttrs = rel['attributes'];
              if (relAttrs is Map) {
                final groupName = (relAttrs['name'] ?? '').toString().trim();
                if (groupName.isNotEmpty) {
                  translatorGroup = groupName;
                  break;
                }
              }
            }
          }
        }

        // Никогда не показываем UUID в качестве названия главы
        final cleanLabel = rawChap.isNotEmpty
            ? rawChap
            : (chapTitle.isNotEmpty ? 'Спешл' : 'Глава ${i + 1}');

        final candidate = MangaDexChapter(
          id: id,
          volume: rawVol.isNotEmpty ? rawVol : null,
          chapterNumber: chapNum,
          chapterLabel: cleanLabel,
          title: chapTitle,
          translatedLanguage: lang,
          pagesCount: pages,
          translatorGroup: translatorGroup,
        );

        final key = rawChap.isNotEmpty ? rawChap : 'idx_$i';
        final existing = byChapterKey[key];
        if (existing == null ||
            (existing.translatedLanguage != 'ru' && lang == 'ru')) {
          byChapterKey[key] = candidate;
        }
      }

      final sorted = byChapterKey.values.toList()
        ..sort((a, b) {
          final na = a.chapterNumber ?? 999999.0;
          final nb = b.chapterNumber ?? 999999.0;
          return na.compareTo(nb);
        });
      return sorted;
    }

    try {
      final ruChapters = await fetchForLang('ru');
      if (ruChapters.isNotEmpty) return ruChapters;

      if ((title != null && title.trim().isNotEmpty) ||
          (originalTitle != null && originalTitle.trim().isNotEmpty)) {
        final remangaChapters = await _remanga.getChaptersByTitle(
          title: title,
          originalTitle: originalTitle,
        );
        if (remangaChapters.isNotEmpty) return remangaChapters;
      }

      return await fetchForLang('en');
    } catch (_) {
      return const [];
    }
  }

  /// Возвращает список URL страниц в высоком качестве через `/at-home/server/$chapterId`.
  Future<List<String>> getChapterPages(String chapterId) async {
    final bundle = await getChapterPagesWithFallback(chapterId);
    return bundle.dataUrls;
  }

  /// Возвращает URL страниц в полном качестве (`data`) и резервном качестве (`dataSaver`).
  Future<({List<String> dataUrls, List<String> dataSaverUrls})>
      getChapterPagesWithFallback(String chapterId) async {
    if (chapterId.trim().isEmpty) {
      return (dataUrls: const <String>[], dataSaverUrls: const <String>[]);
    }
    if (chapterId.startsWith('remanga:')) {
      final urls = await _remanga.getChapterPages(chapterId);
      return (dataUrls: urls, dataSaverUrls: const <String>[]);
    }

    try {
      final res = await _dio.get('/at-home/server/$chapterId');
      final body = res.data;
      if (body is! Map) {
        return (dataUrls: const <String>[], dataSaverUrls: const <String>[]);
      }

      final baseUrl = (body['baseUrl'] ?? '').toString().trim();
      final chapterMap = body['chapter'];
      if (baseUrl.isEmpty || chapterMap is! Map) {
        return (dataUrls: const <String>[], dataSaverUrls: const <String>[]);
      }

      final hash = (chapterMap['hash'] ?? '').toString().trim();
      if (hash.isEmpty) {
        return (dataUrls: const <String>[], dataSaverUrls: const <String>[]);
      }

      final dataList = chapterMap['data'] is List ? chapterMap['data'] as List : const [];
      final saverList =
          chapterMap['dataSaver'] is List ? chapterMap['dataSaver'] as List : const [];

      final dataUrls = dataList
          .map((file) => '$baseUrl/data/$hash/$file')
          .toList(growable: false);
      final dataSaverUrls = saverList
          .map((file) => '$baseUrl/data-saver/$hash/$file')
          .toList(growable: false);

      return (dataUrls: dataUrls, dataSaverUrls: dataSaverUrls);
    } catch (_) {
      return (dataUrls: const <String>[], dataSaverUrls: const <String>[]);
    }
  }

  /// Просмотр каталога манги и манхвы с фильтрацией по языку оригинала и переводу (`ru`).
  Future<List<MangaDexManga>> browseManga({
    String? originalLanguage,
    String? availableTranslatedLanguage,
    String? status,
    String order = 'followedCount',
    int limit = 40,
    int offset = 0,
    String? query,
  }) async {
    try {
      final params = <String, dynamic>{
        'limit': limit,
        'offset': offset,
        'includes[]': 'cover_art',
        'contentRating[]': ['safe', 'suggestive'],
        'order[$order]': 'desc',
      };
      if (originalLanguage != null && originalLanguage.isNotEmpty) {
        params['originalLanguage[]'] = originalLanguage;
      }
      if (availableTranslatedLanguage != null &&
          availableTranslatedLanguage.isNotEmpty) {
        params['availableTranslatedLanguage[]'] = [availableTranslatedLanguage];
      }
      if (status != null && status.isNotEmpty) {
        params['status[]'] = [status];
      }
      if (query != null && query.trim().isNotEmpty) {
        params['title'] = query.trim();
      }

      final res = await _dio.get('/manga', queryParameters: params);
      final body = res.data;
      if (body is! Map || body['data'] is! List) return const [];
      return _parseMangaList(body['data'] as List);
    } catch (_) {
      return const [];
    }
  }

  /// Загружает информацию о манге по ID MangaDex.
  Future<MangaDexManga?> getMangaById(String mangaId) async {
    if (mangaId.trim().isEmpty) return null;
    try {
      final res = await _dio.get(
        '/manga/$mangaId',
        queryParameters: const {'includes[]': 'cover_art'},
      );
      final body = res.data;
      if (body is! Map || body['data'] is! Map) return null;
      final parsed = _parseMangaList([body['data']]);
      return parsed.isNotEmpty ? parsed.first : null;
    } catch (_) {
      return null;
    }
  }

  List<MangaDexManga> _parseMangaList(List<dynamic> rawList) {
    final results = <MangaDexManga>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;

      final attrs = item['attributes'] is Map
          ? item['attributes'] as Map
          : const <String, dynamic>{};
      final titleMap = attrs['title'] is Map
          ? attrs['title'] as Map
          : const <String, dynamic>{};

      String? altRuTitle;
      final altTitles = attrs['altTitles'];
      if (altTitles is List) {
        for (final entry in altTitles) {
          if (entry is Map) {
            final ruVal = (entry['ru'] ?? '').toString().trim();
            if (ruVal.isNotEmpty) {
              altRuTitle = ruVal;
              break;
            }
          }
        }
      }

      final primaryRu = (titleMap['ru'] ?? '').toString().trim();
      final primaryEn = (titleMap['en'] ?? '').toString().trim();
      final fallbackTitle = titleMap.values.isNotEmpty
          ? titleMap.values.first.toString().trim()
          : '';

      final resolvedTitle = primaryRu.isNotEmpty
          ? primaryRu
          : (altRuTitle ??
              (primaryEn.isNotEmpty ? primaryEn : fallbackTitle));
      if (resolvedTitle.isEmpty) continue;

      final origTitleCandidate = primaryEn.isNotEmpty
          ? primaryEn
          : (titleMap['ja-ro'] ??
                  titleMap['ja'] ??
                  titleMap['ko-ro'] ??
                  titleMap['ko'] ??
                  fallbackTitle)
              .toString()
              .trim();

      final origLang = attrs['originalLanguage']?.toString();
      final langsList = attrs['availableTranslatedLanguages'] is List
          ? (attrs['availableTranslatedLanguages'] as List)
              .map((e) => e.toString().trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList()
          : const <String>[];
      final linksMap = attrs['links'] is Map ? attrs['links'] as Map : null;
      final malId = linksMap?['mal']?.toString().trim();
      final latestChap = attrs['latestUploadedChapter']?.toString().trim();
      final status = attrs['status']?.toString().trim();
      final descMap =
          attrs['description'] is Map ? attrs['description'] as Map : null;
      final description = (descMap?['ru'] ?? descMap?['en'] ?? '')
          .toString()
          .trim();
      String coverUrl = '';
      final rels = item['relationships'];
      if (rels is List) {
        for (final rel in rels) {
          if (rel is Map && rel['type'] == 'cover_art') {
            final relAttrs = rel['attributes'];
            if (relAttrs is Map) {
              final fileName = relAttrs['fileName']?.toString() ?? '';
              if (fileName.isNotEmpty) {
                coverUrl =
                    'https://uploads.mangadex.org/covers/$id/$fileName.512.jpg';
                break;
              }
            }
          }
        }
      }

      results.add(
        MangaDexManga(
          id: id,
          title: resolvedTitle,
          originalTitle: origTitleCandidate.isNotEmpty ? origTitleCandidate : null,
          coverUrl: coverUrl,
          originalLanguage: origLang,
          malId: (malId != null && malId.isNotEmpty) ? malId : null,
          availableTranslatedLanguages: langsList,
          latestUploadedChapter:
              (latestChap != null && latestChap.isNotEmpty) ? latestChap : null,
          description: description.isNotEmpty ? description : null,
          status: (status != null && status.isNotEmpty) ? status : null,
        ),
      );
    }
    return results;
  }
}

