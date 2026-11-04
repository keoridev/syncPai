import '../entities/anime_title.dart';

abstract class CatalogRepository {
  /// Получить последние обновленные релизы
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20});

  /// Поиск по названию
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20});

  /// Получить подробную информацию о тайтле (по id или code)
  Future<AnimeTitle> getTitleDetails({int? id, String? code});
}

