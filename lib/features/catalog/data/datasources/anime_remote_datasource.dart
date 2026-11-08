import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../models/anime_catalog_model.dart';
import '../models/anime_player_data_model.dart';

abstract class AnimeRemoteDataSource {
  /// Получение каталога напрямую через официальный Shikimori API v1 (15 000+ аниме)
  Future<List<AnimeCatalogModel>> getCatalog({int page = 1, int limit = 30});

  /// Поиск по аниме через официальный Shikimori API v1
  Future<List<AnimeCatalogModel>> searchCatalog(String query, {int limit = 30});

  /// Получение прямых ссылок и озвучек через Supabase Edge Function get_anime_player_data
  Future<AnimePlayerDataModel> getPlayerLinks(int shikimoriId, {String? title});
}

class ShikimoriAnimeRemoteDataSourceImpl implements AnimeRemoteDataSource {
  final Dio _dio;
  final SupabaseClient? _client;

  static const String _primaryUrl = 'https://shikimori.me/api/animes';
  static const String _fallbackUrl = 'https://shikimori.one/api/animes';
  static const Map<String, dynamic> _headers = {
    'User-Agent': 'SyncPai-App/1.0',
    'Accept': 'application/json',
  };

  ShikimoriAnimeRemoteDataSourceImpl({
    Dio? customDio,
    SupabaseClient? customClient,
  })  : _dio = customDio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 12),
                headers: _headers,
              ),
            ),
        _client = customClient;

  SupabaseClient? get _supabase {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<AnimeCatalogModel>> getCatalog({int page = 1, int limit = 30}) async {
    try {
      dynamic responseData;
      try {
        final response = await _dio.get(
          _primaryUrl,
          queryParameters: {
            'page': page,
            'limit': limit,
            'order': 'popularity',
          },
          options: Options(headers: _headers),
        );
        responseData = response.data;
      } catch (primaryErr) {
        // Fallback на зеркало shikimori.one
        final response = await _dio.get(
          _fallbackUrl,
          queryParameters: {
            'page': page,
            'limit': limit,
            'order': 'popularity',
          },
          options: Options(headers: _headers),
        );
        responseData = response.data;
      }

      if (responseData is List) {
        return responseData
            .whereType<Map<String, dynamic>>()
            .map((json) => AnimeCatalogModel.fromShikimori(json))
            .toList();
      }
      return [];
    } catch (e) {
      if (e is ServerException || e is NetworkException) rethrow;
      throw ServerException('Ошибка загрузки каталога Shikimori: $e');
    }
  }

  @override
  Future<List<AnimeCatalogModel>> searchCatalog(String query, {int limit = 30}) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return getCatalog(page: 1, limit: limit);
    }

    try {
      dynamic responseData;
      try {
        final response = await _dio.get(
          _primaryUrl,
          queryParameters: {
            'search': clean,
            'page': 1,
            'limit': limit,
            'order': 'popularity',
          },
          options: Options(headers: _headers),
        );
        responseData = response.data;
      } catch (primaryErr) {
        final response = await _dio.get(
          _fallbackUrl,
          queryParameters: {
            'search': clean,
            'page': 1,
            'limit': limit,
            'order': 'popularity',
          },
          options: Options(headers: _headers),
        );
        responseData = response.data;
      }

      if (responseData is List) {
        return responseData
            .whereType<Map<String, dynamic>>()
            .map((json) => AnimeCatalogModel.fromShikimori(json))
            .toList();
      }
      return [];
    } catch (e) {
      if (e is ServerException || e is NetworkException) rethrow;
      throw ServerException('Ошибка поиска по каталогу Shikimori: $e');
    }
  }

  @override
  Future<AnimePlayerDataModel> getPlayerLinks(int shikimoriId, {String? title}) async {
    final client = _supabase;
    if (client == null) {
      throw const NetworkException('Supabase клиент не инициализирован');
    }

    try {
      final response = await client.functions.invoke(
        'get_anime_player_data',
        body: {
          'shikimori_id': shikimoriId,
          if (title != null && title.isNotEmpty) 'title': title,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return AnimePlayerDataModel.fromJson(data);
      } else if (data is String) {
        return AnimePlayerDataModel(
          shikimoriId: shikimoriId,
          translations: const [],
          error: data,
        );
      }

      throw const ParsingException('Некорректный формат ответа Edge Function');
    } catch (e) {
      throw ServerException('Ошибка вызова Edge Function get_anime_player_data: $e');
    }
  }
}

typedef SupabaseAnimeRemoteDataSourceImpl = ShikimoriAnimeRemoteDataSourceImpl;
