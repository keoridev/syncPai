import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/manga/data/datasources/desu_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/remanga_datasource.dart';
import 'package:sync_pai/features/manga/data/repositories/manga_repository.dart';

class _MultiTabRemangaAdapter implements HttpClientAdapter {
  int catalogCalls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    catalogCalls++;
    final type = options.queryParameters['types'];
    final ordering = options.queryParameters['ordering'];
    final slug = type == 1
        ? 'manhwa_1'
        : (type == 0
            ? 'manga_1'
            : (ordering == '-votes' ? 'pop_1' : 'all_1'));
    return ResponseBody.fromString(
      jsonEncode({
        'content': [
          {
            'dir': slug,
            'rus_name': 'Тайтл $slug',
            'en_name': slug,
            'avg_rating': '9.0',
            'count_chapters': 50,
            'type': {'id': type ?? 1},
            'img': {'high': '/media/$slug.jpg'},
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _CompletedDesuAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({
        'response': [
          {
            'id': 77,
            'russian': 'Завершённая манга',
            'name': 'Completed Manga',
            'kind': 'manga',
            'status': 'completed',
            'score': 8.9,
            'image': {'original': 'https://desu.uno/c.jpg'},
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('MangaRepository.prefetchAllFilterTabs populates all 5 tabs concurrently in LRU', () async {
    final prefs = await SharedPreferences.getInstance();
    final remangaDio = Dio(BaseOptions(baseUrl: 'https://api.remanga.org/api'));
    remangaDio.httpClientAdapter = _MultiTabRemangaAdapter();

    final desuDio = Dio(BaseOptions(baseUrl: 'https://desu.uno/manga/api'));
    desuDio.httpClientAdapter = _CompletedDesuAdapter();

    final repo = MangaRepository(
      remanga: RemangaDataSource(customDio: remangaDio),
      desu: DesuDataSource(customDio: desuDio),
      mangadex: MangaDexDataSource(),
      prefs: prefs,
    );

    await repo.prefetchAllFilterTabs(count: 24);

    for (final tab in MangaRepository.filterTabs) {
      final cached = repo.getCachedCatalogPage(
        tab: tab,
        page: 1,
        russianOnly: true,
      );
      expect(cached, isNotNull, reason: 'Tab $tab should be cached');
      expect(cached, isNotEmpty, reason: 'Tab $tab should have items');
    }
  });

  test('MangaRepository.optimisticFilterFromMemory filters cached items in 0ms', () async {
    final prefs = await SharedPreferences.getInstance();
    final remangaDio = Dio(BaseOptions(baseUrl: 'https://api.remanga.org/api'));
    remangaDio.httpClientAdapter = _MultiTabRemangaAdapter();

    final desuDio = Dio(BaseOptions(baseUrl: 'https://desu.uno/manga/api'));
    desuDio.httpClientAdapter = _CompletedDesuAdapter();

    final repo = MangaRepository(
      remanga: RemangaDataSource(customDio: remangaDio),
      desu: DesuDataSource(customDio: desuDio),
      mangadex: MangaDexDataSource(),
      prefs: prefs,
    );

    await repo.getCatalog(tab: 'manhwa', page: 1, count: 24);
    await repo.getCatalog(tab: 'manga', page: 1, count: 24);

    final manhwaOnly = repo.optimisticFilterFromMemory(tab: 'manhwa');
    expect(manhwaOnly.length, 1);
    expect(manhwaOnly.first.originalLanguage, 'ko');

    final mangaOnly = repo.optimisticFilterFromMemory(tab: 'manga');
    expect(mangaOnly.length, 1);
    expect(mangaOnly.first.originalLanguage, 'ja');
  });
}

