import '../entities/anime_clip.dart';

abstract class AnimeClipsRepository {
  /// Получить список клипов для ленты
  Future<List<AnimeClip>> getClips({bool forceRefresh = false});

  /// Переключить лайк клипа
  Future<bool> toggleLike(String clipId);

  /// Переключить закладку
  Future<bool> toggleBookmark(String clipId);
}

