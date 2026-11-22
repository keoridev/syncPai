import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/catalog/data/datasources/anime_remote_datasource.dart';

class _RecordingCatalogAdapter implements HttpClientAdapter {
  int requestCount = 0;
  final List<Map<String, dynamic>> capturedQueryParams = [];
  final Completer<void> allowResponse = Completer<void>();

  List<Map<String, dynamic>> _buildFakeItems(int count) {
    return List.generate(
      count,
      (i) => {
        'id': i + 1,
        'alias': 'anime-${i + 1}',
        'name': {
          'main': 'Аниме ${i + 1}',
          'english': 'Anime ${i + 1}',
        },
        'poster': {
          'src': 'https://example.com/${i + 1}.jpg',
        },
        'year': 2025,
        'genres': [
          {'id': 14, 'name': 'Экшен'},
        ],
      },
    );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    capturedQueryParams.add(Map<String, dynamic>.from(options.queryParameters));
    await allowResponse.future;
    final payload = {
      'data': _buildFakeItems(40),
    };
    return ResponseBody.fromString(
      _encodeJson(payload),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  String _encodeJson(Map<String, dynamic> map) {
    // Простой ручной JSON через Uri/json не нужен — используем StringBuffer для 40 элементов
    final buf = StringBuffer('{"data":[');
    final list = map['data'] as List<Map<String, dynamic>>;
    for (int i = 0; i < list.length; i++) {
      if (i > 0) buf.write(',');
      final item = list[i];
      final name = item['name'] as Map<String, dynamic>;
      final poster = item['poster'] as Map<String, dynamic>;
      buf.write(
        '{"id":${item['id']},"alias":"${item['alias']}",'
        '"name":{"main":"${name['main']}","english":"${name['english']}"},'
        '"poster":{"src":"${poster['src']}"},'
        '"year":${item['year']},'
        '"genres":[{"id":14,"name":"Экшен"}]}',
      );
    }
    buf.write(']}');
    return buf.toString();
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AniLibertyAnimeRemoteDataSourceImpl deduplication & cancel isolation', () {
    late Dio dio;
    late _RecordingCatalogAdapter adapter;
    late AniLibertyAnimeRemoteDataSourceImpl dataSource;

    setUp(() {
      adapter = _RecordingCatalogAdapter();
      dio = Dio()..httpClientAdapter = adapter;
      dataSource = AniLibertyAnimeRemoteDataSourceImpl(customDio: dio);
    });

    test('deduplicates concurrent startup requests (limit 40, 25, 20) into 1 HTTP call and caches slices',
        () async {
      final f40 = dataSource.getCatalog(page: 1, limit: 40, sort: 'updates');
      final f25 = dataSource.getCatalog(page: 1, limit: 25); // sort=null -> updates
      final f20 = dataSource.getCatalog(page: 1, limit: 20, sort: 'updates');

      // Разрешаем ответ от сервера
      adapter.allowResponse.complete();

      final results = await Future.wait([f40, f25, f20]);

      expect(adapter.requestCount, 1);
      expect(adapter.capturedQueryParams.first['limit'], 40);
      expect(adapter.capturedQueryParams.first['f[sorting]'], 'FRESH_AT_DESC');
      expect(results[0].length, 40);
      expect(results[1].length, 25);
      expect(results[2].length, 20);

      // Повторный вызов (например, карусель на 15 элементов) обслуживается из кэша без HTTP-запроса
      final cached15 = await dataSource.getCatalog(page: 1, limit: 15, sort: 'updates');
      expect(cached15.length, 15);
      expect(adapter.requestCount, 1);
    });

    test('cancelling foreground CancelToken does NOT abort shared/background in-flight request',
        () async {
      final foregroundToken = CancelToken();
      final backgroundToken = CancelToken();

      final fgFuture = dataSource.getCatalog(
        page: 1,
        limit: 40,
        genres: 'Экшен',
        cancelToken: foregroundToken,
      );
      final bgFuture = dataSource.getCatalog(
        page: 1,
        limit: 40,
        genres: 'Экшен',
        cancelToken: backgroundToken,
      );

      // Пользователь отменил foreground-запрос, но background-предзагрузка продолжает ждать
      foregroundToken.cancel('User switched filter');

      await expectLater(
        fgFuture,
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );

      // Сервер отвечает — фоновый запрос успешно получает все 40 релизов!
      adapter.allowResponse.complete();
      final bgItems = await bgFuture;
      expect(bgItems.length, 40);
      expect(adapter.requestCount, 1);
      expect(backgroundToken.isCancelled, isFalse);
    });
  });
}

