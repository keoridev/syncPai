import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/catalog/data/services/catalog_persistent_store.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_entity.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/domain/repositories/anime_catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_catalog_usecase.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';

class _FakeCatalogRepo extends Fake implements CatalogRepository {}

class _RecordedCall {
  final int page;
  final String? sort;
  final String? status;
  final String? types;
  final String? genres;

  const _RecordedCall({
    required this.page,
    this.sort,
    this.status,
    this.types,
    this.genres,
  });
}

class _FakeAnimeCatalogRepo extends Fake implements AnimeCatalogRepository {
  final List<_RecordedCall> calls = [];
  Future<List<AnimeEntity>> Function(_RecordedCall call)? handler;

  @override
  Future<List<AnimeEntity>> getCatalog({
    int page = 1,
    int limit = 20,
    String? genres,
    String? sort,
    String? status,
    String? types,
    String? year,
    CancelToken? cancelToken,
  }) async {
    final call = _RecordedCall(
      page: page,
      sort: sort,
      status: status,
      types: types,
      genres: genres,
    );
    calls.add(call);
    if (handler != null) {
      return handler!(call);
    }
    return const [];
  }
}

AnimeEntity _entity({
  required int id,
  required String title,
  String? kind = 'TV',
  String status = 'ongoing',
  double score = 8.0,
  int episodesTotal = 12,
  List<String> genres = const ['Экшен'],
}) {
  return AnimeEntity(
    id: '$id',
    shikimoriId: id,
    titleRu: title,
    titleEn: title,
    kind: kind,
    status: status,
    score: score,
    episodesTotal: episodesTotal,
    genres: genres,
  );
}

