import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/theme/app_theme.dart';
import 'package:sync_pai/features/catalog/data/datasources/anime_remote_datasource.dart';
import 'package:sync_pai/features/catalog/data/services/catalog_persistent_store.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/catalog/presentation/widgets/catalog_filter_sheet.dart';

class _FailingCatalogRepository implements CatalogRepository {
  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async {
    throw Exception('HTTP 422');
  }

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20}) async =>
      const [];

  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) async =>
      throw UnimplementedError();
}

class _GenreRefMockAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.contains('/references/genres')) {
      final body = jsonEncode({
        'data': [
          {'id': 4, 'name': 'Сёнен'},
          {'id': 5, 'name': 'Сэйнэн'},
          {'id': 7, 'name': 'Школа'},
          {'id': 9, 'name': 'Мистика'},
          {'id': 19, 'name': 'Психология'},
          {'id': 29, 'name': 'Фэнтези'},
        ],
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode({
        'data': [
          {
            'id': 10,
            'alias': 'test-release',
            'name': {'main': 'Тест Сёнен', 'english': 'Test Shounen'},
            'poster': {'src': 'https://example.com/10.jpg'},
            'year': 2025,
            'genres': [
              {'id': 4, 'name': 'Сёнен'},
            ],
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Dynamic AniLibria Genre Reference Sync & Hybrid Alias Matching', () {
    test('fetches live genre references, normalizes ё/е, and omits non-existent genre IDs like Исекай',
        () async {
      final adapter = _GenreRefMockAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final ds = AniLibertyAnimeRemoteDataSourceImpl(customDio: dio);

      await ds.syncGenreReferences(force: true);

      // Демографические и виртуальные теги никогда не отправляют f[genres] на AniLibria
      expect(ds.resolveGenreId('Сёнен'), isNull);
      expect(ds.resolveGenreId('Сенен'), isNull);
      expect(ds.resolveGenreId('сэйнэн'), isNull);
      expect(ds.resolveGenreId('Сейнен'), isNull);
      expect(ds.resolveGenreId('Исекай'), isNull);

      // Стандартные жанры из справочника корректно разрешаются в ID
      expect(ds.resolveGenreId('Мистика'), 9);
      expect(ds.resolveGenreId('Психология'), 19);
      expect(ds.resolveGenreId('Фэнтези'), 29);

      await ds.getCatalog(page: 1, genres: 'Мистика');
      final releaseReq = adapter.requests
          .lastWhere((r) => r.path.contains('/catalog/releases'));
      expect(releaseReq.queryParameters['f[genres]'], '9');

      await ds.getCatalog(page: 1, genres: 'Сёнен');
      final shounenReq = adapter.requests
          .lastWhere((r) => r.path.contains('/catalog/releases'));
      expect(shounenReq.queryParameters.containsKey('f[genres]'), isFalse);
    });

    test('CatalogCubit.matchesGenreOrAlias matches demographic tags and keywords', () {
      const isekaiByDesc = AnimeTitle(
        id: 1,
        code: 'isekai-1',
        russianTitle: 'Перерождение',
        englishTitle: 'Reincarnation',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Фэнтези'],
        description: 'Обычный парень попал в другой мир и переродился магом.',
        status: 'released',
      );
      const seinenByTag = AnimeTitle(
        id: 2,
        code: 'seinen-1',
        russianTitle: 'Тёмный триллер',
        englishTitle: 'Dark Thriller',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Сейнен', 'Психологическое'],
        description: '',
        status: 'released',
      );

      expect(CatalogCubit.matchesGenreOrAlias(isekaiByDesc, 'Исекай'), isTrue);
      expect(CatalogCubit.matchesGenreOrAlias(seinenByTag, 'Сэйнэн'), isTrue);
      expect(CatalogCubit.matchesGenreOrAlias(seinenByTag, 'Психология'), isTrue);

      const battleShounen = AnimeTitle(
        id: 3,
        code: 'battle-1',
        russianTitle: 'Боец',
        englishTitle: 'Fighter',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Экшен', 'Боевые искусства'],
        description: '',
        status: 'ongoing',
      );
      expect(CatalogCubit.matchesGenreOrAlias(battleShounen, 'Сёнен'), isTrue);
    });

    test('CatalogCubit never emits CatalogError when local cache has matches for Сёнен',
        () async {
      await CatalogPersistentStore.instance.clear();
      await CatalogPersistentStore.instance.mergeAndPersist([
        const AnimeTitle(
          id: 77,
          code: 'naruto-like',
          russianTitle: 'Хроники Синоби',
          englishTitle: 'Shinobi',
          posterSmall: '',
          posterMedium: '',
          posterOriginal: '',
          genres: ['Экшен', 'Приключения'],
          description: '',
          status: 'released',
        ),
      ]);

      final repo = _FailingCatalogRepository();
      final cubit = CatalogCubit(
        getUpdates: GetUpdates(repo),
        searchTitles: SearchTitles(repo),
      );
      cubit.onCategoryChanged('Сёнен');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(cubit.state, isA<CatalogLoaded>());
      final loaded = cubit.state as CatalogLoaded;
      expect(loaded.filteredTitles.any((t) => t.id == 77), isTrue);

      await cubit.close();
      await CatalogPersistentStore.instance.clear();
    });

    test('getCatalog passes f[types]=MOVIE and anons falls back to IS_ANNOUNCED',
        () async {
      final adapter = _AnonsAndMoviesAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final ds = AniLibertyAnimeRemoteDataSourceImpl(customDio: dio);

      final movies = await ds.getCatalog(
        page: 1,
        types: 'MOVIE',
        sort: 'rating',
      );
      expect(movies, isNotEmpty);
      expect(movies.first.kind, 'MOVIE');
      final movieReq = adapter.requests
          .firstWhere((r) => r.queryParameters['f[types]'] == 'MOVIE');
      expect(movieReq.queryParameters['f[sorting]'], 'RATING_DESC');

      final anons = await ds.getCatalog(page: 1, status: 'anons');
      expect(anons, isNotEmpty);
      expect(
        adapter.requests.any(
          (r) => r.queryParameters['f[publish_statuses]'] == 'IS_IN_PRODUCTION',
        ),
        isTrue,
      );
      expect(
        adapter.requests.any(
          (r) => r.queryParameters['f[publish_statuses]'] == 'IS_ANNOUNCED',
        ),
        isTrue,
      );
    });

    test('CatalogCubit.selectQuickTab never emits CatalogError on failing backend',
        () async {
      final repo = _FailingCatalogRepository();
      final cubit = CatalogCubit(
        getUpdates: GetUpdates(repo),
        searchTitles: SearchTitles(repo),
      );
      cubit.emit(const CatalogLoaded(titles: [], filteredTitles: []));

      for (final tab in const [
        'all',
        'ongoing',
        'popular',
        'released',
        'movies',
        'anons',
      ]) {
        cubit.selectQuickTab(tab);
        await Future.delayed(const Duration(milliseconds: 25));
        expect(cubit.state, isA<CatalogLoaded>());
      }
      await cubit.close();
    });

    testWidgets(
        'CatalogFilterSheet loads live genres sorted alphabetically from AnimeRemoteDataSource',
        (tester) async {
      final adapter = _GenreRefMockAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final ds = AniLibertyAnimeRemoteDataSourceImpl(customDio: dio);
      await tester.runAsync(() => ds.syncGenreReferences(force: true));

      if (getIt.isRegistered<AnimeRemoteDataSource>()) {
        await getIt.unregister<AnimeRemoteDataSource>();
      }
      getIt.registerSingleton<AnimeRemoteDataSource>(ds);

      final repo = _FailingCatalogRepository();
      final cubit = CatalogCubit(
        getUpdates: GetUpdates(repo),
        searchTitles: SearchTitles(repo),
      );
      const state = CatalogLoaded(titles: [], filteredTitles: []);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.cinemaDark,
          home: BlocProvider<CatalogCubit>.value(
            value: cubit,
            child: const Scaffold(
              body: CatalogFilterSheet(currentState: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Жанры из живого ответа (/references/genres) отрендерены в алфавитном порядке
      expect(find.widgetWithText(FilterChip, 'Мистика'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Психология'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Фэнтези'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Школа'), findsOneWidget);
      expect(ds.liveGenres.map((e) => e.name).toList(), [
        'Мистика',
        'Психология',
        'Сэйнэн',
        'Сёнен',
        'Фэнтези',
        'Школа',
      ]);

      await cubit.close();
      await getIt.unregister<AnimeRemoteDataSource>();
    });
  });
}

class _AnonsAndMoviesAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.queryParameters['f[publish_statuses]'] == 'IS_IN_PRODUCTION') {
      return ResponseBody.fromString(
        jsonEncode({'data': []}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'data': [
          {
            'id': 55,
            'alias': 'test-movie',
            'name': {'main': 'Тест Фильм', 'english': 'Test Movie'},
            'type': {'value': 'MOVIE', 'description': 'Фильм'},
            'poster': {'src': 'https://example.com/55.jpg'},
            'year': 2026,
            'genres': [
              {'id': 8, 'name': 'Драма'},
            ],
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

