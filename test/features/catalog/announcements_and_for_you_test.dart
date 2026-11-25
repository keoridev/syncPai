import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/anime_details/domain/entities/anime_video_item.dart';
import 'package:sync_pai/features/anime_details/presentation/screens/anime_details_screen.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/catalog_filter.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/catalog/presentation/screens/catalog_screen.dart';
import 'package:sync_pai/features/catalog/presentation/widgets/for_you_recommendations_shelf.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';

class _ShikimoriAnonsAdapter implements HttpClientAdapter {
  Uri? lastUri;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUri = options.uri;
    return ResponseBody.fromBytes(
      utf8.encode(
        jsonEncode([
          {
            'id': 52991,
            'name': 'Sousou no Frieren 2nd Season',
            'russian': 'Провожающая в последний путь Фрирен 2',
            'kind': 'tv',
            'status': 'anons',
            'aired_on': '2026-01-16',
            'season': 'winter_2026',
            'image': {
              'original': '/system/animes/original/52991.jpg',
              'preview': '/system/animes/preview/52991.jpg',
            },
          }
        ]),
      ),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

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
  Future<int?> resolveShikimoriId(AnimeTitle title) async => null;
}

void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('ShikimoriRemoteDataSourceImpl.getUpcomingAnnouncements queries status=anons and maps AnimeTitle', () async {
    final dio = Dio();
    dio.transformer = SyncTransformer();
    final adapter = _ShikimoriAnonsAdapter();
    dio.httpClientAdapter = adapter;

    final ds = ShikimoriRemoteDataSourceImpl(
      customDio: dio,
      minRequestInterval: Duration.zero,
    );

    final items = await ds.getUpcomingAnnouncements(page: 1, limit: 40);
    expect(adapter.lastUri?.host, 'shikimori.io');
    expect(adapter.lastUri?.path, '/api/animes');
    expect(adapter.lastUri?.queryParameters['status'], 'anons');
    expect(adapter.lastUri?.queryParameters['order'], 'popularity');
    expect(items, hasLength(1));
    expect(items.first.isAnnounced, isTrue);
    expect(items.first.episodes, isEmpty);
    expect(items.first.russianTitle, 'Провожающая в последний путь Фрирен 2');
    expect(items.first.posterOriginal, 'https://shikimori.io/system/animes/original/52991.jpg');
    expect(items.first.season, '2026-01-16');
  });

  test('CatalogCubit loads Анонсы under tab:announcements from ShikimoriRemoteDataSource', () async {
    final dio = Dio();
    dio.transformer = SyncTransformer();
    dio.httpClientAdapter = _ShikimoriAnonsAdapter();
    final shikiDs = ShikimoriRemoteDataSourceImpl(
      customDio: dio,
      minRequestInterval: Duration.zero,
    );
    getIt.registerSingleton<ShikimoriRemoteDataSource>(shikiDs);

    final repo = _FakeCatalogRepo();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );

    await cubit.loadSource(const ShikimoriAnnouncedSource('winter_2026'));
    final state = cubit.state as CatalogLoaded;
    expect(state.activeFilterKey, 'tab:announcements');
    expect(state.titles, hasLength(1));
    expect(state.titles.first.isAnnounced, isTrue);

    await cubit.close();
  });

  testWidgets('CatalogScreen has no duplicate top Для тебя shelf and keeps Для тебя tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _FakeCatalogRepo();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );
    getIt.registerSingleton<CatalogCubit>(cubit);

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<CatalogCubit>.value(
          value: cubit,
          child: const CatalogScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ForYouRecommendationsShelf), findsNothing);
    expect(find.text('Для тебя'), findsOneWidget);

    await tester.tap(find.text('Для тебя'));
    await tester.pump();
    expect(find.byKey(const ValueKey('catalog_open_for_you_view')), findsOneWidget);

    await cubit.close();
  });

  testWidgets('AnimeDetailsScreen shows Ожидается выход pill and Добавить в «В планах» CTA for announced anime', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _FakeCatalogRepo();
    getIt.registerSingleton<CatalogCubit>(
      CatalogCubit(
        getUpdates: GetUpdates(repo),
        searchTitles: SearchTitles(repo),
      ),
    );
    getIt.registerSingleton<ShikimoriRemoteDataSource>(_FakeShikimoriDS());

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const announcedTitle = AnimeTitle(
      id: 52991,
      shikimoriId: 52991,
      code: 'shiki_52991',
      russianTitle: 'Фрирен 2',
      englishTitle: 'Frieren 2',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: ['Фэнтези'],
      description: 'Скоро',
      status: 'Анонс',
      season: '2026-01-16',
      isAnnounced: true,
      episodes: [],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: AnimeDetailsScreen(title: announcedTitle),
      ),
    );
    await tester.pump();

    expect(find.text('Ожидается выход'), findsOneWidget);
    expect(find.text('Добавить в «В планах»'), findsOneWidget);
  });
}
