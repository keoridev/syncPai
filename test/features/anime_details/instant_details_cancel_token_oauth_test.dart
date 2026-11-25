import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/theme/app_theme.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/anime_details/domain/entities/anime_video_item.dart';
import 'package:sync_pai/features/anime_details/presentation/screens/anime_details_screen.dart';
import 'package:sync_pai/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_entity.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/domain/entities/translation_entity.dart';
import 'package:sync_pai/features/catalog/domain/repositories/anime_catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_player_links_usecase.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';

class _RealHttpOverrides extends HttpOverrides {}

class _FastPlayerLinksUseCase implements GetPlayerLinksUseCase {
  @override
  AnimeCatalogRepository get repository => throw UnimplementedError();

  @override
  Future<List<TranslationEntity>> call(int releaseId, {String? title}) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return const [
      TranslationEntity(
        studioName: 'AniLiberty',
        translationType: 'dub',
        isDirectStream: true,
        episodes: [
          EpisodeEntity(
            episode: 1,
            link: 'https://example.com/ep1.m3u8',
            name: 'Первая серия',
          ),
        ],
      ),
    ];
  }
}

class _SlowShikimoriDataSource implements ShikimoriRemoteDataSource {
  @override
  Future<ShikimoriRatingAndReviews> getReviewsAndRatings(AnimeTitle title) async {
    await Future<void>.delayed(const Duration(seconds: 3));
    return const ShikimoriRatingAndReviews(
      portalScores: {'Shikimori': 8.9},
      reviews: [],
    );
  }

  @override
  Future<List<AnimeVideoItem>> getVideos({int? shikimoriId, String? query, String? fallbackPoster}) async => const [];

  @override
  Future<List<String>> getScreenshots(int shikimoriId) async => const [];

  @override
  Future<AdaptedMangaInfo?> getAdaptedManga(int shikimoriAnimeId) async => null;

  @override
  Future<int?> resolveShikimoriId(AnimeTitle title) async => null;

  @override
  Future<List<AnimeTitle>> getUpcomingAnnouncements({
    int page = 1,
    int limit = 40,
  }) async =>
      const [];

  @override
  Future<List<AnimeTitle>> getSimilarAnimes(int shikimoriId) async => const [];
}

class _FakeAnimeRepo implements CatalogRepository {
  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) async =>
      AnimeTitle(
        id: id ?? 1,
        code: code ?? 'code_${id ?? 1}',
        russianTitle: 'Test ${id ?? 1}',
        englishTitle: 'Test ${id ?? 1}',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: const ['Экшен'],
        description: 'Desc',
        status: 'Онгоинг',
        episodes: const [EpisodeItem(episode: 1, name: 'Ep 1')],
      );

  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async =>
      const [];

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20}) async =>
      const [];
}

