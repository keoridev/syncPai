import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/mangaupdates_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/remanga_datasource.dart';
import 'package:sync_pai/features/manga/data/services/anime_manga_bridge_service.dart';
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

class _FakeRemangaAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.contains('/search/')) {
      return ResponseBody.fromString(
        jsonEncode({
          'content': [
            {'dir': 'solo_leveling'},
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
              {'id': 101, 'count_chapters': 200},
            ],
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (path.contains('/titles/chapters/') && !path.endsWith('/555/')) {
      return ResponseBody.fromString(
        jsonEncode({
          'content': [
            {
              'id': 555,
              'tome': 1,
              'chapter': '1',
              'name': 'Пробуждение',
              'count_pages': 25,
              'is_paid': false,
              'publishers': [
                {'name': 'SoloTeam'},
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
    return ResponseBody.fromString(
      jsonEncode({
        'content': {
          'pages': [
            {'link': '/media/page1.jpg'},
          ],
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _NullMangaUpdates extends MangaUpdatesDataSource {
  @override
  Future<int?> getAnimeEndChapter(String title) async => null;
}

class _AdaptedShikimori implements ShikimoriRemoteDataSource {
  @override
  Future<AdaptedMangaInfo?> getAdaptedManga(int shikimoriAnimeId) async {
    return const AdaptedMangaInfo(
      shikimoriMangaId: 99,
      russianTitle: 'Магическая битва',
      englishTitle: 'Jujutsu Kaisen',
      coverUrl: '',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubMangaDex extends MangaDexDataSource {
  @override
  Future<List<MangaDexManga>> searchManga(
    String title, {
    int limit = 40,
    int offset = 0,
  }) async {
    return const [
      MangaDexManga(
        id: 'jjk-1',
        title: 'Магическая битва',
        originalTitle: 'Jujutsu Kaisen',
        coverUrl: '',
        originalLanguage: 'ja',
      ),
    ];
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('MangaDexDataSource falls back to RemangaDataSource when MangaDex has 0 RU chapters', () async {
    final mdDio = Dio(BaseOptions(baseUrl: 'https://api.mangadex.org'));
    mdDio.httpClientAdapter = _EmptyMangaDexAdapter();

    final remangaDio = Dio(BaseOptions(baseUrl: 'https://api.remanga.org/api'));
    remangaDio.httpClientAdapter = _FakeRemangaAdapter();
    final remanga = RemangaDataSource(customDio: remangaDio);

    final ds = MangaDexDataSource(customDio: mdDio, remangaDataSource: remanga);
    final chapters = await ds.getChapters('dmca-id', title: 'Поднятие уровня');

    expect(chapters.length, 1);
    expect(chapters.first.source, 'Remanga');
    expect(chapters.first.translatedLanguage, 'ru');
    expect(chapters.first.translatorGroup, 'SoloTeam');
    expect(chapters.first.displayTitle, 'Том 1 • Глава 1 — Пробуждение');

    final pages = await ds.getChapterPagesWithFallback(chapters.first.id);
    expect(pages.dataUrls, ['https://remanga.org/media/page1.jpg']);
  });

  test('AnimeMangaBridgeService computes ~2.5x estimated chapter when MangaUpdates is null', () async {
    AnimeMangaBridge? updated;
    final service = AnimeMangaBridgeService.forTest(
      shikimoriDataSource: _AdaptedShikimori(),
      mangaUpdatesDataSource: _NullMangaUpdates(),
      mangaDexDataSource: _StubMangaDex(),
    );

    const anime = AnimeTitle(
      id: 9001,
      code: 'jjk',
      russianTitle: 'Магическая битва',
      englishTitle: 'Jujutsu Kaisen',
      shikimoriId: 40748,
      episodesTotal: 24,
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: [],
      description: '',
      status: '',
    );

    await service.resolveForAnime(
      anime,
      onChapterOffsetUpdated: (b) => updated = b,
    );

    await Future.delayed(const Duration(milliseconds: 100));
    expect(updated, isNotNull);
    expect(updated!.isEstimatedChapter, isTrue);
    expect(updated!.continueFromChapter, 60);
  });
}

