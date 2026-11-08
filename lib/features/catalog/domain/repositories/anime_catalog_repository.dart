import '../entities/anime_entity.dart';
import '../entities/translation_entity.dart';

abstract class AnimeCatalogRepository {
  /// Получение каталога аниме с поддержкой пагинации из Supabase
  Future<List<AnimeEntity>> getCatalog({int page = 1, int limit = 30});

  /// Получение ссылок на видеопотоки и озвучки через Supabase BFF Edge Function
  Future<List<TranslationEntity>> getPlayerLinks(int shikimoriId, {String? title});
}

