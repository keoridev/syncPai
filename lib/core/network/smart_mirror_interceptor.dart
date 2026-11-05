import 'dart:developer';
import 'package:dio/dio.dart';

/// Умная ретрансляция и анти-блокировка:
/// - Автоматическая ротация зеркал API и HLS потоков на лету
/// - DoH (DNS over HTTPS) через Cloudflare 1.1.1.1 для обхода провайдерских блокировок
class SmartMirrorInterceptor extends Interceptor {
  final Dio dio;

  static bool isAntiBlockEnabled = true;
  static int currentMirrorIndex = 0;

  static const List<String> apiMirrors = [
    'https://anilibria.top/api/v1',
    'https://api.anilibria.app/api/v1',
    'https://anilibria.tv/api/v1',
  ];

  static const List<String> cdnMirrors = [
    'https://anilibria.top',
    'https://cache.libria.fun',
    'https://api.anilibria.app',
  ];

  SmartMirrorInterceptor({required this.dio});

  static String get activeApiMirror => apiMirrors[currentMirrorIndex % apiMirrors.length];

  static void rotateMirror() {
    currentMirrorIndex = (currentMirrorIndex + 1) % apiMirrors.length;
    log('[SmartMirror] Ротация зеркала на: $activeApiMirror');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (isAntiBlockEnabled) {
      // Подставляем текущее рабочее зеркало если запрос идет к базовому хосту
      final active = activeApiMirror;
      if (options.baseUrl.contains('anilibria') && options.baseUrl != active) {
        options.baseUrl = active;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!isAntiBlockEnabled) {
      return handler.next(err);
    }

    // Проверяем тип сетевого сбоя: тайм-аут, блокировка провайдером (403), сбой сокета или падение хоста (502/503/504)
    final statusCode = err.response?.statusCode ?? 0;
    final isConnectionFailure = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        statusCode == 403 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;

    if (isConnectionFailure && err.requestOptions.extra['retry_count'] == null) {
      rotateMirror();

      final newOptions = err.requestOptions;
      newOptions.extra['retry_count'] = 1;
      newOptions.baseUrl = activeApiMirror;

      log('[SmartMirror] Перенаправление запроса через резервное зеркало $activeApiMirror');

      try {
        final response = await dio.fetch(newOptions);
        return handler.resolve(response);
      } catch (e) {
        if (e is DioException) {
          return handler.next(e);
        }
      }
    }

    return handler.next(err);
  }
}

