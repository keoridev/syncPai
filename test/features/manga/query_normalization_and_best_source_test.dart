import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/manga/data/datasources/desu_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/remanga_datasource.dart';
import 'package:sync_pai/features/manga/data/repositories/manga_repository.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';

class _EmptyMangaDexAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({'data': []}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _StubDesuAdapter implements HttpClientAdapter {
  final List<String> searched = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/' || options.path.isEmpty) {
      searched.add((options.queryParameters['search'] ?? '').toString());
      return ResponseBody.fromString(
        jsonEncode({
          'response': [
            {
              'id': 888,
              'russian': 'Невообразимые приключения перерождённого дворянина',
              'name': 'Tensei Kizoku no Isekai Boukenroku',
              'kind': 'manga',
            },
          ],
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
          'chapters': {
            'list': [
              {'id': 1, 'vol': 1, 'ch': 1, 'title': 'Глава 1'},
              {'id': 2, 'vol': 1, 'ch': 2, 'title': 'Глава 2'},
              {'id': 3, 'vol': 1, 'ch': 3, 'title': 'Глава 3'},
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

  test('MangaRepository.sanitizeSearchQuery and buildNormalizedQueries strip ~, :, (, — suffixes', () {
    expect(
      MangaRepository.sanitizeSearchQuery(
        'Tensei Kizoku no Isekai Boukenroku ~Jichou wo Shiranai~',
      ),
      'Tensei Kizoku no Isekai Boukenroku',
    );
    expect(
      MangaRepository.buildNormalizedQueries(
        'Fuufu Ijou, Koibito Miman. (Manga)',
        'Больше чем любовники — меньше чем друзья',
      ),
      [
        'Fuufu Ijou, Koibito Miman.',
        'Больше чем любовники',
        'Fuufu Ijou, Koibito Miman. (Manga)',
        'Больше чем любовники — меньше чем друзья',
      ],
    );
  });

  test('MangaRepository.getChapters picks Desu.uno when MangaDex has 0 RU chapters', () async {
    final prefs = await SharedPreferences.getInstance();
    final mdDio = Dio(BaseOptions(baseUrl: 'https://api.mangadex.org'));
    mdDio.httpClientAdapter = _EmptyMangaDexAdapter();

    final remangaDio = Dio(BaseOptions(baseUrl: 'https://api.remanga.org/api'));
    remangaDio.httpClientAdapter = _EmptyMangaDexAdapter();

    final desuAdapter = _StubDesuAdapter();
    final desuDio = Dio(BaseOptions(baseUrl: 'https://desu.uno/manga/api'));
    desuDio.httpClientAdapter = desuAdapter;

    final repo = MangaRepository(
      remanga: RemangaDataSource(customDio: remangaDio),
      desu: DesuDataSource(customDio: desuDio),
      mangadex: MangaDexDataSource(customDio: mdDio),
      prefs: prefs,
    );

    const manga = MangaDexManga(
      id: 'md-uuid-123',
      title: 'Невообразимые приключения перерождённого дворянина',
      originalTitle: 'Tensei Kizoku no Isekai Boukenroku ~Jichou wo Shiranai~',
      coverUrl: '',
    );

    final chapters = await repo.getChapters(manga);
    expect(chapters.length, 3);
    expect(chapters.first.source, 'Desu');
    expect(desuAdapter.searched.first, 'Tensei Kizoku no Isekai Boukenroku');
  });
}

