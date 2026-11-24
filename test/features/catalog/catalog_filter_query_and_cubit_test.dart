import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/catalog/data/datasources/shikimori_announced_datasource.dart';
import 'package:sync_pai/features/catalog/data/services/catalog_persistent_store.dart';
import 'package:sync_pai/features/catalog/data/services/references_store.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_entity.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/catalog_filter.dart';
import 'package:sync_pai/features/catalog/domain/entities/catalog_filter_query.dart';
import 'package:sync_pai/features/catalog/domain/repositories/anime_catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_catalog_usecase.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';

class _FakeLegacyRepo extends Fake implements CatalogRepository {}

class _MockCatalogRepo extends Fake implements AnimeCatalogRepository {
  final List<({CatalogFilter filter, int page, CancelToken? token})> calls = [];
  Future<CatalogPage> Function(CatalogFilter filter, int page, CancelToken? token)?
      handler;

  @override
  Future<CatalogPage> getReleases({
    required CatalogFilter filter,
    required int page,
    int limit = 40,
    CancelToken? cancelToken,
  }) async {
    calls.add((filter: filter, page: page, token: cancelToken));
    if (handler != null) {
      return handler!(filter, page, cancelToken);
    }
    return CatalogPage(items: const [], page: page, hasMore: false);
  }
}

class _FakeShikiAnnouncedDs implements ShikimoriAnnouncedDataSource {
  int calls = 0;
  String? lastSeason;

  @override
  Future<List<AnimeTitle>> fetchAnnounced({
    required String season,
    int limit = 40,
    CancelToken? cancelToken,
  }) async {
    calls++;
    lastSeason = season;
    return [
      const AnimeTitle(
        id: 77701,
        shikimoriId: 77701,
        code: 'shiki_77701',
        russianTitle: 'Анонс Следующего Сезона',
        englishTitle: 'Next Season Anons',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: [],
        description: '',
        status: 'Анонс',
      ),
    ];
  }
}

