import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/network/dio_client.dart';
import 'package:sync_pai/core/network/smart_mirror_interceptor.dart';

class _MockAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _MockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    SmartMirrorInterceptor.currentMirrorIndex = 0;
    SmartMirrorInterceptor.isAntiBlockEnabled = true;
  });

  test('apiMirrors excludes dead anilibria.tv endpoint', () {
    expect(
      SmartMirrorInterceptor.apiMirrors,
      const [
        'https://anilibria.top/api/v1',
        'https://api.anilibria.app/api/v1',
      ],
    );
  });

  test('rotates away on 410 Gone and skips nested RetryInterceptor delays',
      () async {
    final visitedUrls = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://anilibria.top/api/v1'));
    dio.httpClientAdapter = _MockAdapter((options) async {
      visitedUrls.add('${options.baseUrl}${options.path}');
      if (options.baseUrl.contains('anilibria.top')) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 410,
          ),
        );
      }
      return ResponseBody.fromString(
        '{"ok":true}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final client = DioClient(customDio: dio);
    final sw = Stopwatch()..start();
    final res = await client.get<Map<String, dynamic>>('/releases');
    sw.stop();

    expect(res.data?['ok'], isTrue);
    expect(visitedUrls, [
      'https://anilibria.top/api/v1/releases',
      'https://api.anilibria.app/api/v1/releases',
    ]);
    expect(sw.elapsedMilliseconds, lessThan(6000));
  });

  test('timeout triggers immediate mirror failover without nested retries',
      () async {
    int attempts = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://anilibria.top/api/v1'));
    dio.httpClientAdapter = _MockAdapter((options) async {
      attempts++;
      if (attempts == 1) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      }
      expect(options.extra['disable_retry'], isTrue);
      return ResponseBody.fromString(
        '{"mirror":"fallback"}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final client = DioClient(customDio: dio);
    final sw = Stopwatch()..start();
    final res = await client.get<Map<String, dynamic>>('/catalog');
    sw.stop();

    expect(res.data?['mirror'], 'fallback');
    expect(attempts, 2);
    expect(sw.elapsedMilliseconds, lessThan(6000));
  });
}

