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
  ];

  AnixartRemoteDataSourceImpl({Dio? customDio})
      : _dio = customDio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  if (!kIsWeb) 'User-Agent': 'AnixartApp/8.2.3 (Android; OkHttp)',
                  'Accept': 'application/json',
                },
              ),
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
        debugPrint('Anixart request to $host failed: ${e.message}, trying fallback...');
      } catch (e) {
        debugPrint('Anixart error on $host: $e');
      }
    }

    throw AnixartNetworkException(
      lastDioError?.message != null
          ? 'Ошибка сети при обращении к Anixart: ${lastDioError!.message}'
          : 'Не удалось связаться с серверами Anixart. Используйте импорт через файл бэкапа.',
    );
  }

  Future<int> _resolveProfileId(String host, String query) async {
    final directId = int.tryParse(query);
    if (directId != null) {
      return directId;
    }

    // Если передан текст/логин — ищем через search профилей
    final searchUrl = '$host/profile/search';
    final response = await _dio.get(
      searchUrl,
      queryParameters: {'query': query, 'page': 0},
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
    final response = await _dio.get(bookmarksUrl);

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
        final historyRes = await _dio.get(historyUrl);
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

