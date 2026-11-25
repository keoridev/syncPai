import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/network/api_constants.dart';
import 'package:sync_pai/core/network/dio_client.dart';
import 'package:sync_pai/features/catalog/data/datasources/anilibria_remote_datasource.dart';
import 'package:sync_pai/features/catalog/data/datasources/anime_remote_datasource.dart';
import 'package:sync_pai/features/catalog/data/datasources/shikimori_announced_datasource.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';

class _EmptyPrimaryMirrorAdapter implements HttpClientAdapter {
  final List<Uri> requestedUris = [];
  final bool delayResponses;

  _EmptyPrimaryMirrorAdapter({this.delayResponses = false});

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri);
    if (delayResponses) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    final isFallback = options.uri.toString().startsWith(ApiConstants.fallbackBaseUrl);
    if (!isFallback && options.uri.host == 'anilibria.top') {
      return ResponseBody.fromString(
        '',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/plain'],
        },
      );
    }

    if (options.uri.path.contains('/anime/schedule/week')) {
      return ResponseBody.fromString(
        jsonEncode([
          {
            'release': {
              'id': 77,
              'alias': 'test-schedule',
              'name': {'main': 'Schedule Anime', 'english': 'Schedule Anime'},
            },
          }
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.uri.path.contains('/app/search/releases')) {
      return ResponseBody.fromString(
        jsonEncode([
          {
            'id': 101,
            'alias': 'solo-leveling',
            'name': {'main': 'Поднятие уровня', 'english': 'Solo Leveling'},
          }
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.uri.path.contains('/api/graphql')) {
      return ResponseBody.fromString(
        jsonEncode({
          'data': {
            'animes': [
              {
                'id': '555',
                'name': 'Announced Show',
                'russian': 'Анонсированное шоу',
                'kind': 'tv',
                'status': 'anons',
                'season': 'spring_2027',
                'poster': {'originalUrl': '/1.jpg', 'mainUrl': '/1.jpg'},
              }
            ]
          }
        }),
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

class _CountingCatalogRepo implements CatalogRepository {
  int getUpdatesCalls = 0;

  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) =>
      throw UnimplementedError();

  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async {
    getUpdatesCalls++;
    return const [];
  }

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20}) async =>
      const [];
}

void main() {
  test('AnilibriaRemoteDataSourceImpl retries fallback mirror on empty 200 OK body', () async {
    final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseUrl));
    final adapter = _EmptyPrimaryMirrorAdapter();
    dio.httpClientAdapter = adapter;

    final client = DioClient(customDio: dio);
    final ds = AnilibriaRemoteDataSourceImpl(client);

    final results = await ds.searchTitles('Solo Leveling');
    expect(results, hasLength(1));
    expect(results.first.id, 101);
    expect(
      adapter.requestedUris.any((u) => u.toString().startsWith(ApiConstants.fallbackBaseUrl)),
      isTrue,
    );
  });

  test('AnilibriaRemoteDataSourceImpl deduplicates concurrent searchTitles calls', () async {
    final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseUrl));
    final adapter = _EmptyPrimaryMirrorAdapter(delayResponses: true);
    dio.httpClientAdapter = adapter;

    final client = DioClient(customDio: dio);
    final ds = AnilibriaRemoteDataSourceImpl(client);

    final futures = await Future.wait([
      ds.searchTitles('Solo Leveling'),
      ds.searchTitles('Solo Leveling'),
      ds.searchTitles('Solo Leveling'),
    ]);

    expect(futures[0], hasLength(1));
    expect(futures[1], hasLength(1));
    expect(futures[2], hasLength(1));
    // 1 primary (empty) + 1 fallback = 2 total HTTP calls, not 6.
    expect(adapter.requestedUris, hasLength(2));
  });

  test('AniLibertyAnimeRemoteDataSourceImpl deduplicates concurrent getScheduleWeek calls and handles empty primary body', () async {
    final dio = Dio();
    final adapter = _EmptyPrimaryMirrorAdapter(delayResponses: true);
    dio.httpClientAdapter = adapter;

    final ds = AniLibertyAnimeRemoteDataSourceImpl(customDio: dio);

    final results = await Future.wait([
      ds.getScheduleWeek(),
      ds.getScheduleWeek(),
    ]);

    expect(results[0], hasLength(1));
    expect(results[1], hasLength(1));
    expect(
      adapter.requestedUris.where((u) => u.path.contains('/anime/schedule/week')),
      hasLength(2), // 1 primary (empty) + 1 fallback
    );
  });

  test('ShikimoriAnnouncedDataSourceImpl deduplicates concurrent GraphQL requests', () async {
    final dio = Dio();
    final adapter = _EmptyPrimaryMirrorAdapter(delayResponses: true);
    dio.httpClientAdapter = adapter;

    final ds = ShikimoriAnnouncedDataSourceImpl(dio);

    final results = await Future.wait([
      ds.fetchAnnounced(season: 'spring_2027'),
      ds.fetchAnnounced(season: 'spring_2027'),
      ds.fetchAnnounced(season: 'spring_2027'),
    ]);

    expect(results[0], hasLength(1));
    expect(results[1], hasLength(1));
    expect(results[2], hasLength(1));
    expect(adapter.requestedUris, hasLength(1));
  });

  test('CatalogCubit.loadUpdates initializes only once unless refresh is true', () async {
    final repo = _CountingCatalogRepo();
    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );

    await cubit.loadUpdates();
    await cubit.loadUpdates();
    expect(repo.getUpdatesCalls, 1);

    await cubit.loadUpdates(refresh: true);
    expect(repo.getUpdatesCalls, 2);

    await cubit.close();
  });
}

