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
import 'package:sync_pai/features/catalog/domain/entities/catalog_settings.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/screens/catalog_screen.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';
import 'package:sync_pai/features/manga/presentation/widgets/manga_catalog_view.dart';

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

class _FakeCatalogRepo implements CatalogRepository {
  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) =>
      throw UnimplementedError();

  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async =>
      List.generate(
        12,
        (i) => AnimeTitle(
          id: i + 1,
          code: 't_${i + 1}',
          russianTitle: 'Очень длинное название аниме-тайтла номер ${i + 1} для проверки переноса строк',
          englishTitle: 'Very Long Anime Title Number ${i + 1}',
          posterSmall: '',
          posterMedium: '',
          posterOriginal: '',
          genres: const ['Экшен', 'Фэнтези'],
          description: 'Описание',
          status: 'Онгоинг',
          year: 2026,
          episodesTotal: 24,
          latestEpisode: 12,
        ),
      );

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
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('CatalogScreen 3-column grid on 360dp phone has zero RenderFlex overflow', (tester) async {
    final repo = _FakeCatalogRepo();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );
    await cubit.loadUpdates();
    cubit.setGridDensity(CatalogGridDensity.compact);
    getIt.registerSingleton<CatalogCubit>(cubit);

    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<CatalogCubit>.value(
          value: cubit,
          child: const CatalogScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    await cubit.close();
  });

  testWidgets('CatalogScreen shows Аниме | Манга toggle and switches to MangaCatalogView', (tester) async {
    final mdDio = Dio()..httpClientAdapter = _EmptyMangaDexAdapter();
    getIt.registerSingleton<MangaDexDataSource>(MangaDexDataSource(customDio: mdDio));
    final repo = _FakeCatalogRepo();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );
    getIt.registerSingleton<CatalogCubit>(cubit);

    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<CatalogCubit>.value(
          value: cubit,
          child: const CatalogScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('catalog_mode_anime')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog_mode_manga')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('catalog_mode_manga')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MangaCatalogView), findsOneWidget);
    expect(find.text('Манхва'), findsOneWidget);
    expect(find.text('Манга'), findsWidgets);

    await cubit.close();
  });

  testWidgets('AnimeDetailsScreen hides Читать мангу when anime has no adapted manga source', (tester) async {
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

    const title = AnimeTitle(
      id: 1,
      code: 't_1',
      russianTitle: 'Тест',
      englishTitle: 'Test',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: ['Экшен'],
      description: 'Описание',
      status: 'Онгоинг',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: AnimeDetailsScreen(title: title),
      ),
    );
    await tester.pump();

    expect(find.text('Читать мангу'), findsNothing);
  });
}
