import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_state.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/anime_details/domain/entities/user_lists_stats.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/anime_media_info_section.dart';
import 'package:sync_pai/features/anime_lists/data/datasources/anixart_backup_parser.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/anime_lists/domain/repositories/anime_list_repository.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/catalog/presentation/screens/catalog_screen.dart';
import 'package:sync_pai/features/catalog/presentation/widgets/anime_poster_card.dart';

class _StubCatalogRepo implements CatalogRepository {
  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async =>
      const [];

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20}) async =>
      const [];

  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) async =>
      throw UnimplementedError();
}

class _InMemoryListRepo implements AnimeListRepository {
  final List<UserAnimeEntry> _entries;
  _InMemoryListRepo([List<UserAnimeEntry>? seed])
      : _entries = List.of(seed ?? const []);

  @override
  Future<List<UserAnimeEntry>> getAllEntries() async => List.of(_entries);

  @override
  Future<UserAnimeEntry?> getEntry(int animeId) async {
    for (final e in _entries) {
      if (e.animeId == animeId) return e;
    }
    return null;
  }

  @override
  Future<void> upsertEntry(UserAnimeEntry entry) async {
    _entries.removeWhere((e) => e.animeId == entry.animeId);
    _entries.insert(0, entry);
  }

  @override
  Future<void> upsertEntries(List<UserAnimeEntry> entries) async {
    for (final e in entries) {
      await upsertEntry(e);
    }
  }

  @override
  Future<void> removeEntry(int animeId) async {
    _entries.removeWhere((e) => e.animeId == animeId);
  }

  @override
  Future<void> clearAllEntries({String? userId}) async {
    _entries.clear();
  }

  @override
  Future<void> updatePosterUrl(int animeId, String posterUrl) async {}

  @override
  Future<void> batchChangeStatus(
      List<int> animeIds, AnimeListStatus newStatus) async {}

  @override
  Future<void> batchDelete(List<int> animeIds) async {}

  @override
  Future<void> syncWithCloud({required String userId}) async {}

  @override
  Future<AnixartImportResult> importAnixartByLoginOrId(
    String loginOrId, {
    required String userId,
  }) =>
      throw UnimplementedError();

  @override
  Future<AnixartImportResult> importAnixartBackup(
    String rawJson, {
    required String userId,
  }) =>
      throw UnimplementedError();

  @override
  Future<AnixartImportResult> importAnixartCsvWithShikimori(
    String rawCsv, {
    required String userId,
    AnimeListStatus defaultStatus = AnimeListStatus.planned,
    AnimeListStatus? overrideStatus,
    void Function(int current, int total, String currentTitle)? onProgress,
  }) =>
      throw UnimplementedError();
}

class _ShikiStatsMockAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object payload;
    if (options.uri.path.endsWith('/graphql')) {
      // GraphQL возвращает пустой statusesStats -> должен сработать REST fallback
      payload = {
        'data': {
          'animes': [
            {
              'id': '100',
              'score': 8.9,
              'statusesStats': [],
              'scoresStats': [],
              'screenshots': [],
              'videos': [],
            },
          ],
        },
      };
    } else if (options.uri.path.endsWith('/animes/100')) {
      payload = {
        'id': 100,
        'rates_statuses_stats': [
          {'name': 'Смотрю', 'value': 150},
          {'name': 'Просмотрено', 'value': 1200},
          {'name': 'Запланировано', 'value': 300},
          {'name': 'Брошено', 'value': 20},
        ],
      };
    } else if (options.uri.path.endsWith('/franchise')) {
      payload = {'nodes': [], 'links': []};
    } else {
      payload = [];
    }
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

