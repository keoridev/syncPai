import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/di/injection.dart';
import '../../../watch_history/domain/repositories/watch_history_repository.dart';
import '../../data/datasources/anixart_backup_parser.dart';
import '../../domain/entities/user_anime_entry.dart';
import '../../domain/repositories/anime_list_repository.dart';
import 'anime_list_state.dart';

class AnimeListCubit extends Cubit<AnimeListState> {
  final AnimeListRepository repository;

  AnimeListCubit({required this.repository})
      : super(AnimeListState(
          stats: UserAnimeStats.compute(const []),
        )) {
    loadLists();
  }

  Future<void> loadLists() async {
    emit(state.copyWith(isLoading: true));
    try {
      final entries = await repository.getAllEntries();

      // Авто-синхронизация: если тайтл просмотрен в истории просмотров,
      // но ещё не добавлен в списки — автоматически заносим его в «Смотрю»
      if (getIt.isRegistered<WatchHistoryRepository>()) {
        try {
          final historyRepo = getIt<WatchHistoryRepository>();
          final historyList = await historyRepo.getAllHistory();
          bool hasNewEntries = false;
          for (final item in historyList) {
            final exists = entries.any((e) => e.animeId == item.titleId);
            if (!exists) {
              final newEntry = UserAnimeEntry(
                id: 'history_${item.titleId}_${item.updatedAt.millisecondsSinceEpoch}',
                userId: '',
                animeId: item.titleId,
                titleRu: item.titleName,
                posterUrl: item.posterUrl,
                status: AnimeListStatus.watching,
                lastEpisode: item.episode,
                positionMs: item.positionMs,
                updatedAt: item.updatedAt,
              );
              await repository.upsertEntry(newEntry);
              entries.add(newEntry);
              hasNewEntries = true;
            }
          }
          if (hasNewEntries) {
            entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          }
        } catch (_) {}
      }

      final stats = UserAnimeStats.compute(entries);
      emit(state.copyWith(
        allEntries: entries,
        stats: stats,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Ошибка загрузки списков: $e',
      ));
    }
  }

  void selectTab(AnimeListStatus status) {
    emit(state.copyWith(selectedTab: status));
  }

  Future<void> setAnimeStatus({
    required int animeId,
    required String titleRu,
    String? posterUrl,
    required AnimeListStatus status,
    int lastEpisode = 1,
    int positionMs = 0,
    int? episodesTotal,
  }) async {
    final existing = state.getEntryFor(animeId);
    final entry = (existing != null)
        ? existing.copyWith(
            status: status,
            titleRu: titleRu,
            posterUrl: posterUrl ?? existing.posterUrl,
            lastEpisode: lastEpisode,
            positionMs: positionMs,
            episodesTotal: episodesTotal ?? existing.episodesTotal,
            updatedAt: DateTime.now(),
          )
        : UserAnimeEntry(
            id: 'list_${animeId}_${DateTime.now().millisecondsSinceEpoch}',
            userId: '',
            animeId: animeId,
            titleRu: titleRu,
            posterUrl: posterUrl,
            status: status,
            lastEpisode: lastEpisode,
            positionMs: positionMs,
            episodesTotal: episodesTotal,
            updatedAt: DateTime.now(),
          );

    await repository.upsertEntry(entry);
    await loadLists();
  }

  Future<void> removeAnime(int animeId) async {
    await repository.removeEntry(animeId);
    await loadLists();
  }

  Future<void> importBatch(List<UserAnimeEntry> entries) async {
    if (entries.isEmpty) return;
    emit(state.copyWith(isLoading: true));
    try {
      for (final entry in entries) {
        await repository.upsertEntry(entry);
      }
      final all = await repository.getAllEntries();
      final stats = UserAnimeStats.compute(all);
      final importResult = AnixartImportResult(
        entries: entries,
        totalParsed: entries.length,
        totalEpisodes: stats.totalEpisodesCompleted,
        estimatedTimeSpent: stats.formattedTime,
      );
      emit(state.copyWith(
        allEntries: all,
        stats: stats,
        isLoading: false,
        lastImportResult: importResult,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Ошибка пакетного импорта: $e',
      ));
    }
  }

  Future<void> importAnixartBackup(String jsonContent, {required String userId}) async {
    emit(state.copyWith(isLoading: true));
    try {
      final result = await repository.importAnixartBackup(jsonContent, userId: userId);
      final entries = await repository.getAllEntries();
      final stats = UserAnimeStats.compute(entries);
      emit(state.copyWith(
        allEntries: entries,
        stats: stats,
        isLoading: false,
        lastImportResult: result,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Ошибка парсинга бэкапа Anixart: $e',
      ));
    }
  }

  Future<AnixartImportResult?> importAnixartOnline(String loginOrId, {required String userId}) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final result = await repository.importAnixartByLoginOrId(loginOrId, userId: userId);
      final entries = await repository.getAllEntries();
      final stats = UserAnimeStats.compute(entries);
      emit(state.copyWith(
        allEntries: entries,
        stats: stats,
        isLoading: false,
        lastImportResult: result,
      ));
      return result;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      emit(state.copyWith(
        isLoading: false,
        errorMessage: msg,
      ));
      rethrow;
    }
  }

  Future<void> syncWithCloud({required String userId}) async {
    await repository.syncWithCloud(userId: userId);
    await loadLists();
  }

  /// Тихо обновить постер для тайтла в памяти и локальной базе
  Future<void> updatePosterUrl(int animeId, String posterUrl) async {
    await repository.updatePosterUrl(animeId, posterUrl);
    final updatedList = state.allEntries.map((e) {
      if (e.animeId == animeId) {
        return e.copyWith(posterUrl: posterUrl);
      }
      return e;
    }).toList();
    emit(state.copyWith(allEntries: updatedList));
  }

  /// Пакетное перемещение тайтлов в другой статус (Массовое управление)
  Future<void> batchChangeStatus(List<int> animeIds, AnimeListStatus newStatus) async {
    if (animeIds.isEmpty) return;
    await repository.batchChangeStatus(animeIds, newStatus);
    await loadLists();
  }

  /// Пакетное удаление тайтлов из списков (Массовое управление)
  Future<void> batchDelete(List<int> animeIds) async {
    if (animeIds.isEmpty) return;
    await repository.batchDelete(animeIds);
    await loadLists();
  }
}

