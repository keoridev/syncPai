import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/manga/data/datasources/mangadex_datasource.dart';
import 'package:sync_pai/features/manga/domain/entities/manga_bridge.dart';

class _StubCatalogRepo implements CatalogRepository {
  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) =>
      throw UnimplementedError();

  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async =>
      const [];

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int page = 1, int limit = 20}) async =>
      const [];
}

class _AltTitleAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({
        'data': [
          {
            'id': 'solo-1',
            'attributes': {
              'title': {'en': 'Na Honjaman Level-Up'},
              'altTitles': [
                {'ko': '나 혼자만 레벨업'},
                {'ru': 'Поднятие уровня в одиночку'},
              ],
              'originalLanguage': 'ko',
              'availableTranslatedLanguages': ['ru', 'en'],
            },
            'relationships': [],
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _FakeMangaDex extends MangaDexDataSource {
  final List<int> requestedOffsets = [];
  final List<int> requestedLimits = [];
  final List<String> searchedQueries = [];

  @override
  Future<List<MangaDexManga>> browseManga({
    String? originalLanguage,
    String? availableTranslatedLanguage,
    String? status,
    String order = 'followedCount',
    int limit = 40,
    int offset = 0,
    String? query,
  }) async {
    requestedLimits.add(limit);
    requestedOffsets.add(offset);
    return List.generate(
      limit,
      (i) => MangaDexManga(
        id: 'm-${offset + i}',
        title: 'Манга ${offset + i}',
        originalTitle: 'Manga ${offset + i}',
        coverUrl: '',
        originalLanguage: 'ko',
        availableTranslatedLanguages: const ['ru'],
      ),
    );
  }

  @override
  Future<List<MangaDexManga>> searchManga(
    String title, {
    int limit = 40,
    int offset = 0,
  }) async {
    searchedQueries.add(title);
    if (title == 'Поднятие уровня') {
      return const [];
    }
    return [
      MangaDexManga(
        id: 'sl-1',
        title: 'Поднятие уровня в одиночку',
        originalTitle: title,
        coverUrl: '',
        originalLanguage: 'ko',
        availableTranslatedLanguages: const ['ru'],
      ),
    ];
  }
}

class _FakeShikimori implements ShikimoriRemoteDataSource {
  final List<String> searchedQueries = [];

  @override
  Future<List<({String russian, String english})>> searchMangas(
    String query, {
    int limit = 8,
  }) async {
    searchedQueries.add(query);
    return [(russian: 'Поднятие уровня в одиночку', english: 'Solo Leveling')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('MangaDexDataSource resolves altTitles[ru] over title[en] and preserves originalTitle', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.mangadex.org'));
    dio.httpClientAdapter = _AltTitleAdapter();
    final ds = MangaDexDataSource(customDio: dio);

    final items = await ds.browseManga(limit: 40, offset: 0);
    expect(items.length, 1);
    expect(items.first.title, 'Поднятие уровня в одиночку');
    expect(items.first.originalTitle, 'Na Honjaman Level-Up');
  });

  test('CatalogCubit paginates MangaDex with limit=40 and incremental offset', () async {
    final prefs = await SharedPreferences.getInstance();
    final fakeMd = _FakeMangaDex();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(_StubCatalogRepo()),
      searchTitles: SearchTitles(_StubCatalogRepo()),
      prefs: prefs,
      mangaDexDataSource: fakeMd,
    );

    await cubit.loadUpdates();
    await cubit.loadMangaCatalog();

    final st1 = cubit.state as CatalogLoaded;
    expect(st1.mangaItems.length, 40);
    expect(st1.hasMoreManga, isTrue);
    expect(fakeMd.requestedLimits, [40]);
    expect(fakeMd.requestedOffsets, [0]);

    await cubit.loadNextMangaPage();
    final st2 = cubit.state as CatalogLoaded;
    expect(st2.mangaItems.length, 80);
    expect(fakeMd.requestedOffsets, [0, 40]);

    await cubit.close();
  });

  test('CatalogCubit Cyrillic manga search falls back to Shikimori to resolve English title', () async {
    final prefs = await SharedPreferences.getInstance();
    final fakeMd = _FakeMangaDex();
    final fakeShiki = _FakeShikimori();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(_StubCatalogRepo()),
      searchTitles: SearchTitles(_StubCatalogRepo()),
      prefs: prefs,
      mangaDexDataSource: fakeMd,
      shikimoriRemoteDataSource: fakeShiki,
    );

    await cubit.loadUpdates();
    await cubit.searchMangaCatalog('Поднятие уровня');

    final st = cubit.state as CatalogLoaded;
    expect(fakeShiki.searchedQueries, ['Поднятие уровня']);
    expect(fakeMd.searchedQueries, ['Поднятие уровня', 'Solo Leveling']);
    expect(st.mangaItems.length, 1);
    expect(st.mangaItems.first.title, 'Поднятие уровня в одиночку');

    await cubit.close();
  });
}