AnimeTitle _title(int id, String name, {List<String> genres = const ['Драма'], int? latestEp}) {
  return AnimeTitle(
    id: id,
    code: 't_$id',
    russianTitle: name,
    englishTitle: name,
    description: 'Описание $name',
    status: 'Онгоинг',
    posterSmall: '',
    posterMedium: '',
    posterOriginal: '',
    genres: genres,
    latestEpisode: latestEp,
    year: 2026,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    MascotCompanionService.instance.resetForTest();
  });

  tearDown(() async {
    MascotCompanionService.instance.resetForTest();
    await getIt.reset();
  });

  test('CatalogCubit.mergePreservingVisibleOrder preserves top order and appends new items below',
      () {
    final visible = [
      _title(1, 'Первый', latestEp: 3),
      _title(2, 'Второй', latestEp: 5),
    ];
    final incoming = [
      _title(99, 'Новый вверху с API', latestEp: 1),
      _title(2, 'Второй', latestEp: 6), // обновлена серия на месте
      _title(1, 'Первый', latestEp: 4), // обновлена серия на месте
      _title(100, 'Ещё один новый'),
    ];

    final merged = CatalogCubit.mergePreservingVisibleOrder(
      currentVisible: visible,
      incoming: incoming,
    );

    expect(merged.map((e) => e.id).toList(), [1, 2, 99, 100]);
    expect(merged[0].latestEpisode, 4);
    expect(merged[1].latestEpisode, 6);
  });

  testWidgets('CatalogScreen shows borderless tabs, open Для тебя view and 3-min Pai-chan helper',
      (tester) async {
    final repo = _StubCatalogRepo();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );
    final listRepo = _InMemoryListRepo([
      UserAnimeEntry(
        id: 'u_1',
        userId: 'u1',
        animeId: 1,
        titleRu: 'Фрирен',
        status: AnimeListStatus.completed,
        updatedAt: DateTime(2026, 11, 22),
      ),
    ]);
    final listCubit = AnimeListCubit(repository: listRepo);
    await listCubit.loadLists();
    getIt.registerSingleton<AnimeListCubit>(listCubit);

    final items = List.generate(
      14,
      (i) => _title(i + 1, 'Тайтл ${i + 1}', genres: ['Драма', 'Фэнтези']),
    );
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    cubit.emit(CatalogLoaded(titles: items, filteredTitles: items));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const CatalogScreen(),
        ),
      ),
    );
    await tester.pump();

    // Наличие вкладки «Для тебя» и всех 7 вкладок
    expect(find.byKey(const ValueKey('catalog_quick_tab_for_you')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog_quick_tab_all')), findsOneWidget);
    // На карточке #1 в сетке отображается статус «Просмотрено»
    expect(find.text('Просмотрено'), findsWidgets);

    // 3 минуты сёрфинга в каталоге -> Пай-тян предлагает подборку
    await tester.pump(const Duration(minutes: 3));
    final reaction = MascotCompanionService.instance.currentReaction;
    expect(reaction, isNotNull);
    expect(reaction!.expression, MascotExpression.curiousSearch);
    expect(reaction.actionLabel, 'Открыть подборки');
    expect(MascotCompanionService.instance.indecisionHelperShownThisSession, isTrue);

    // Нажатие action открывает секцию «Для тебя»
    reaction.onAction?.call();
    await tester.pump();
    expect(find.byKey(const ValueKey('catalog_open_for_you_view')), findsOneWidget);

    // Открытие плеера сбрасывает/не допускает повторный таймер
    MascotCompanionService.instance.setPlayerActive(true);
    expect(MascotCompanionService.instance.currentReaction, isNull);

    await cubit.close();
    await listCubit.close();
  });

  testWidgets('AnimePosterCard renders distinct list status pills for search and grids',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 280,
            child: Row(
              children: [
                Expanded(
                  child: AnimePosterCard(
                    title: _title(10, 'Watched Show'),
                    userListStatus: AnimeListStatus.completed,
                    onTap: () {},
                  ),
                ),
                Expanded(
                  child: AnimePosterCard(
                    title: _title(11, 'Watching Show'),
                    userListStatus: AnimeListStatus.watching,
                    onTap: () {},
                  ),
                ),
                Expanded(
                  child: AnimePosterCard(
                    title: _title(12, 'Planned Show'),
                    userListStatus: AnimeListStatus.planned,
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Просмотрено'), findsOneWidget);
    expect(find.text('Смотрю'), findsOneWidget);
    expect(find.text('В планах'), findsOneWidget);
  });

  test('ShikimoriRemoteDataSourceImpl merges Supabase user_anime_lists with Shikimori REST stats',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://shikimori.one/api'));
    dio.httpClientAdapter = _ShikiStatsMockAdapter();

    final ds = ShikimoriRemoteDataSourceImpl(
      customDio: dio,
      minRequestInterval: Duration.zero,
      retry429Delay: Duration.zero,
      communityStatsLoader: (_, __) async => const UserListsStats(
        watching: 5,
        completed: 12,
        planned: 3,
      ),
    );

    const title = AnimeTitle(
      id: 777,
      code: 'old_classic',
      russianTitle: 'Классика',
      englishTitle: 'Old Classic',
      description: '',
      status: 'Завершён',
      genres: ['Драма'],
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      shikimoriId: 100,
    );

    final res = await ds.getReviewsAndRatings(title);
    expect(res.userStats.watching, 155);
    expect(res.userStats.completed, 1212);
    expect(res.userStats.planned, 303);
    expect(res.userStats.dropped, 20);
  });

  testWidgets('AnimeMediaInfoSection hides user lists block when total == 0 and shows when > 0',
      (tester) async {
    final emptyTitle = _title(55, 'Zero Stats');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimeMediaInfoSection(
              title: emptyTitle,
              userStats: const UserListsStats(),
              isLoadingStats: false,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('user_lists_fresh_fallback')), findsNothing);
    expect(find.byKey(const ValueKey('user_lists_data')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimeMediaInfoSection(
              title: emptyTitle,
              userStats: const UserListsStats(watching: 10, completed: 40),
              isLoadingStats: false,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('user_lists_data')), findsOneWidget);
  });

  test('AnimeListCubit does not duplicate Pai-chan toast on background sync or unchanged completed status',
      () async {
    final seed = [
      UserAnimeEntry(
        id: 'e1',
        userId: 'u1',
        animeId: 42,
        titleRu: 'Стальной алхимик',
        status: AnimeListStatus.completed,
        updatedAt: DateTime(2026, 11, 20),
      ),
    ];
    final cubit = AnimeListCubit(repository: _InMemoryListRepo(seed));
    await cubit.loadLists();
    MascotCompanionService.instance.resetForTest();

    // 1. Фоновая синхронизация при пересмотре завершённого тайтла -> без тоста
    await cubit.setAnimeStatus(
      animeId: 42,
      titleRu: 'Стальной алхимик',
      status: AnimeListStatus.completed,
      lastEpisode: 3,
      isUserInitiated: false,
    );
    expect(MascotCompanionService.instance.currentReaction, isNull);

    // 2. Повторный клик на тот же статус (previousStatus == newStatus) -> без тоста
    await cubit.setAnimeStatus(
      animeId: 42,
      titleRu: 'Стальной алхимик',
      status: AnimeListStatus.completed,
      isUserInitiated: true,
    );
    expect(MascotCompanionService.instance.currentReaction, isNull);

    // 3. Явное добавление нового статуса пользователем (planned -> watching) -> тост появляется
    await cubit.setAnimeStatus(
      animeId: 42,
      titleRu: 'Стальной алхимик',
      status: AnimeListStatus.watching,
      isUserInitiated: true,
    );
    expect(MascotCompanionService.instance.currentReaction, isNotNull);
    expect(
      MascotCompanionService.instance.currentReaction!.message,
      contains('Стальной алхимик'),
    );

    await cubit.close();
  });
}

