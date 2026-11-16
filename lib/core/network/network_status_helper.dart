import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Lightweight helper for fast network reachability detection (< 500ms).
class NetworkStatusHelper {
  /// Test override hook for deterministic testing without real socket calls.
  static bool? testOverride;

  /// Fast DNS lookup check. Resolves in < 500ms using low-latency public resolvers.
  /// Skips socket lookup on web platforms or during automated widget tests.
  static Future<bool> hasInternet() async {
    if (testOverride != null) {
      return testOverride!;
    }
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
      return true;
    }

    try {
      final result = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(milliseconds: 450));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {
      // Fallback quickly to dns.google if Cloudflare lookup failed or timed out
      try {
        final fallback = await InternetAddress.lookup('dns.google')
            .timeout(const Duration(milliseconds: 350));
        if (fallback.isNotEmpty && fallback[0].rawAddress.isNotEmpty) {
          return true;
        }
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  /// Determines whether an exception or message indicates network disconnection / timeout.
  static bool isConnectionError(Object? error) {
    if (error == null) return false;

    if (error is SocketException) {
      return true;
    }

    if (error is TimeoutException) {
      return true;
    }

    if (error is DioException) {
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          (error.error is SocketException);
    }

    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('connection timed out') ||
        message.contains('connection error') ||
        message.contains('нет подключения к интернету') ||
        message.contains('клиент оффлайн') ||
        message.contains('offline');
  }
}
