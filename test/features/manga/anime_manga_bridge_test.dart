import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/core/widgets/mascot/pai_companion_toast.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/mangaupdates_datasource.dart';
import 'package:sync_pai/features/manga/data/repositories/manga_progress_repository.dart';
import 'package:sync_pai/features/manga/data/services/anime_manga_bridge_service.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';
import 'package:sync_pai/features/manga/presentation/screens/manga_reader_screen.dart';

class _StubInterceptor extends Interceptor {
  final dynamic Function(RequestOptions options) responder;

  _StubInterceptor(this.responder);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final data = responder(options);
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: data,
      ),
    );
  }
}

Dio _stubDio(dynamic Function(RequestOptions options) responder) {
  final dio = Dio();
  dio.interceptors.add(_StubInterceptor(responder));
  return dio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MascotCompanionService.instance.resetForTest();
  });

  group('MangaUpdatesDataSource', () {
    test('parseEndChapter parses "Chap 34" and "Vol 4, Chap 34"', () {
      expect(MangaUpdatesDataSource.parseEndChapter('Chap 34'), 34);
      expect(MangaUpdatesDataSource.parseEndChapter('Vol 4, Chap 34'), 34);
      expect(MangaUpdatesDataSource.parseEndChapter('chap 108 (epilogue)'), 108);
      expect(MangaUpdatesDataSource.parseEndChapter('Ongoing'), isNull);
      expect(MangaUpdatesDataSource.parseEndChapter(null), isNull);
    });

    test('getAnimeEndChapter queries search + series details', () async {
      final dio = _stubDio((opts) {
        if (opts.path.contains('/series/search')) {
          return {
            'results': [
              {
                'record': {
                  'series_id': 9988,
                  'title': 'More Than a Married Couple, But Not Lovers.',
                },
              },
            ],
          };
        }
        return {
          'series_id': 9988,
          'anime': {'start': 'Chap 1', 'end': 'Vol 5, Chap 30'},
        };
      });

      final ds = MangaUpdatesDataSource(customDio: dio);
      final endChap = await ds.getAnimeEndChapter(
        'More Than a Married Couple, But Not Lovers.',
      );
      expect(endChap, 30);
    });
  });

  group('ShikimoriRemoteDataSource.getAdaptedManga & MangaDexDataSource', () {
    test('extracts Adaptation manga and resolves chapters (RU priority) & pages',
        () async {
      final shikiDio = _stubDio((opts) {
        if (opts.path.contains('/related')) {
          return [
            {
              'relation': 'Sequel',
              'anime': {'id': 2, 'name': 'Other'},
            },
            {
              'relation': 'Adaptation',
              'manga': {
                'id': 112233,
                'name': 'Fuufu Ijou, Koibito Miman.',
                'russian': 'Больше, чем пара, меньше, чем любовники',
                'kind': 'manga',
                'score': '7.92',
                'chapters': 75,
                'image': {'original': '/system/mangas/original/112233.jpg'},
              },
            },
          ];
        }
        return [];
      });

      final mdDio = _stubDio((opts) {
        if (opts.path == '/manga') {
          return {
            'data': [
              {
                'id': 'md-fuufu-1',
                'attributes': {
                  'title': {'en': 'Fuufu Ijou, Koibito Miman.'},
                  'originalLanguage': 'ja',
                },
                'relationships': [
                  {
                    'type': 'cover_art',
                    'attributes': {'fileName': 'cover123.jpg'},
                  },
                ],
              },
            ],
          };
        }
        if (opts.path == '/manga/md-fuufu-1/feed') {
          return {
            'data': [
              {
                'id': 'ch-31-en',
                'attributes': {
                  'chapter': '31',
                  'title': 'English 31',
                  'translatedLanguage': 'en',
                  'pages': 18,
                },
              },
              {
                'id': 'ch-31-ru',
                'attributes': {
                  'chapter': '31',
                  'title': 'Русская 31',
                  'translatedLanguage': 'ru',
                  'pages': 18,
                },
              },
              {
                'id': 'ch-30-en',
                'attributes': {
                  'chapter': '30',
                  'title': 'English 30',
                  'translatedLanguage': 'en',
                  'pages': 20,
                },
              },
            ],
          };
        }
        if (opts.path == '/at-home/server/ch-31-ru') {
          return {
            'baseUrl': 'https://uploads.mangadex.org',
            'chapter': {
              'hash': 'abc123',
              'data': ['p1.png', 'p2.png'],
            },
          };
        }
        return {};
      });

      final shikiDs = ShikimoriRemoteDataSourceImpl(
        customDio: shikiDio,
        minRequestInterval: Duration.zero,
      );
      final muDs = MangaUpdatesDataSource(
        customDio: _stubDio((opts) {
          if (opts.path.contains('/series/search')) {
            return {
              'results': [
                {
                  'record': {
                    'series_id': 55,
                    'title': 'Fuufu Ijou, Koibito Miman.',
                  },
                },
              ],
            };
          }
          return {
            'anime': {'end': 'Chap 30'},
          };
        }),
      );
      final mdDs = MangaDexDataSource(customDio: mdDio);

      final bridgeService = AnimeMangaBridgeService.forTest(
        shikimoriDataSource: shikiDs,
        mangaUpdatesDataSource: muDs,
        mangaDexDataSource: mdDs,
      );

      const anime = AnimeTitle(
        id: 9455,
        shikimoriId: 50425,
        code: 'fuufu',
        russianTitle: 'Больше, чем пара, меньше, чем любовники',
        englishTitle: 'More Than a Married Couple, But Not Lovers.',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Романтика'],
        description: '',
        status: 'Вышел',
      );

      final bridge = await bridgeService.resolveForAnime(anime);
      expect(bridge, isNotNull);
      expect(bridge!.mangaDexId, 'md-fuufu-1');
      expect(bridge.mangaUpdatesEndChapter, 30);
      expect(bridge.continueFromChapter, 31);

      final chapters = await mdDs.getChapters(bridge.mangaDexId);
      expect(chapters.length, 2);
      expect(chapters[0].chapterLabel, '30');
      expect(chapters[1].chapterLabel, '31');
      expect(chapters[1].translatedLanguage, 'ru');

      final pages = await mdDs.getChapterPages(chapters[1].id);
      expect(pages, [
        'https://uploads.mangadex.org/data/abc123/p1.png',
        'https://uploads.mangadex.org/data/abc123/p2.png',
      ]);
    });
  });

  group('Season Finale Manga Toast & MangaReaderScreen', () {
    testWidgets(
        'PaiCompanionToast shows manga continuation CTA when no anime sequel exists',
        (tester) async {
      MascotCompanionService.instance.setPlayerActive(true);
      bool openedManga = false;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [PaiCompanionToast()],
            ),
          ),
        ),
      );

      MascotCompanionService.instance.onSeasonFinale(
        hasPlayableSequel: false,
        hasAnnouncedSequel: false,
        mangaTitle: 'Больше, чем пара, меньше, чем любовники',
        continueFromChapter: 31,
        onReadManga: () => openedManga = true,
      );
      await tester.pump();

      expect(find.text('Сезон завершён!'), findsOneWidget);
      expect(
        find.text(
          'Продолжения аниме пока нет, но сюжет идёт дальше в манге — начать с 31 главы?',
        ),
        findsOneWidget,
      );
      expect(find.text('Читать с 31 гл.'), findsOneWidget);
      expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pai_companion_action_btn')));
      await tester.pump();
      expect(openedManga, isTrue);
    });

    testWidgets(
        'MangaReaderScreen opens on continueFromChapter, switches Webtoon/Paged modes, and saves progress',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final progressRepo = MangaProgressRepository(prefs);

      final mdDio = _stubDio((opts) {
        if (opts.path.endsWith('/feed')) {
          return {
            'data': [
              {
                'id': 'ch-30',
                'attributes': {
                  'chapter': '30',
                  'title': 'Глава 30',
                  'translatedLanguage': 'ru',
                  'pages': 2,
                },
              },
              {
                'id': 'ch-31',
                'attributes': {
                  'chapter': '31',
                  'title': 'Новая арка',
                  'translatedLanguage': 'ru',
                  'pages': 2,
                },
              },
            ],
          };
        }
        return {
          'baseUrl': 'https://uploads.mangadex.org',
          'chapter': {
            'hash': 'hash1',
            'data': ['1.jpg', '2.jpg'],
          },
        };
      });

      const bridge = AnimeMangaBridge(
        anilibriaId: 9455,
        shikimoriId: 50425,
        mangaDexId: 'md-1',
        mangaTitle: 'Больше, чем пара',
        coverUrl: '',
        mangaUpdatesEndChapter: 30,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MangaReaderScreen(
            bridge: bridge,
            initialChapter: bridge.continueFromChapter,
            dataSource: MangaDexDataSource(customDio: mdDio),
            progressRepository: progressRepo,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Глава 31 — Новая арка'), findsOneWidget);
      expect(find.byKey(const ValueKey('manga_webtoon_list')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('manga_mode_toggle_btn')));
      await tester.pump();
      expect(find.byKey(const ValueKey('manga_paged_view')), findsOneWidget);

      final saved = await progressRepo.getProgress('md-1');
      expect(saved, isNotNull);
      expect(saved!.chapterNumber, '31');
    });
  });
}