void main() {
  group('AnimeDetailsCache SWR LRU (max 50 entries, 30-min TTL)', () {
    setUp(AnimeDetailsCache.clear);

    test('evicts oldest entry beyond 50 and expires after 30 minutes', () {
      for (var i = 1; i <= 55; i++) {
        AnimeDetailsCache.putTitle(
          AnimeTitle(
            id: i,
            code: 'c_$i',
            russianTitle: 'Title $i',
            englishTitle: 'Title $i',
            posterSmall: '',
            posterMedium: '',
            posterOriginal: '',
            genres: const ['Экшен'],
            description: 'Desc',
            status: 'Онгоинг',
          ),
        );
      }

      // Oldest 5 (1..5) should be evicted; 6..55 remain
      expect(AnimeDetailsCache.get(1), isNull);
      expect(AnimeDetailsCache.get(5), isNull);
      expect(AnimeDetailsCache.get(6), isNotNull);
      expect(AnimeDetailsCache.get(55), isNotNull);

      final expired = CachedAnimeDetails(
        title: AnimeDetailsCache.get(55)!.title,
        cachedAt: DateTime.now().subtract(const Duration(minutes: 31)),
      );
      expect(expired.isExpired, isTrue);
    });
  });

  group('CatalogCubit rapid category switching & CancelToken', () {
    test('rapid onCategoryChanged calls do not throw or double-cancel', () async {
      final repo = _FakeAnimeRepo();
      final cubit = CatalogCubit(
        getUpdates: GetUpdates(repo),
        searchTitles: SearchTitles(repo),
      );
      addTearDown(cubit.close);

      cubit.onCategoryChanged('Все');
      cubit.onCategoryChanged('Сёнэн');
      cubit.onCategoryChanged('Экшен');
      cubit.onCategoryChanged('Комедия');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.isClosed, isFalse);
    });
  });

  group('Desktop Google OAuth loopback HttpServer', () {
    test('skips /favicon.ico, captures PKCE code URI and returns Russian dark HTML page', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        final callbackFuture = AuthRepositoryImpl.awaitDesktopOAuthCallback(server);

        final client = HttpClient();
        addTearDown(client.close);

        // 1. Browser favicon request should be ignored with 204
        final favReq = await client.get('127.0.0.1', server.port, '/favicon.ico');
        final favRes = await favReq.close();
        expect(favRes.statusCode, HttpStatus.noContent);

        // 2. Real OAuth redirect with PKCE code
        final authReq = await client.get('127.0.0.1', server.port, '/?code=pkce_test_123');
        final authRes = await authReq.close();
        final body = await authRes.transform(utf8.decoder).join();

        expect(authRes.statusCode, HttpStatus.ok);
        expect(body, contains('Вход выполнен!'));
        expect(body, contains('SyncPai'));

        final capturedUri = await callbackFuture;
        expect(capturedUri.queryParameters['code'], 'pkce_test_123');
      }, _RealHttpOverrides());
    });
  });

  group('AnimeDetailsScreen non-blocking decoupled render', () {
    setUp(AnimeDetailsCache.clear);

    testWidgets('renders title, CTA and fast Episode 1 within 100ms while slow 3s Shikimori is pending', (tester) async {
      final hadPlayerLinks = getIt.isRegistered<GetPlayerLinksUseCase>();
      final hadShikimori = getIt.isRegistered<ShikimoriRemoteDataSource>();
      final prevPlayerLinks = hadPlayerLinks ? getIt<GetPlayerLinksUseCase>() : null;
      final prevShikimori = hadShikimori ? getIt<ShikimoriRemoteDataSource>() : null;

      if (hadPlayerLinks) getIt.unregister<GetPlayerLinksUseCase>();
      if (hadShikimori) getIt.unregister<ShikimoriRemoteDataSource>();
      getIt.registerSingleton<GetPlayerLinksUseCase>(_FastPlayerLinksUseCase());
      getIt.registerSingleton<ShikimoriRemoteDataSource>(_SlowShikimoriDataSource());

      addTearDown(() {
        if (getIt.isRegistered<GetPlayerLinksUseCase>()) {
          getIt.unregister<GetPlayerLinksUseCase>();
        }
        if (prevPlayerLinks != null) {
          getIt.registerSingleton<GetPlayerLinksUseCase>(prevPlayerLinks);
        }
        if (getIt.isRegistered<ShikimoriRemoteDataSource>()) {
          getIt.unregister<ShikimoriRemoteDataSource>();
        }
        if (prevShikimori != null) {
          getIt.registerSingleton<ShikimoriRemoteDataSource>(prevShikimori);
        }
      });

      const summaryTitle = AnimeTitle(
        id: 777,
        code: 'instant-test',
        russianTitle: 'Моментальное Аниме',
        englishTitle: 'Instant Anime',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Экшен', 'Фэнтези'],
        description: 'Краткое описание из каталога.',
        status: 'Онгоинг',
        year: 2026,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.cinemaDark,
          home: const AnimeDetailsScreen(title: summaryTitle),
        ),
      );

      // Frame 1: summary metadata & primary CTA render immediately
      expect(find.text('Моментальное Аниме'), findsOneWidget);
      expect(find.text('Смотреть'), findsOneWidget);

      // At 100ms: fast 50ms AniLibria episodes are already loaded and cached while 3s Shikimori is still pending
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 40));
      expect(AnimeDetailsCache.get(777)?.title.episodes.length, 1);

      await tester.scrollUntilVisible(
        find.text('Серия 1'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Серия 1'), findsOneWidget);

      // Advance past the 3s slow Shikimori timer so no pending timers remain
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });
}
