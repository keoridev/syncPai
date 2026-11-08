import '../entities/user_anime_entry.dart';
import '../../data/datasources/anixart_backup_parser.dart';

abstract class AnimeListRepository {
  /// Получить все сохраненные записи списков (Offline-first)
  Future<List<UserAnimeEntry>> getAllEntries();

  /// Получить статус конкретного тайтла
  Future<UserAnimeEntry?> getEntry(int animeId);

  /// Сохранить или обновить статус/прогресс тайтла
  Future<void> upsertEntry(UserAnimeEntry entry);

  /// Удалить тайтл из списков
  Future<void> removeEntry(int animeId);

  /// Тихо обновить постер для тайтла в локальной БД
  Future<void> updatePosterUrl(int animeId, String posterUrl);

  /// Массово изменить статус списка для группы тайтлов
  Future<void> batchChangeStatus(List<int> animeIds, AnimeListStatus newStatus);

  /// Массово удалить группу тайтлов из списков
  Future<void> batchDelete(List<int> animeIds);

  /// Импортировать закладки из файла бэкапа Anixart
  Future<AnixartImportResult> importAnixartBackup(String jsonContent, {required String userId});

  /// Умный импорт CSV-закладок Anixart с поиском по Shikimori API и маппингом статусов
  Future<AnixartImportResult> importAnixartCsvWithShikimori(
    String rawCsv, {
    required String userId,
    AnimeListStatus defaultStatus = AnimeListStatus.planned,
    AnimeListStatus? overrideStatus,
    void Function(int current, int total, String currentTitle)? onProgress,
  });

  /// Импортировать закладки онлайн по ID профиля или логину Anixart
  Future<AnixartImportResult> importAnixartByLoginOrId(String loginOrId, {required String userId});

  /// Синхронизировать списки с Supabase (фоновый процесс)
  Future<void> syncWithCloud({required String userId});
}

