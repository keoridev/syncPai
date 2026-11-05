import '../entities/watch_history_item.dart';

abstract class WatchHistoryRepository {
  /// Получить историю просмотра для конкретного тайтла
  Future<WatchHistoryItem?> getProgress(int titleId);

  /// Получить всю историю просмотров (для главного экрана или профиля)
  Future<List<WatchHistoryItem>> getAllHistory();

  /// Сохранить текущий прогресс серии и минуты
  Future<void> saveProgress(WatchHistoryItem item);

  /// Удалить прогресс тайтла
  Future<void> removeProgress(int titleId);
}