AnimeTitle _title({
  required int id,
  required String title,
  String? kind = 'TV',
  String status = 'ongoing',
  double score = 8.0,
  int episodesTotal = 12,
  List<String> genres = const ['Экшен'],
  List<EpisodeItem> episodes = const [EpisodeItem(episode: 1)],
}) {
  return AnimeTitle(
    id: id,
    code: 'code-$id',
    russianTitle: title,
    englishTitle: title,
    posterSmall: '',
    posterMedium: '',
    posterOriginal: '',
    kind: kind,
    status: status,
    score: score,
    episodesTotal: episodesTotal,
    genres: genres,
    description: '',
    episodes: episodes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CatalogPersistentStore strict queryLocal', () {
    late Directory tempDir;
    late File indexFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('syncpai_tab_iso_');
      indexFile = File('${tempDir.path}/index.json');
      CatalogPersistentStore.instance.setTestFile(indexFile);
      await CatalogPersistentStore.instance.init();
    });

    tearDown(() async {
      CatalogPersistentStore.instance.setTestFile(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('filters MOVIE, ongoing, released, anons, genres and rating strictly',
        () async {
      await CatalogPersistentStore.instance.mergeAndPersist([
        _title(id: 1, title: 'TV Ongoing', kind: 'TV', status: 'ongoing', score: 7.5, genres: const ['Экшен']),
        _title(id: 2, title: 'Movie Released', kind: 'MOVIE', status: 'released', score: 9.2, genres: const ['Драма']),
        _title(id: 3, title: 'Unknown Kind TV', kind: null, status: 'released', score: 8.1, genres: const ['Экшен']),
        _title(id: 4, title: 'Anons Title', kind: 'TV', status: 'anons', score: 0.0, episodesTotal: 0, episodes: const [], genres: const ['Комедия']),
      ]);

      final movies = CatalogPersistentStore.instance.queryLocal(type: 'MOVIE');
      expect(movies.map((e) => e.id).toList(), [2]);

      final ongoing = CatalogPersistentStore.instance.queryLocal(status: 'ongoing');
      expect(ongoing.map((e) => e.id).toList(), [1]);

      final released = CatalogPersistentStore.instance.queryLocal(status: 'released');
      expect(released.map((e) => e.id).toList(), [2, 3]);

      final anons = CatalogPersistentStore.instance.queryLocal(status: 'anons');
      expect(anons.map((e) => e.id).toList(), [4]);

      final popular = CatalogPersistentStore.instance.queryLocal(sort: 'rating');
      expect(popular.first.id, 2);

      final actionOnly = CatalogPersistentStore.instance.queryLocal(genre: 'Экшен');
      expect(actionOnly.map((e) => e.id).toList(), [1, 3]);
    });
  });

  group('CatalogCubit per-tab isolation & lazy loading', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('syncpai_cubit_iso_');
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

    test('cold start fires only 1 request and Фильмы never shows TV items from Все',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final fakeCatalogRepo = _FakeAnimeCatalogRepo();
      fakeCatalogRepo.handler = (call) async {
        if (call.types == 'MOVIE') {
          return [
            _entity(id: 201, title: 'Твоё имя', kind: 'MOVIE', status: 'released', score: 9.0),
          ];
        }
        return [
          _entity(id: 101, title: 'TV Сериал 1', kind: 'TV', status: 'ongoing', score: 8.0),
          _entity(id: 102, title: 'TV Без типа', kind: null, status: 'ongoing', score: 7.5),
        ];
      };

      final fakeLegacy = _FakeCatalogRepo();
      final cubit = CatalogCubit(
        getUpdates: GetUpdates(fakeLegacy),
        searchTitles: SearchTitles(fakeLegacy),
        prefs: prefs,
        getCatalogUseCase: GetCatalogUseCase(fakeCatalogRepo),
      );
      addTearDown(cubit.close);

      await cubit.loadUpdates();
      expect(fakeCatalogRepo.calls.length, 1);
      expect(fakeCatalogRepo.calls.first.sort, CatalogSort.updates.name);
      expect(fakeCatalogRepo.calls.first.types, isNull);
      expect(fakeCatalogRepo.calls.first.status, isNull);

      final allState = cubit.state as CatalogLoaded;
      expect(allState.filteredTitles.map((e) => e.id).toList(), [101, 102]);

      cubit.selectQuickTab('movies');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final moviesState = cubit.state as CatalogLoaded;
      expect(moviesState.typeFilter, 'MOVIE');
      expect(moviesState.filteredTitles.map((e) => e.id).toList(), [201]);
      expect(moviesState.filteredTitles.any((e) => e.id == 101 || e.id == 102), isFalse);

      // Switching back to 'movies' uses in-memory tab cache without extra API call
      final callsBeforeReturn = fakeCatalogRepo.calls.length;
      cubit.selectQuickTab('all');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cubit.selectQuickTab('movies');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fakeCatalogRepo.calls.length, callsBeforeReturn);
    });

    test('stale response from previous tab cannot overwrite active tab',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final ongoingCompleter = Completer<List<AnimeEntity>>();
      final fakeCatalogRepo = _FakeAnimeCatalogRepo();
      fakeCatalogRepo.handler = (call) async {
        if (call.status == 'ongoing') {
          return ongoingCompleter.future;
        }
        if (call.types == 'MOVIE') {
          return [
            _entity(id: 301, title: 'Унесённые призраками', kind: 'MOVIE', status: 'released', score: 9.3),
          ];
        }
        return [
          _entity(id: 1, title: 'Все TV', kind: 'TV', status: 'ongoing'),
        ];
      };

      final fakeLegacy = _FakeCatalogRepo();
      final cubit = CatalogCubit(
        getUpdates: GetUpdates(fakeLegacy),
        searchTitles: SearchTitles(fakeLegacy),
        prefs: prefs,
        getCatalogUseCase: GetCatalogUseCase(fakeCatalogRepo),
      );
      addTearDown(cubit.close);

      await cubit.loadUpdates();

      // Tap Онгоинги (slow response), then immediately switch to Фильмы
      cubit.selectQuickTab('ongoing');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cubit.selectQuickTab('movies');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Resolve slow Онгоинги after Фильмы is already active
      ongoingCompleter.complete([
        _entity(id: 999, title: 'Поздний Онгоинг', kind: 'TV', status: 'ongoing'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final finalState = cubit.state as CatalogLoaded;
      expect(finalState.typeFilter, 'MOVIE');
      expect(finalState.filteredTitles.map((e) => e.id).toList(), [301]);
    });
  });
}

