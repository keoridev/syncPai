import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'api_constants.dart';
import '../error/exceptions.dart';

class DioClient {
  final Dio dio;

  DioClient({Dio? customDio})
      : dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConstants.baseUrl,
                connectTimeout: ApiConstants.connectTimeout,
                receiveTimeout: ApiConstants.receiveTimeout,
                sendTimeout: ApiConstants.sendTimeout,
                headers: {
                  'Accept': 'application/json',
                  'User-Agent': 'SyncPai/1.0.0 (Flutter; Cross-Platform)',
                },
              ),
            ) {
    dio.interceptors.addAll([
      RetryInterceptor(
        dio: dio,
        logPrint: (message) => log('[DioRetry] $message'),
        retries: 3,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 3),
        ],
      ),
      InterceptorsWrapper(
        onRequest: (options, handler) {
          log('[Dio] Request: ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          log('[Dio] Response [${response.statusCode}] from ${response.requestOptions.uri}');
          return handler.next(response);
        },
        onError: (DioException error, handler) {
          log('[Dio] Error: ${error.type} - ${error.message} (${error.requestOptions.uri})');
          return handler.next(error);
        },
      ),
    ]);
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      return response;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  Exception _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return NetworkException(error.message ?? 'Таймаут подключения');
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final message = error.response?.statusMessage ?? 'Ошибка сервера ($statusCode)';
        return ServerException(message, statusCode);
      case DioExceptionType.cancel:
        return const ServerException('Запрос отменен');
      default:
        return ServerException(error.message ?? 'Неизвестная сетевая ошибка');
    }
  }
}

