import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../models/anime_catalog_model.dart';
import '../models/anime_player_data_model.dart';

abstract class AnimeRemoteDataSource {
  /// Получение каталога через Supabase Edge Function get_catalog (BFF для Shikimori API v1)
  Future<List<AnimeCatalogModel>> getCatalog({
    int page = 1,
    int limit = 30,
    String? order,
    String? status,
    String? genre,
  });

  /// Поиск по аниме через Supabase Edge Function get_catalog
  Future<List<AnimeCatalogModel>> searchCatalog(String query, {int limit = 30});

  /// Получение прямых ссылок и озвучек через Supabase Edge Function get_anime_player_data
  Future<AnimePlayerDataModel> getPlayerLinks(int shikimoriId, {String? title});
}

class ShikimoriAnimeRemoteDataSourceImpl implements AnimeRemoteDataSource {
  final SupabaseClient? _client;
  final Dio _dio;

  static const String _fallbackShikimoriUrl = 'https://shikimori.one/api/animes';
  static const String _mirrorShikimoriUrl = 'https://shikimori.io/api/animes';

  ShikimoriAnimeRemoteDataSourceImpl({
    Dio? customDio,
    SupabaseClient? customClient,
  })  : _client = customClient,
        _dio = customDio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 5),
                sendTimeout: const Duration(seconds: 4),
                headers: const {
                  'User-Agent': 'SyncPai-App/1.0',
                  'Accept': 'application/json',
                },
              ),
            );

  SupabaseClient? get _supabase {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<AnimeCatalogModel>> getCatalog({
    int page = 1,
    int limit = 30,
    String? order,
    String? status,
    String? genre,
  }) async {
    final client = _supabase;
    if (client != null) {
      try {
        final response = await client.functions.invoke(
          'get_catalog',
          body: {
            'page': page,
            'limit': limit,
            if (order != null && order.isNotEmpty) 'order': order,
            if (status != null && status.isNotEmpty) 'status': status,
            if (genre != null && genre.isNotEmpty) 'genre': genre,
          },
        );

        final dynamic data = response.data;
        if (data is List) {
          return data
              .whereType<Map>()
              .map((json) => AnimeCatalogModel.fromShikimori(json))
              .toList();
        }
      } catch (e) {
        // Fallback к прямому зеркалу Shikimori при ошибке Edge Function
      }
    }

    // Резервный канал напрямую к зеркалам Shikimori API
    try {
      final qParams = <String, dynamic>{
        'page': page,
        'limit': limit,
        'order': order ?? 'popularity',
      };
      if (status != null && status.isNotEmpty) qParams['status'] = status;
      if (genre != null && genre.isNotEmpty) qParams['genre'] = genre;

      final response = await _dio.get(
        _fallbackShikimoriUrl,
        queryParameters: qParams,
      );
      if (response.data is List) {
        return (response.data as List)
            .whereType<Map>()
            .map((json) => AnimeCatalogModel.fromShikimori(json))
            .toList();
      }
    } catch (_) {
      try {
        final qParams = <String, dynamic>{
          'page': page,
          'limit': limit,
          'order': order ?? 'popularity',
        };
        if (status != null && status.isNotEmpty) qParams['status'] = status;
        if (genre != null && genre.isNotEmpty) qParams['genre'] = genre;

        final mirrorRes = await _dio.get(
          _mirrorShikimoriUrl,
          queryParameters: qParams,
        );
        if (mirrorRes.data is List) {
          return (mirrorRes.data as List)
              .whereType<Map>()
              .map((json) => AnimeCatalogModel.fromShikimori(json))
              .toList();
        }
      } catch (_) {}
    }

    return [];
  }

  @override
  Future<List<AnimeCatalogModel>> searchCatalog(String query, {int limit = 30}) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return getCatalog(page: 1, limit: limit);
    }

    final client = _supabase;
    if (client != null) {
      try {
        final response = await client.functions.invoke(
          'get_catalog',
          body: {
            'page': 1,
            'limit': limit,
            'search': clean,
          },
        );

        final dynamic data = response.data;
        if (data is List) {
          return data
              .whereType<Map>()
              .map((json) => AnimeCatalogModel.fromShikimori(json))
              .toList();
        }
      } catch (_) {
        // Fallback к прямому поиску
      }
    }

    // Резервный прямой поиск
    try {
      final response = await _dio.get(
        _fallbackShikimoriUrl,
        queryParameters: {
          'search': clean,
          'page': 1,
          'limit': limit,
          'order': 'popularity',
        },
      );
      if (response.data is List) {
        return (response.data as List)
            .whereType<Map>()
            .map((json) => AnimeCatalogModel.fromShikimori(json))
            .toList();
      }
    } catch (_) {}

    return [];
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
