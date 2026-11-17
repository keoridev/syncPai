import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/network/dio_client.dart';
import 'package:sync_pai/features/anime_details/data/datasources/jikan_remote_datasource.dart';
import 'package:sync_pai/features/catalog/data/datasources/anilibria_remote_datasource.dart';
import 'package:sync_pai/features/catalog/data/datasources/anime_remote_datasource.dart';

class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final ResponseBody Function(RequestOptions options) responder;

  _FakeAdapter(this.responder);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }
}

void main() {
  test('AniLibriaRemoteDataSourceImpl strips search: prefix and avoids 404 release calls',
      () async {
    final dio = Dio();
    final adapter = _FakeAdapter((options) {
      if (options.path.contains('search/releases')) {
        return ResponseBody.fromString(
          '[{"id": 9741, "alias": "atri-my-dear-moments", "name": {"main": "Атри: Мои дорогие моменты", "english": "ATRI: My Dear Moments"}}]',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          },
        );
      }
      return ResponseBody.fromString('{"error": "not found"}', 404);
    });
    dio.httpClientAdapter = adapter;

    final ds = AnilibriaRemoteDataSourceImpl(DioClient(customDio: dio));
    final dto = await ds.getTitleDetails(
      id: 53128,
      code: 'search:Атри: Мои дорогие моменты',
    );

    expect(dto.id, 9741);
    expect(
      adapter.requests.any((r) => r.path.contains('/releases/search:')),
      isFalse,
    );
    expect(
      adapter.requests.any((r) => r.path.contains('/releases/53128')),
      isFalse,
    );
    expect(
      adapter.requests.first.queryParameters['query'],
      'Атри: Мои дорогие моменты',
    );
  });

  test('AnimeRemoteDataSourceImpl.getPlayerLinks skips 0/search: release call and resolves directly',
      () async {
    final dio = Dio();
    final adapter = _FakeAdapter((options) {
      if (options.path.contains('app/search/releases')) {
        return ResponseBody.fromString(
          '[{"id": 9741, "alias": "atri", "name": {"main": "Атри"}}]',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          },
        );
      }
      if (options.path.endsWith('/anime/releases/9741')) {
        return ResponseBody.fromString(
          '{"id": 9741, "episodes": [{"ordinal": 1, "hls_1080": "https://cdn.example/1.m3u8"}]}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          },
        );
      }
      return ResponseBody.fromString('{"error": "unexpected 404"}', 404);
    });
    dio.httpClientAdapter = adapter;

    final ds = AniLibertyAnimeRemoteDataSourceImpl(customDio: dio);
    final player = await ds.getPlayerLinks(
      0,
      title: 'search:Атри: Мои дорогие моменты',
    );

    expect(player.translations, isNotEmpty);
    expect(
      adapter.requests.any((r) => r.path.endsWith('/anime/releases/9741')),
      isTrue,
    );
    expect(
      adapter.requests.any((r) => r.path.endsWith('/anime/releases/0')),
      isFalse,
    );
    expect(
      adapter.requests.first.queryParameters['query'],
      'Атри: Мои дорогие моменты',
    );
  });

  test('JikanRemoteDataSourceImpl caches timeout failures and skips repeat calls in session',
      () async {
    final dio = Dio();
    int hitCount = 0;
    dio.httpClientAdapter = _FakeAdapter((options) {
      hitCount++;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    });

    final jikan = JikanRemoteDataSourceImpl(customDio: dio);
    final first = await jikan.getReviewsAndScore(777555);
    final second = await jikan.getReviewsAndScore(777555);

    expect(first.reviews, isEmpty);
    expect(second.reviews, isEmpty);
    expect(hitCount, 1);
  });
}
