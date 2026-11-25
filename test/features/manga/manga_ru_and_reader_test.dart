import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/data/repositories/manga_progress_repository.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';
import 'package:sync_pai/features/manga/presentation/screens/manga_reader_screen.dart';

class _MangaRuAndDataSaverAdapter implements HttpClientAdapter {
  final List<Uri> requestedUris = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri);

    if (options.uri.path.contains('/animes/42249/related')) {
      return ResponseBody.fromString(
        jsonEncode([
          {
            'relation': 'Adaptation',
            'relation_russian': 'Первоисточник',
            'manga': {
              'id': 104565,
              'name': 'Tokyo Revengers',
              'russian': 'Токийские мстители',
              'kind': 'manga',
            },
          }
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.uri.path.contains('/mangas/104565')) {
      return ResponseBody.fromString(
        jsonEncode({
          'id': 104565,
          'name': 'Tokyo Revengers',
          'russian': 'Токийские мстители',
          'japanese': ['東京卍リベンジャーズ'],
          'myanimelist_id': 104565,
          'kind': 'manga',
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.uri.path.contains('/feed')) {
      final langs = options.uri.queryParametersAll['translatedLanguage[]'] ?? const [];
      if (langs.contains('ru')) {
        return ResponseBody.fromString(
          jsonEncode({
            'data': [
              {
                'id': 'a1b2c3d4-uuid-0001',
                'attributes': {
                  'chapter': null,
                  'title': 'Ваншот',
                  'translatedLanguage': 'ru',
                  'pages': 12,
                },
              },
              {
                'id': 'a1b2c3d4-uuid-0002',
                'attributes': {
                  'chapter': '1',
                  'title': 'Начало',
                  'translatedLanguage': 'ru',
                  'pages': 20,
                },
              },
            ]
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode({'data': []}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.uri.path.contains('/at-home/server/')) {
      return ResponseBody.fromString(
        jsonEncode({
          'baseUrl': 'https://uploads.mangadex.org',
          'chapter': {
            'hash': 'abc123',
            'data': ['1.jpg'],
            'dataSaver': ['1_saver.jpg'],
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      '[]',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  test('ShikimoriRemoteDataSourceImpl.getAdaptedManga fetches full manga with japanese title and malId', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://shikimori.io/api'));
    dio.transformer = SyncTransformer();
    dio.httpClientAdapter = _MangaRuAndDataSaverAdapter();

    final ds = ShikimoriRemoteDataSourceImpl(
      customDio: dio,
      minRequestInterval: Duration.zero,
    );

    final adapted = await ds.getAdaptedManga(42249);
    expect(adapted, isNotNull);
    expect(adapted!.englishTitle, 'Tokyo Revengers');
    expect(adapted.japaneseTitle, '東京卍リベンジャーズ');
    expect(adapted.malId, 104565);
  });

  test('MangaDexDataSource prioritizes RU chapters, formats null chapters without UUIDs, and parses dataSaver', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.mangadex.org'));
    dio.transformer = SyncTransformer();
    dio.httpClientAdapter = _MangaRuAndDataSaverAdapter();

    final ds = MangaDexDataSource(customDio: dio);
    final chapters = await ds.getChapters('manga-1');

    expect(chapters, hasLength(2));
    expect(chapters.every((c) => c.translatedLanguage == 'ru'), isTrue);
    expect(chapters.any((c) => c.displayTitle.contains('uuid')), isFalse);
    expect(chapters.any((c) => c.displayTitle == 'Спешл — Ваншот'), isTrue);

    final pages = await ds.getChapterPagesWithFallback(chapters.first.id);
    expect(pages.dataUrls, ['https://uploads.mangadex.org/data/abc123/1.jpg']);
    expect(pages.dataSaverUrls, ['https://uploads.mangadex.org/data-saver/abc123/1_saver.jpg']);
  });

  testWidgets('MangaReaderScreen centers desktop webtoon at 760px and shows RU language badge', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final dio = Dio(BaseOptions(baseUrl: 'https://api.mangadex.org'));
    dio.transformer = SyncTransformer();
    dio.httpClientAdapter = _MangaRuAndDataSaverAdapter();
    final ds = MangaDexDataSource(customDio: dio);

    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const bridge = AnimeMangaBridge(
      anilibriaId: 1,
      mangaDexId: 'manga-1',
      mangaTitle: 'Токийские мстители',
      coverUrl: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MangaReaderScreen(
          bridge: bridge,
          dataSource: ds,
          progressRepository: MangaProgressRepository(prefs),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final boxFinder = find.byKey(const ValueKey('manga_webtoon_max_width'));
    expect(boxFinder, findsOneWidget);
    final box = tester.widget<ConstrainedBox>(boxFinder);
    expect(box.constraints.maxWidth, 760);

    expect(find.byKey(const ValueKey('manga_reader_lang_badge')), findsOneWidget);
    expect(find.text('RU'), findsOneWidget);

    // Clear mode pill, explicit chapter nav, and cacheExtent 1800
    expect(find.text('Вебтун'), findsOneWidget);
    expect(find.text('Пред. глава'), findsOneWidget);
    expect(find.text('След. глава'), findsOneWidget);
    final listView = tester.widget<ListView>(find.byKey(const ValueKey('manga_webtoon_list')));
    expect(listView.cacheExtent, 1800);

    // Toggle to Страницы mode
    await tester.tap(find.byKey(const ValueKey('manga_mode_toggle_btn')));
    await tester.pump();
    expect(find.text('Страницы'), findsOneWidget);

    // Pin to profile showcase
    final repo = MangaProgressRepository(prefs);
    await tester.tap(find.byKey(const ValueKey('manga_pin_showcase_btn')));
    await tester.pump();
    final featured = await repo.getFeaturedManga();
    expect(featured, isNotNull);
    expect(featured!.mangaTitle, 'Токийские мстители');
  });
}
