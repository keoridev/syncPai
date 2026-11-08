import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../models/anime_catalog_model.dart';
import '../models/anime_player_data_model.dart';

abstract class AnimeRemoteDataSource {
  /// Получение кэшированного каталога напрямую из PostgreSQL таблицы Supabase
  Future<List<AnimeCatalogModel>> getCatalog({int page = 1, int limit = 30});

  /// Поиск по аниме в таблице anime_catalog в Supabase PostgreSQL
  Future<List<AnimeCatalogModel>> searchCatalog(String query, {int limit = 30});

  /// Получение прямых ссылок и озвучек через Supabase Edge Function get_anime_player_data
  Future<AnimePlayerDataModel> getPlayerLinks(int shikimoriId, {String? title});
}

class SupabaseAnimeRemoteDataSourceImpl implements AnimeRemoteDataSource {
  final SupabaseClient? _client;

  SupabaseAnimeRemoteDataSourceImpl([this._client]);

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
      final from = (page - 1) * limit;
      final to = from + limit - 1;

      final response = await client
          .from('anime_catalog')
          .select()
          .order('score', ascending: false)
          .range(from, to);

      final List<dynamic> list = response as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map((json) => AnimeCatalogModel.fromJson(json))
          .toList();
    } catch (e) {
      throw ServerException('Ошибка загрузки каталога из Supabase: $e');
    }
  }

  @override
  Future<List<AnimeCatalogModel>> searchCatalog(String query, {int limit = 30}) async {
    final client = _supabase;
    if (client == null) {
      throw const NetworkException('Supabase клиент не инициализирован');
    }

    try {
      final clean = query.trim().replaceAll("'", "''");
      final response = await client
          .from('anime_catalog')
          .select()
          .or('title_ru.ilike.%$clean%,title_en.ilike.%$clean%')
          .order('score', ascending: false)
          .limit(limit);

      final List<dynamic> list = response as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map((json) => AnimeCatalogModel.fromJson(json))
          .toList();
    } catch (e) {
      throw ServerException('Ошибка поиска по каталогу Supabase: $e');
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
        // Если ответ пришел строкой
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

