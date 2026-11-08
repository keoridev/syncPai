import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../models/anime_catalog_model.dart';
import '../models/anime_player_data_model.dart';

abstract class AnimeRemoteDataSource {
  /// Получение каталога через Supabase Edge Function get_catalog (BFF для Shikimori API v1)
  Future<List<AnimeCatalogModel>> getCatalog({int page = 1, int limit = 30});

  /// Поиск по аниме через Supabase Edge Function get_catalog
  Future<List<AnimeCatalogModel>> searchCatalog(String query, {int limit = 30});

  /// Получение прямых ссылок и озвучек через Supabase Edge Function get_anime_player_data
  Future<AnimePlayerDataModel> getPlayerLinks(int shikimoriId, {String? title});
}

class ShikimoriAnimeRemoteDataSourceImpl implements AnimeRemoteDataSource {
  final SupabaseClient? _client;

  ShikimoriAnimeRemoteDataSourceImpl({
    Dio? customDio,
    SupabaseClient? customClient,
  }) : _client = customClient;

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
    final client = _supabase;
    if (client == null) {
      throw const NetworkException('Supabase клиент не инициализирован');
    }

    try {
      final response = await client.functions.invoke(
        'get_catalog',
        body: {
          'page': page,
          'limit': limit,
        },
      );

      final dynamic data = response.data;
      if (data is List) {
        return data
            .whereType<Map>()
            .map((json) => AnimeCatalogModel.fromShikimori(json))
            .toList();
      }
      return [];
    } catch (e) {
      if (e is ServerException || e is NetworkException) rethrow;
      throw ServerException('Ошибка загрузки каталога через Edge Function get_catalog: $e');
    }
  }

  @override
  Future<List<AnimeCatalogModel>> searchCatalog(String query, {int limit = 30}) async {
    final client = _supabase;
    if (client == null) {
      throw const NetworkException('Supabase клиент не инициализирован');
    }

    final clean = query.trim();

    try {
      final response = await client.functions.invoke(
        'get_catalog',
        body: {
          'page': 1,
          'limit': limit,
          if (clean.isNotEmpty) 'search': clean,
        },
      );

      final dynamic data = response.data;
      if (data is List) {
        return data
            .whereType<Map>()
            .map((json) => AnimeCatalogModel.fromShikimori(json))
            .toList();
      }
      return [];
    } catch (e) {
      if (e is ServerException || e is NetworkException) rethrow;
      throw ServerException('Ошибка поиска по каталогу через Edge Function get_catalog: $e');
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
