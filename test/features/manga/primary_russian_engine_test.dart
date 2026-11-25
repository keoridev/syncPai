import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/manga/data/datasources/desu_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/remanga_datasource.dart';
import 'package:sync_pai/features/manga/data/repositories/manga_repository.dart';

class _FakeRemangaAdapter implements HttpClientAdapter {
  int catalogCalls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.contains('/search/catalog/')) {
      catalogCalls++;
      return ResponseBody.fromString(
        jsonEncode({
          'content': [
            {
              'dir': 'solo_leveling',
              'rus_name': 'Поднятие уровня в одиночку',
              'en_name': 'Solo Leveling',
              'avg_rating': '9.4',
              'count_chapters': 200,
              'type': {'id': 1},
              'img': {'high': '/media/solo.jpg'},
            },
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (path.contains('/titles/solo_leveling/')) {
      return ResponseBody.fromString(
        jsonEncode({
          'content': {
            'branches': [
              {'id': 7, 'count_chapters': 200},
            ],
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (path.contains('/v2/titles/chapters/')) {
      return ResponseBody.fromString(
        jsonEncode({
          'content': [
            {
              'id': 11,
              'tome': 1,
              'chapter': '1',
              'name': 'Бесплатная',
              'is_paid': false,
              'count_pages': 20,
              'publishers': [
                {'name': 'ReTeam'},
              ],
            },
            {
              'id': 12,
              'tome': 1,
              'chapter': '2',
              'name': 'Платная',
              'is_paid': true,
              'count_pages': 22,
              'publishers': [
                {'name': 'ReTeam'},
              ],
            },
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(jsonEncode({'content': []}), 200);
  }
}

class _FakeDesuAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path == '/' || path.isEmpty) {
      return ResponseBody.fromString(
        jsonEncode({
          'response': [
            {
              'id': 501,
              'russian': 'Поднятие уровня в одиночку',
              'name': 'Solo Leveling',
              'kind': 'manhwa',
              'score': 9.1,
              'image': {'original': 'https://desu.uno/solo.jpg'},
            },
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (path == '/501') {
      return ResponseBody.fromString(
        jsonEncode({
          'response': {
            'chapters': {
              'list': [
                {'id': 9001, 'vol': 1, 'ch': 1, 'title': 'Глава 1'},
                {'id': 9002, 'vol': 1, 'ch': 2, 'title': 'Зеркало платной'},
              ],
            },
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'response': {
          'pages': {
            'list': [
              {'img': 'https://desu.uno/p1.jpg'},
            ],
          },
        },
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

  test('MangaRepository uses ReManga primary catalog, deduplicates concurrent calls, and caches in LRU + disk', () async {
    final prefs = await SharedPreferences.getInstance();
    final remangaAdapter = _FakeRemangaAdapter();
    final remangaDio = Dio(BaseOptions(baseUrl: 'https://api.remanga.org/api'));
    remangaDio.httpClientAdapter = remangaAdapter;

    final desuDio = Dio(BaseOptions(baseUrl: 'https://desu.uno/manga/api'));
    desuDio.httpClientAdapter = _FakeDesuAdapter();

    final repo = MangaRepository(
      remanga: RemangaDataSource(customDio: remangaDio),
      desu: DesuDataSource(customDio: desuDio),
      mangadex: MangaDexDataSource(),
      prefs: prefs,
    );

    // Concurrent calls should deduplicate into 1 network request
    final results = await Future.wait([
      repo.getCatalog(tab: 'all', page: 1, count: 30),
      repo.getCatalog(tab: 'all', page: 1, count: 30),
    ]);
    expect(remangaAdapter.catalogCalls, 1);
    expect(results[0].length, 1);
    expect(results[0].first.title, 'Поднятие уровня в одиночку');
    expect(results[0].first.source, 'Remanga');
    expect(results[0].first.rating, 9.4);

    // Second call hits 0ms LRU cache
    final cached = await repo.getCatalog(tab: 'all', page: 1, count: 30);
    expect(cached.length, 1);
    expect(remangaAdapter.catalogCalls, 1);
  });

  test('MangaRepository mirrors paid ReManga chapters from DesuDataSource', () async {
    final prefs = await SharedPreferences.getInstance();
    final remangaDio = Dio(BaseOptions(baseUrl: 'https://api.remanga.org/api'));
    remangaDio.httpClientAdapter = _FakeRemangaAdapter();

    final desuDio = Dio(BaseOptions(baseUrl: 'https://desu.uno/manga/api'));
    desuDio.httpClientAdapter = _FakeDesuAdapter();

    final repo = MangaRepository(
      remanga: RemangaDataSource(customDio: remangaDio),
      desu: DesuDataSource(customDio: desuDio),
      mangadex: MangaDexDataSource(),
      prefs: prefs,
    );

    final catalog = await repo.getCatalog(tab: 'all', page: 1, count: 30);
    final chapters = await repo.getChapters(catalog.first);

    expect(chapters.length, 2);
    expect(chapters[0].source, 'Remanga');
    expect(chapters[1].source, 'Desu');
    expect(chapters[1].id, 'desu:501:9002');

    final pages = await repo.getChapterPagesWithFallback(chapters[1].id);
    expect(pages.dataUrls, ['https://desu.uno/p1.jpg']);
  });
}