AnimeEntity _e(int id, String title, {String kind = 'TV'}) => AnimeEntity(
      id: '$id',
      shikimoriId: id,
      titleRu: title,
      titleEn: title,
      kind: kind,
      status: 'ongoing',
      score: 8.5,
      episodesTotal: 12,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CatalogFilterQuery — canonical serialization & signature', () {
    test('signature is deterministic regardless of genres/types order', () {
      const f1 = CatalogFilter(
        sorting: CatalogSorting.ratingDesc,
        genres: [32, 1, 15],
        types: [ReleaseType.movie, ReleaseType.tv],
        seasons: ['Autumn', 'winter'],
        publishStatuses: [PublishStatus.isOngoing],
        yearFrom: 2016,
        yearTo: 2026,
      );
      const f2 = CatalogFilter(
        sorting: CatalogSorting.ratingDesc,
        genres: [15, 32, 1, 15],
        types: [ReleaseType.tv, ReleaseType.movie],
        seasons: ['winter', 'autumn'],
        publishStatuses: [PublishStatus.isOngoing],
        yearFrom: 2016,
        yearTo: 2026,
      );

      expect(f1.signature, equals(f2.signature));
      expect(
        f1.signature,
        'sort=RATING_DESC|gen=1,15,32|type=MOVIE,TV|sea=autumn,winter|age=|pub=IS_ONGOING|prod=|yr=2016-2026|q=',
      );
    });

    test('toQueryParameters omits empty fields, uses CSV String (no List / f[...][]), and formats years range',
        () {
      const filter = CatalogFilter(
        sorting: CatalogSorting.freshAtDesc,
        genres: [32, 1],
        publishStatuses: [PublishStatus.isOngoing],
        yearFrom: 2020,
        yearTo: 2026,
      );

      final qp = filter.toQueryParameters(page: 1, limit: 40);

      expect(qp['page'], 1);
      expect(qp['limit'], 40);
      expect(qp['f[sorting]'], 'FRESH_AT_DESC');
      expect(qp['f[genres]'], '1,32');
      expect(qp['f[publish_statuses]'], 'IS_ONGOING');
      expect(qp['f[years][from_year]'], 2020);
      expect(qp['f[years][to_year]'], 2026);

      // Empty fields must not appear
      expect(qp.containsKey('f[types]'), isFalse);
      expect(qp.containsKey('f[seasons]'), isFalse);
      expect(qp.containsKey('f[age_ratings]'), isFalse);
      expect(qp.containsKey('f[production_statuses]'), isFalse);
      expect(qp.containsKey('f[search]'), isFalse);
      expect(qp.containsKey('f[years]'), isFalse);

      // Never pass List values or f[...][] keys
      for (final entry in qp.entries) {
        expect(entry.key.contains('[]'), isFalse);
        expect(entry.value is List, isFalse);
      }
    });

    test('quickTabSources: movies uses f[types]=MOVIE (not f[genres]), no enum has IS_ANNOUNCED, and signature distinguishes catalog/announced/schedule',
        () {
      // (б) Ни один enum не содержит IS_ANNOUNCED
      expect(
        PublishStatus.values.any((e) => e.apiValue == 'IS_ANNOUNCED'),
        isFalse,
      );
      expect(
        ProductionStatus.values.any((e) => e.apiValue == 'IS_ANNOUNCED'),
        isFalse,
      );

      // (в) Фильмы => f[types]=MOVIE, а не f[genres]
      final moviesSource =
          CatalogCubit.quickTabSources['movies'] as AnilibriaCatalogSource;
      final moviesQp = moviesSource.filter.toQueryParameters(page: 1, limit: 40);
      expect(moviesQp['f[types]'], 'MOVIE');
      expect(moviesQp.containsKey('f[genres]'), isFalse);

      // (д) signature различает catalog / announced / schedule
      final catSig = const AnilibriaCatalogSource(CatalogFilter()).signature;
      final annSig = const ShikimoriAnnouncedSource('spring_2027').signature;
      final schSig = const AniLibriaScheduleSource().signature;
      expect(catSig.startsWith('catalog|'), isTrue);
      expect(annSig.startsWith('announced|'), isTrue);
      expect(schSig.startsWith('schedule|'), isTrue);
      expect({catSig, annSig, schSig}.length, 3);
    });

    test('runtime-guard throws StateError on invalid value against ReferencesStore',
        () {
      ReferencesStore.instance.resetForTest();
      expect(
        () => ReferencesStore.instance.assertValid('publish_statuses', 'IS_ANNOUNCED'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => ReferencesStore.instance.assertValid('types', 'INVALID_TYPE'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => ReferencesStore.instance.assertValid('publish_statuses', 'IS_ONGOING'),
        returnsNormally,
      );
    });
  });

  group('CatalogCubit.load — cancelation, dedup & sequential pagination', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('syncpai_filter_cubit_');
      CatalogPersistentStore.instance
          .setTestFile(File('${tempDir.path}/index.json'));
      await CatalogPersistentStore.instance.init();
    });

    tearDown(() async {
      CatalogPersistentStore.instance.setTestFile(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('switching tab cancels previous request token and ignores late response',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = _MockCatalogRepo();
      final slowOngoing = Completer<CatalogPage>();

      repo.handler = (filter, page, token) async {
        if (filter.publishStatuses.contains(PublishStatus.isOngoing)) {
          return slowOngoing.future;
        }
        return CatalogPage(
          items: [_e(500, 'Фильм 1', kind: 'MOVIE')],
          page: page,
          hasMore: false,
        );
      };

      final cubit = CatalogCubit(
        getUpdates: GetUpdates(_FakeLegacyRepo()),
        searchTitles: SearchTitles(_FakeLegacyRepo()),
        prefs: prefs,
        getCatalogUseCase: GetCatalogUseCase(repo),
      );
      addTearDown(cubit.close);

      final ongoingFilter = (CatalogCubit.quickTabSources['ongoing']
              as AnilibriaCatalogSource)
          .filter;
      final moviesFilter = (CatalogCubit.quickTabSources['movies']
              as AnilibriaCatalogSource)
          .filter;

      unawaited(cubit.load(ongoingFilter, page: 1, refresh: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final ongoingToken = repo.calls.first.token!;
      expect(ongoingToken.isCancelled, isFalse);

      await cubit.load(moviesFilter, page: 1, refresh: true);
      expect(ongoingToken.isCancelled, isTrue);

      slowOngoing.complete(
        CatalogPage(items: [_e(999, 'Поздний онгоинг')], page: 1, hasMore: true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = cubit.state as CatalogLoaded;
      expect(
        state.activeFilterKey,
        AnilibriaCatalogSource(moviesFilter).signature,
      );
      expect(state.titles.map((e) => e.id).toList(), [500]);
    });

    test('deduplicates concurrent in-flight page=2 calls', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = _MockCatalogRepo();
      final page2Completer = Completer<CatalogPage>();

      repo.handler = (filter, page, token) async {
        if (page == 1) {
          return CatalogPage(
            items: List.generate(12, (i) => _e(i + 1, 'Item $i')),
            page: 1,
            hasMore: true,
          );
        }
        return page2Completer.future;
      };

      final cubit = CatalogCubit(
        getUpdates: GetUpdates(_FakeLegacyRepo()),
        searchTitles: SearchTitles(_FakeLegacyRepo()),
        prefs: prefs,
        getCatalogUseCase: GetCatalogUseCase(repo),
      );
      addTearDown(cubit.close);

      final allFilter = (CatalogCubit.quickTabSources['all']
              as AnilibriaCatalogSource)
          .filter;
      await cubit.load(allFilter, page: 1, refresh: true);

      final f1 = cubit.load(allFilter, page: 2);
      final f2 = cubit.load(allFilter, page: 2);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repo.calls.where((c) => c.page == 2).length, 1);

      page2Completer.complete(
        CatalogPage(items: [_e(99, 'Page 2 Item')], page: 2, hasMore: false),
      );
      await Future.wait([f1, f2]);

      final loaded = cubit.state as CatalogLoaded;
      expect(loaded.currentPage, 2);
      expect(loaded.titles.any((e) => e.id == 99), isTrue);
    });

    test('Анонсы routes to ShikimoriAnnouncedDataSource, never calls /anime/catalog/releases, and sets hasReachedMax',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = _MockCatalogRepo();
      final shikiDs = _FakeShikiAnnouncedDs();

      final cubit = CatalogCubit(
        getUpdates: GetUpdates(_FakeLegacyRepo()),
        searchTitles: SearchTitles(_FakeLegacyRepo()),
        prefs: prefs,
        getCatalogUseCase: GetCatalogUseCase(repo),
        shikimoriAnnouncedDataSource: shikiDs,
      );
      addTearDown(cubit.close);

      cubit.selectQuickTab('anons');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(shikiDs.calls, 1);
      expect(repo.calls, isEmpty);
      final loaded = cubit.state as CatalogLoaded;
      expect(loaded.activeFilterKey.startsWith('announced|'), isTrue);
      expect(loaded.hasReachedMax, isTrue);
      expect(loaded.titles.first.status, 'Анонс');
    });
  });
}

