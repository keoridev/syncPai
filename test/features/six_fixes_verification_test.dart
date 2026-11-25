import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/widgets/app_avatar.dart';
import 'package:sync_pai/core/widgets/holographic_monogram_avatar.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/anime_details/domain/entities/anime_video_item.dart';
import 'package:sync_pai/features/anime_details/presentation/screens/anime_details_screen.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_cubit.dart';

class _FakeCatalogRepo implements CatalogRepository {
  int lastRequestedPage = 0;

  List<AnimeTitle> makeBatch(int start, int count) => List.generate(
        count,
        (i) => AnimeTitle(
          id: start + i,
          code: 'a_${start + i}',
          russianTitle: 'Аниме ${start + i}',
          englishTitle: 'Anime ${start + i}',
          description: 'Описание тайтла ${start + i}',
          status: 'Онгоинг',
          posterOriginal: '',
          posterMedium: '',
          posterSmall: '',
          genres: const ['Фэнтези'],
          year: 2026,
        ),
      );

  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async {
    lastRequestedPage = page;
    return makeBatch((page - 1) * 20 + 1, 20);
  }

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20}) async =>
      const [];

  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) =>
      throw UnimplementedError();
}

class _FakeShikimoriRemoteDS implements ShikimoriRemoteDataSource {
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

class _MockShikimoriAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    expect(options.followRedirects, isTrue);
    if (options.path.contains('/animes/') &&
        options.path.contains('/screenshots')) {
      return ResponseBody.fromString(
        jsonEncode([
          {'original': '/system/screenshots/original/1.jpg'},
        ]),
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
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
      'AppAvatar falls back gracefully to monogram when local path does not exist',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppAvatar(
            avatarUrl:
                '/data/user/0/com.syncpai/cache/missing_custom_avatar_999.jpg',
            username: 'PaiUser',
            size: 48,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(HolographicMonogramAvatar), findsOneWidget);
  });

  test(
      'ShikimoriRemoteDataSourceImpl uses shikimori.io API base and enables followRedirects',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://shikimori.io/api'));
    final adapter = _MockShikimoriAdapter();
    dio.httpClientAdapter = adapter;

    final ds = ShikimoriRemoteDataSourceImpl(
      customDio: dio,
      minRequestInterval: Duration.zero,
      retry429Delay: Duration.zero,
    );

    final shots = await ds.getScreenshots(52991);
    expect(adapter.requests, 1);
    expect(shots, ['https://shikimori.io/system/screenshots/original/1.jpg']);
  });

  test(
      'CatalogCubit.loadUpdates replaces <12 snapshot items and loadNextPage fetches page 2',
      () async {
    final repo = _FakeCatalogRepo();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );

    // Seed small 4-item snapshot state
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    cubit.emit(
      CatalogLoaded(
        titles: repo.makeBatch(900, 4),
        filteredTitles: repo.makeBatch(900, 4),
      ),
    );

    await cubit.loadUpdates();
    expect(repo.lastRequestedPage, 1);
    final loaded1 = cubit.state as CatalogLoaded;
    expect(loaded1.titles.length, 20);
    expect(loaded1.hasMore, isTrue);

    await cubit.loadNextPage();
    expect(repo.lastRequestedPage, 2);
    final loaded2 = cubit.state as CatalogLoaded;
    expect(loaded2.titles.length, 40);
    await cubit.close();
  });

  testWidgets(
      'AnimeDetailsScreen renders clickable #191F2B genre pills and 4-line synopsis toggle',
      (tester) async {
    final repo = _FakeCatalogRepo();
    final catalogCubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    catalogCubit.emit(const CatalogLoaded(titles: [], filteredTitles: []));
    getIt.registerSingleton<CatalogCubit>(catalogCubit);

    final settingsCubit = SettingsCubit();
    getIt.registerSingleton<SettingsCubit>(settingsCubit);
    getIt.registerSingleton<ShikimoriRemoteDataSource>(_FakeShikimoriRemoteDS());

    const longSynopsis =
        'Очень длинное описание истории, которое гарантированно занимает больше четырёх строк текста на мобильном и десктопном экране, чтобы проверить кнопку разворачивания описания и её корректное переключение между состояниями. '
        'Второй абзац описания добавляет ещё деталей о главных героях, их путешествии по волшебному миру и древних тайнах, которые им предстоит раскрыть вместе с верными друзьями.';

    const title = AnimeTitle(
      id: 777,
      code: 'frieren',
      russianTitle: 'Провожающая в последний путь Фрирен',
      englishTitle: 'Sousou no Frieren',
      description: longSynopsis,
      status: 'Завершён',
      posterOriginal: '',
      posterMedium: '',
      posterSmall: '',
      year: 2023,
      kind: 'TV',
      episodesTotal: 28,
      score: 9.3,
      genres: ['Фэнтези', 'Приключения', 'Драма'],
    );

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await catalogCubit.close();
      await settingsCubit.close();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: AnimeDetailsScreen(title: title),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    for (final g in title.genres) {
      expect(find.byKey(ValueKey('details_genre_pill_$g')), findsOneWidget);
    }
    expect(find.text('9.3'), findsOneWidget);
    expect(find.text('Развернуть описание'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('details_synopsis_toggle')));
    await tester.pump();
    expect(find.text('Свернуть'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('details_genre_pill_Драма')));
    await tester.pump(const Duration(milliseconds: 100));
    expect((catalogCubit.state as CatalogLoaded).selectedGenres, {'Драма'});
  });
}
