import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/anime_details/domain/entities/anime_video_item.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/mangaupdates_datasource.dart';
import 'package:sync_pai/features/manga/data/services/anime_manga_bridge_service.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';
import 'package:sync_pai/features/manga/presentation/cubit/user_manga_list_cubit.dart';
import 'package:sync_pai/features/manga/presentation/widgets/user_manga_list_view.dart';

class _FastShikimoriDS implements ShikimoriRemoteDataSource {
  int adaptedCalls = 0;

  @override
  Future<AdaptedMangaInfo?> getAdaptedManga(int shikimoriAnimeId) async {
    adaptedCalls++;
    return const AdaptedMangaInfo(
      shikimoriMangaId: 10,
      russianTitle: 'Токийские мстители',
      englishTitle: 'Tokyo Revengers',
      coverUrl: '',
    );
  }

  @override
  Future<ShikimoriRatingAndReviews> getReviewsAndRatings(AnimeTitle title) async =>
      const ShikimoriRatingAndReviews(portalScores: {}, reviews: []);

  @override
  Future<List<String>> getScreenshots(int shikimoriId) async => const [];

  @override
  Future<List<AnimeTitle>> getSimilarAnimes(int shikimoriId) async => const [];

  @override
  Future<List<AnimeTitle>> getUpcomingAnnouncements({
    int page = 1,
    int limit = 40,
  }) async =>
      const [];

  @override
  Future<List<AnimeVideoItem>> getVideos({
    int? shikimoriId,
    String? query,
    String? fallbackPoster,
  }) async =>
      const [];

  @override
  Future<int?> resolveShikimoriId(AnimeTitle title) async => 42249;
}

class _SlowMangaUpdatesDS extends MangaUpdatesDataSource {
  @override
  Future<int?> getAnimeEndChapter(String englishTitle) async {
    await Future<void>.delayed(const Duration(seconds: 5));
    return 77;
  }
}

class _FastMangaDexDS extends MangaDexDataSource {
  @override
  Future<List<MangaDexManga>> searchManga(String title) async {
    return const [
      MangaDexManga(
        id: 'md-tokyo-revengers',
        title: 'Tokyo Revengers',
        coverUrl: '',
      ),
    ];
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    final prefs = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(prefs);
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('AnimeMangaBridgeService enforces 2500ms MangaUpdates timeout and caches in SharedPreferences', () async {
    final shiki = _FastShikimoriDS();
    final service = AnimeMangaBridgeService.forTest(
      shikimoriDataSource: shiki,
      mangaUpdatesDataSource: _SlowMangaUpdatesDS(),
      mangaDexDataSource: _FastMangaDexDS(),
    );

    const title = AnimeTitle(
      id: 99123,
      shikimoriId: 42249,
      code: 'tokyo',
      russianTitle: 'Токийские мстители',
      englishTitle: 'Tokyo Revengers',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: [],
      description: '',
      status: 'Вышел',
    );

    final sw = Stopwatch()..start();
    final bridge = await service.resolveForAnime(title);
    sw.stop();

    expect(bridge, isNotNull);
    expect(bridge!.mangaDexId, 'md-tokyo-revengers');
    expect(bridge.continueFromChapter, isNull); // Timed out at 2500ms cleanly
    expect(sw.elapsedMilliseconds, lessThan(3500));

    // Fresh service instance reads from SharedPreferences in 0ms without calling Shikimori
    final shiki2 = _FastShikimoriDS();
    final service2 = AnimeMangaBridgeService.forTest(
      shikimoriDataSource: shiki2,
      mangaUpdatesDataSource: _SlowMangaUpdatesDS(),
      mangaDexDataSource: _FastMangaDexDS(),
    );
    final cached = await service2.resolveForAnime(title);
    expect(cached, isNotNull);
    expect(cached!.mangaDexId, 'md-tokyo-revengers');
    expect(shiki2.adaptedCalls, 0);
  });

  testWidgets('UserMangaListCubit auto-adds to Читаю and UserMangaListView renders 4 tabs + Продолжить button', (tester) async {
    final prefs = getIt<SharedPreferences>();
    final cubit = UserMangaListCubit(prefs);
    getIt.registerSingleton<UserMangaListCubit>(cubit);

    await cubit.recordAutoProgress(
      mangaId: 'md-1',
      mangaTitle: 'Кошечка из Сакурасо',
      coverUrl: '',
      chapterLabel: '14',
      pageIndex: 3,
      chaptersCount: 85,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              UserMangaListView(),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Читаю (1)'), findsOneWidget);
    expect(find.text('В планах'), findsOneWidget);
    expect(find.text('Прочитано'), findsOneWidget);
    expect(find.text('Брошено'), findsOneWidget);
    expect(find.text('Глава 14 / 85'), findsOneWidget);
    expect(find.text('Продолжить'), findsOneWidget);

    await cubit.close();
  });
}

