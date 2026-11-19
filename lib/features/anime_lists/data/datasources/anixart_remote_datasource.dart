import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'anixart_backup_parser.dart';

sealed class AnixartException implements Exception {
  final String message;
  const AnixartException(this.message);

  @override
  String toString() => message;
}

class AnixartUserNotFoundException extends AnixartException {
  const AnixartUserNotFoundException([super.message = 'Пользователь не найден в базе Anixart.']);
}

class AnixartPrivateProfileException extends AnixartException {
  const AnixartPrivateProfileException([
    super.message = 'Профиль скрыт настройками приватности Anixart. Сделайте список публичным в приложении или используйте импорт через .json бэкап.',
  ]);
}

class AnixartNetworkException extends AnixartException {
  const AnixartNetworkException([super.message = 'Не удалось связаться с серверами Anixart. Попробуйте импортировать .json файл бэкапа.']);
}

abstract class AnixartRemoteDataSource {
  /// Получить закладки и историю просмотров публичного профиля Anixart по ID или логину
  Future<AnixartImportResult> fetchProfileBookmarks({
    required String loginOrId,
    required String userId,
  });
}

class AnixartRemoteDataSourceImpl implements AnixartRemoteDataSource {
  final Dio _dio;

  static const List<String> _hosts = [
    'https://api.anixart.tv',
    'https://api.anixart.app',
    'https://api-s.anixart.tv',
  ];

  static const Map<String, String> _clientHeaders = {
    'API-Version': 'v2',
    'Content-Type': 'application/json; charset=UTF-8',
    'Accept': 'application/json',
  };

