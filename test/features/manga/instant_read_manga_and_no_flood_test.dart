import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/data/datasources/mangaupdates_datasource.dart';
import 'package:sync_pai/features/manga/data/services/anime_manga_bridge_service.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';

class _SlowMangaUpdates extends MangaUpdatesDataSource {
  @override
  Future<int?> getAnimeEndChapter(String title) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return 42;
  }
}

class _AdaptedShikimori implements ShikimoriRemoteDataSource {
  final bool hasAdaptation;
  _AdaptedShikimori({this.hasAdaptation = true});

  @override
  Future<AdaptedMangaInfo?> getAdaptedManga(int shikimoriAnimeId) async {
    if (!hasAdaptation) return null;
    return const AdaptedMangaInfo(
      shikimoriMangaId: 99,
      russianTitle: 'Поднятие уровня',
      englishTitle: 'Solo Leveling',
      coverUrl: '',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FastMangaDex extends MangaDexDataSource {
  @override
  Future<List<MangaDexManga>> searchManga(
    String title, {
    int limit = 40,
    int offset = 0,
  }) async {
    return const [
      MangaDexManga(
        id: 'md-fast-1',
        title: 'Поднятие уровня',
        originalTitle: 'Solo Leveling',
        coverUrl: '',
        originalLanguage: 'ko',
      ),
    ];
  }
}

class _CountingCatalogRepo implements CatalogRepository {
  final List<int> requestedPages = [];

  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) =>
      throw UnimplementedError();

  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async {
    requestedPages.add(page);
    return const [];
  }

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int page = 1, int limit = 20}) async =>
      const [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MascotCompanionService.instance.resetForTest();
  });

  tearDown(() {
    MascotCompanionService.instance.resetForTest();
  });

  test('AnimeMangaBridgeService resolves MangaDex immediately without waiting on MangaUpdates', () async {
    AnimeMangaBridge? backgroundUpdated;
    final bridgeService = AnimeMangaBridgeService.forTest(
      shikimoriDataSource: _AdaptedShikimori(hasAdaptation: true),
      mangaUpdatesDataSource: _SlowMangaUpdates(),
      mangaDexDataSource: _FastMangaDex(),
    );

    const anime = AnimeTitle(
      id: 7771,
      code: 'sl',
      russianTitle: 'Поднятие уровня',
      englishTitle: 'Solo Leveling',
      shikimoriId: 52299,
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: [],
      description: '',
      status: '',
    );

    final sw = Stopwatch()..start();
    final bridge = await bridgeService.resolveForAnime(
      anime,
      onChapterOffsetUpdated: (updated) => backgroundUpdated = updated,
    );
    sw.stop();

    expect(bridge, isNotNull);
    expect(bridge!.mangaDexId, 'md-fast-1');
    expect(bridge.mangaUpdatesEndChapter, isNull);
    expect(sw.elapsedMilliseconds, lessThan(200));

    // Wait for background MangaUpdates resolution
    await Future.delayed(const Duration(milliseconds: 450));
    expect(backgroundUpdated?.continueFromChapter, 43);
  });

  test('AnimeMangaBridgeService marks Anime Original and MascotCompanionService notifies user', () async {
    final bridgeService = AnimeMangaBridgeService.forTest(
      shikimoriDataSource: _AdaptedShikimori(hasAdaptation: false),
      mangaUpdatesDataSource: _SlowMangaUpdates(),
      mangaDexDataSource: _FastMangaDex(),
    );

    const anime = AnimeTitle(
      id: 8882,
      code: 'orig',
      russianTitle: 'Оригинал',
      englishTitle: 'Original Anime',
      shikimoriId: 12345,
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: [],
      description: '',
      status: '',
    );

    final bridge = await bridgeService.resolveForAnime(anime);
    expect(bridge, isNull);
    expect(bridgeService.isConfirmedOriginal(8882), isTrue);

    MascotCompanionService.instance.notifyAnimeOriginalNoManga();
    expect(
      MascotCompanionService.instance.currentReaction?.message,
      'У этого аниме нет манги — это оригинальный сюжет.',
    );
  });

  test('CatalogCubit startup loads only page=1 and foreground screen pauses prefetch', () async {
    final repo = _CountingCatalogRepo();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );

    await cubit.loadUpdates();
    expect(repo.requestedPages, [1]);

    CatalogCubit.pushForegroundScreen();
    expect(CatalogCubit.isBackgroundPrefetchPaused, isTrue);
    CatalogCubit.popForegroundScreen();
    expect(CatalogCubit.isBackgroundPrefetchPaused, isFalse);

    await cubit.close();
  });
}

