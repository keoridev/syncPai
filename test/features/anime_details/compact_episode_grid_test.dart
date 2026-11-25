import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/anime_details/domain/entities/anime_video_item.dart';
import 'package:sync_pai/features/anime_details/presentation/screens/anime_details_screen.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';
import 'package:sync_pai/features/watch_history/domain/entities/watch_history_item.dart';
import 'package:sync_pai/features/watch_history/domain/repositories/watch_history_repository.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_cubit.dart';
import 'package:sync_pai/shared/widgets/compact_episode_grid.dart';

class _FakeCatalogRepo implements CatalogRepository {
  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) =>
      throw UnimplementedError();

  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async =>
      const [];

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20}) async =>
      const [];
}

class _FakeShikimoriDS implements ShikimoriRemoteDataSource {
  @override
  Future<AdaptedMangaInfo?> getAdaptedManga(int shikimoriAnimeId) async => null;

  @override
  Future<ShikimoriRatingAndReviews> getReviewsAndRatings(AnimeTitle title) async =>
      const ShikimoriRatingAndReviews(portalScores: {}, reviews: []);

  @override
  Future<List<String>> getScreenshots(int shikimoriId) async => const [];

  @override
  Future<List<AnimeVideoItem>> getVideos({
    int? shikimoriId,
    String? query,
    String? fallbackPoster,
  }) async =>
      const [];

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

class _InMemoryHistoryRepo implements WatchHistoryRepository {
  final List<WatchHistoryItem> items;

  _InMemoryHistoryRepo(this.items);

  @override
  Future<List<WatchHistoryItem>> getAllHistory() async => items;

  @override
  Future<WatchHistoryItem?> getProgress(int titleId) async {
    for (final item in items) {
      if (item.titleId == titleId) return item;
    }
    return null;
  }

  @override
  Future<void> removeProgress(int titleId) async {
    items.removeWhere((e) => e.titleId == titleId);
  }

  @override
  Future<void> saveProgress(WatchHistoryItem item) async {
    items.removeWhere((e) => e.titleId == item.titleId);
    items.insert(0, item);
  }
}

AnimeTitle _buildTitle(int id, int episodeCount) {
  return AnimeTitle(
    id: id,
    code: 'anime-$id',
    russianTitle: 'Тайтл $id',
    englishTitle: 'Title $id',
    posterSmall: '',
    posterMedium: '',
    posterOriginal: '',
    genres: const ['Приключения'],
    description: 'Описание',
    status: 'Онгоинг',
    episodesTotal: episodeCount,
    episodes: List.generate(
      episodeCount,
      (i) => EpisodeItem(
        episode: i + 1,
        name: 'Серия ${i + 1}',
        fhdUrl: 'https://example.com/${i + 1}.m3u8',
      ),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    final repo = _FakeCatalogRepo();
    getIt.registerSingleton<CatalogCubit>(
      CatalogCubit(
        getUpdates: GetUpdates(repo),
        searchTitles: SearchTitles(repo),
      ),
    );
    getIt.registerSingleton<ShikimoriRemoteDataSource>(_FakeShikimoriDS());
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('computeEpisodeRangeIndex & sliceEpisodesForRange handle 1,100 episodes accurately', () {
    final episodes = List.generate(
      1100,
      (i) => EpisodeItem(episode: i + 1),
    );

    expect(computeEpisodeRangeIndex(episodes, 1), 0);
    expect(computeEpisodeRangeIndex(episodes, 100), 0);
    expect(computeEpisodeRangeIndex(episodes, 101), 1);
    expect(computeEpisodeRangeIndex(episodes, 245), 2);
    expect(computeEpisodeRangeIndex(episodes, 1100), 10);

    final chunk2 = sliceEpisodesForRange(episodes, 2);
    expect(chunk2.length, 100);
    expect(chunk2.first.episode, 201);
    expect(chunk2.last.episode, 300);
  });

  testWidgets('AnimeDetailsScreen defaults to compact grid with range chips for 1,050 episodes and auto-jumps to history', (tester) async {
    final historyRepo = _InMemoryHistoryRepo([
      WatchHistoryItem(
        titleId: 9001,
        titleName: 'Тайтл 9001',
        posterUrl: '',
        episode: 245,
        positionMs: 120000,
        durationMs: 1440000,
        updatedAt: DateTime.now(),
      ),
    ]);
    final historyCubit = WatchHistoryCubit(repository: historyRepo);
    await historyCubit.loadHistory();
    getIt.registerSingleton<WatchHistoryCubit>(historyCubit);

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final title = _buildTitle(9001, 1050);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimeDetailsScreen(title: title),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Scroll down to Список серий section (past ResumeProgressCard)
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();

    // Range chips rendered
    expect(find.text('1–100'), findsOneWidget);
    expect(find.text('101–200'), findsOneWidget);
    expect(find.text('201–300'), findsOneWidget);

    // Auto-selected range 201–300 shows episode 245 in compact grid
    expect(find.text('245'), findsOneWidget);
    expect(find.byType(CompactEpisodeTile), findsWidgets);

    // Toggle back to detailed list via header icon toggle
    await tester.tap(find.byKey(const ValueKey('details_episode_view_toggle')));
    await tester.pump();
    expect(find.byType(CompactEpisodeTile), findsNothing);
    expect(find.text('1–100'), findsNothing);
  });

  testWidgets('AnimeDetailsScreen defaults to detailed list for 12 episodes and toggles to compact grid', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final title = _buildTitle(12, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimeDetailsScreen(title: title),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Defaults to list mode (no CompactEpisodeTile)
    expect(find.byType(CompactEpisodeTile), findsNothing);
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);

    // Toggle to compact grid
    await tester.tap(find.byKey(const ValueKey('details_episode_view_toggle')));
    await tester.pump();
    expect(find.byType(CompactEpisodeTile), findsNWidgets(12));
    expect(find.byIcon(Icons.view_agenda_rounded), findsOneWidget);
  });

  testWidgets('CompactEpisodeTile long-press opens quick actions sheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => CompactEpisodeTile(
              episode: const EpisodeItem(episode: 42, name: 'Тест'),
              isActive: true,
              isWatched: false,
              isDownloaded: true,
              onTap: () {},
              onLongPress: () => showEpisodeQuickActionsSheet(
                context,
                episode: const EpisodeItem(episode: 42, name: 'Тест'),
                isDownloaded: false,
                onDownload: () {},
                onMarkWatched: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(CompactEpisodeTile));
    await tester.pumpAndSettle();

    expect(find.text('Скачать серию'), findsOneWidget);
    expect(find.text('Отметить просмотренной'), findsOneWidget);
  });
}