  AnixartRemoteDataSourceImpl({Dio? customDio})
      : _dio = customDio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  if (!kIsWeb)
                    'User-Agent': 'AnixartApp/8.2.2-24110113 (Android 13; SDK 33; arm64-v8a; SyncPai)',
                  ..._clientHeaders,
                },
              ),
            );

  /// Человекочитаемое сопоставление ошибок Anixart для UI (без сырого DioException).
  static String mapUserFriendlyError(Object error) {
    if (error is AnixartException) {
      return error.message;
    }
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code == 400 || code == 404) {
        return 'Профиль Anixart не найден или закрыт настройками приватности. Проверьте ID/логин или воспользуйтесь «Импортом из файла» ниже.';
      }
      if (code == 403 ||
          code == 429 ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionError) {
        return 'Серверы Anixart временно недоступны или ограничивают запросы. Попробуйте позже или загрузите файл экспорта из Anixart.';
      }
      return 'Не удалось загрузить профиль Anixart. Проверьте ID/логин или воспользуйтесь «Импортом из файла» ниже.';
    }
    return 'Не удалось загрузить профиль Anixart. Попробуйте позже или воспользуйтесь «Импортом из файла» ниже.';
  }

  Options get _requestOptions => Options(
        headers: {
          if (!kIsWeb)
            'User-Agent': 'AnixartApp/8.2.2-24110113 (Android 13; SDK 33; arm64-v8a; SyncPai)',
          ..._clientHeaders,
        },
      );

  @override
  Future<AnixartImportResult> fetchProfileBookmarks({
    required String loginOrId,
    required String userId,
  }) async {
    final query = loginOrId.trim();
    if (query.isEmpty) {
      throw const AnixartUserNotFoundException('Введите логин или ID профиля Anixart.');
    }

    DioException? lastDioError;

    for (final host in _hosts) {
      try {
        final profileId = await _resolveProfileId(host, query);
        final result = await _fetchBookmarksAndHistory(host, profileId, userId);
        return result;
      } on AnixartException {
        rethrow;
      } on DioException catch (e) {
        lastDioError = e;
        debugPrint('Anixart request to $host failed (${e.response?.statusCode ?? e.type}), trying fallback...');
      } catch (e) {
        debugPrint('Anixart error on $host: $e');
      }
    }

    if (lastDioError != null) {
      final code = lastDioError.response?.statusCode;
      final friendly = mapUserFriendlyError(lastDioError);
      if (code == 400 || code == 404) {
        throw AnixartUserNotFoundException(friendly);
      }
      throw AnixartNetworkException(friendly);
    }

    throw const AnixartNetworkException(
      'Серверы Anixart временно недоступны или ограничивают запросы. Попробуйте позже или загрузите файл экспорта из Anixart.',
    );
  }

  Future<int> _resolveProfileId(String host, String query) async {
    final directId = int.tryParse(query);
    if (directId != null) {
      final profileRes = await _dio.get(
        '$host/profile/$directId',
        options: _requestOptions,
      );
      if (profileRes.statusCode == 403) {
        throw const AnixartPrivateProfileException();
      }
      if (profileRes.statusCode == 400 || profileRes.statusCode == 404) {
        throw AnixartUserNotFoundException(
          'Профиль Anixart с ID $directId не найден или закрыт настройками приватности. Проверьте ID или воспользуйтесь «Импортом из файла» ниже.',
        );
      }
      return directId;
    }

    // Если передан текст/логин — ищем через POST /search/profiles/{page}
    final searchUrl = '$host/search/profiles/0';
    final response = await _dio.post(
      searchUrl,
      data: {'query': query},
      options: _requestOptions,
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data;
      List<dynamic> users = [];

      if (data is Map<String, dynamic>) {
        if (data['profiles'] is List) {
          users = data['profiles'] as List;
        } else if (data['content'] is List) {
          users = data['content'] as List;
        } else if (data['users'] is List) {
          users = data['users'] as List;
        }
      } else if (data is List) {
        users = data;
      }

      if (users.isEmpty) {
        throw AnixartUserNotFoundException('Пользователь «$query» не найден в Anixart.');
      }

      // Ищем точное совпадение логина
      final exact = users.firstWhere(
        (u) => (u['login']?.toString().toLowerCase() == query.toLowerCase()) ||
               (u['username']?.toString().toLowerCase() == query.toLowerCase()),
        orElse: () => users.first,
      );

      final id = exact['id'] as int? ?? int.tryParse('${exact['id'] ?? ''}');
      if (id != null) return id;
    }

    throw AnixartUserNotFoundException('Не удалось получить ID для пользователя «$query».');
  }

  Future<AnixartImportResult> _fetchBookmarksAndHistory(
    String host,
    int profileId,
    String userId,
  ) async {
    final bookmarksUrl = '$host/profile/$profileId/bookmarks';
    final response = await _dio.get(bookmarksUrl, options: _requestOptions);

    if (response.statusCode == 403) {
      throw const AnixartPrivateProfileException();
    } else if (response.statusCode == 404) {
      throw const AnixartUserNotFoundException();
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      final code = data['code'] as int? ?? 0;
      final msg = (data['message']?.toString() ?? '').toLowerCase();

      if (code == 2 || msg.contains('закрыт') || msg.contains('приватн')) {
        throw const AnixartPrivateProfileException();
      }
    }

    final rawJson = data is String ? data : jsonEncode(data);
    final result = AnixartBackupParser.parse(rawJson, userId: userId);

    // Если закладок нет или мало, проверяем историю просмотров
    if (result.entries.isEmpty) {
      try {
        final historyUrl = '$host/profile/$profileId/history';
        final historyRes = await _dio.get(historyUrl, options: _requestOptions);
        if (historyRes.statusCode == 200 && historyRes.data != null) {
          final histJson = historyRes.data is String ? historyRes.data : jsonEncode(historyRes.data);
          final histResult = AnixartBackupParser.parse(histJson, userId: userId);
          if (histResult.entries.isNotEmpty) {
            return histResult;
          }
        }
      } catch (e) {
        debugPrint('Anixart history fetch error: $e');
      }
    }

    return result;
  }
}

