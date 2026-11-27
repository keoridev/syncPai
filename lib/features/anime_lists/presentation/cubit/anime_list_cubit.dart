import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/datasources/anixart_backup_parser.dart';
import '../../data/datasources/anixart_remote_datasource.dart';
import '../../domain/entities/user_anime_entry.dart';
import '../../domain/repositories/anime_list_repository.dart';
import '../../services/import_poster_enricher.dart';
import '../../../profile/domain/services/achievement_service.dart';
import '../../../../core/services/anime_poster_resolver.dart';
import '../../../../core/services/mascot_companion_service.dart';
import 'anime_list_state.dart';

class AnimeListCubit extends Cubit<AnimeListState> {
  final AnimeListRepository repository;

  AnimeListCubit({required this.repository})
      : super(AnimeListState(
          stats: UserAnimeStats.compute(const []),
        )) {
    loadLists();
  }

  static String normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^a-zа-я0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isValidPoster(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final lower = url.toLowerCase();
    return !lower.contains('missing_original') &&
        !lower.contains('missing_preview') &&
        !lower.contains('missing_x');
  }

  static int _posterQualityScore(String? url) {
    if (!_isValidPoster(url)) return 0;
    final lower = url!.toLowerCase();
    if (lower.contains('original')) return 3;
    if (lower.contains('medium') || lower.contains('preview')) return 2;
    return 1;
  }

  static UserAnimeEntry _mergeDuplicateEntries(
    UserAnimeEntry a,
    UserAnimeEntry b,
  ) {
    final aIsAnilibria = a.animeId > 0 && a.animeId <= 12000;
    final bIsAnilibria = b.animeId > 0 && b.animeId <= 12000;
    final primary = (bIsAnilibria && !aIsAnilibria)
        ? b
        : (aIsAnilibria && !bIsAnilibria)
            ? a
            : (b.lastEpisode > a.lastEpisode ? b : a);
    final secondary = identical(primary, a) ? b : a;

    final bestEpisode = a.lastEpisode >= b.lastEpisode ? a.lastEpisode : b.lastEpisode;
    final bestPosition = a.lastEpisode > b.lastEpisode
        ? a.positionMs
        : (b.lastEpisode > a.lastEpisode
            ? b.positionMs
            : (a.positionMs >= b.positionMs ? a.positionMs : b.positionMs));
    final bestPoster = _posterQualityScore(a.posterUrl) >= _posterQualityScore(b.posterUrl)
        ? (_isValidPoster(a.posterUrl) ? a.posterUrl : b.posterUrl)
        : (_isValidPoster(b.posterUrl) ? b.posterUrl : a.posterUrl);
    final bestUpdated = a.updatedAt.isAfter(b.updatedAt) ? a.updatedAt : b.updatedAt;

    return primary.copyWith(
      posterUrl: bestPoster,
      lastEpisode: bestEpisode,
      positionMs: bestPosition,
      episodesTotal: primary.episodesTotal ?? secondary.episodesTotal,
      score: primary.score ?? secondary.score,
      updatedAt: bestUpdated,
    );
  }

  Future<void> loadLists() async {
    emit(state.copyWith(isLoading: true));
    try {
      final rawEntries = await repository.getAllEntries();

      // Очищаем старые авто-добавленные записи из истории (с префиксом history_),
      // а также объединяем дубликаты одного тайтла (AniLibria ID vs Shikimori ID).
      final nonHistory = <UserAnimeEntry>[];
      for (final entry in rawEntries) {
        if (entry.id.startsWith('history_')) {
          try {
            await repository.removeEntry(entry.animeId);
          } catch (_) {}
        } else {
          nonHistory.add(entry);
        }
      }

      final dedupMap = <String, UserAnimeEntry>{};
      final duplicateIdsToRemove = <int>[];

      for (final entry in nonHistory) {
        final norm = normalizeTitle(entry.titleRu);
        final key = norm.isNotEmpty
            ? '${entry.status.name}::$norm'
            : '${entry.status.name}::id_${entry.animeId}';

        final existing = dedupMap[key];
        if (existing == null) {
          dedupMap[key] = entry;
        } else {
          final merged = _mergeDuplicateEntries(existing, entry);
          dedupMap[key] = merged;
          final droppedId =
              merged.animeId == existing.animeId ? entry.animeId : existing.animeId;
          if (droppedId != merged.animeId) {
            duplicateIdsToRemove.add(droppedId);
          }
        }
      }

      for (final dupId in duplicateIdsToRemove) {
        try {
          await repository.removeEntry(dupId);
        } catch (_) {}
      }

      final entries = dedupMap.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      final stats = UserAnimeStats.compute(entries);
      emit(state.copyWith(
        allEntries: entries,
        stats: stats,
        isLoading: false,
      ));
      unawaited(_hydrateMissingPostersInBackground(entries));
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
    bool isUserInitiated = false,
  }) async {
    final existing = state.getEntryFor(animeId);
    final previousStatus = existing?.status;
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

    // 1. ОПТИМИСТИЧНОЕ ОБНОВЛЕНИЕ UI (0ms): мгновенно пересчитываем состояние и статистику
    final previousEntries = state.allEntries;
    final updatedList = List<UserAnimeEntry>.from(previousEntries);
    final idx = updatedList.indexWhere((e) => e.animeId == animeId);
    if (idx >= 0) {
      updatedList[idx] = entry;
    } else {
      updatedList.insert(0, entry);
    }
    unawaited(AchievementService.instance.checkCollectorCount(updatedList.length));
    if (isUserInitiated && previousStatus != status) {
      MascotCompanionService.instance.onCollectionAdded(status.labelRu, titleRu);
    }
    emit(state.copyWith(
      allEntries: updatedList,
      stats: UserAnimeStats.compute(updatedList),
      errorMessage: null,
      isLoading: false,
    ));

    // 2. Сохранение на диск и неблокирующая синхронизация с облаком
    try {
      await repository.upsertEntry(entry);
      final persistedEntries = await repository.getAllEntries();
      if (!isClosed) {
        emit(state.copyWith(
          allEntries: persistedEntries,
          stats: UserAnimeStats.compute(persistedEntries),
          isLoading: false,
        ));
      }
    } catch (e) {
      // Откатываем оптимистичное состояние только при реальной ошибке сохранения
      if (!isClosed) {
        emit(state.copyWith(
          allEntries: previousEntries,
          stats: UserAnimeStats.compute(previousEntries),
          errorMessage: 'Ошибка обновления статуса: $e',
          isLoading: false,
        ));
      }
    }
  }

  /// Мгновенно (0ms) очищает все списки закладок локально и запускает удаление в Supabase.
  Future<void> clearAllLists({String? userId}) async {
    emit(state.copyWith(
      allEntries: const [],
      stats: UserAnimeStats.compute(const []),
      isLoading: false,
      errorMessage: null,
    ));
    await repository.clearAllEntries(userId: userId);
  }

  Future<void> removeAnime(int animeId) async {
    final previousEntries = state.allEntries;
    final updatedList = List<UserAnimeEntry>.from(previousEntries)
      ..removeWhere((e) => e.animeId == animeId);

    // Оптимистичное удаление (0ms)
    emit(state.copyWith(
      allEntries: updatedList,
      stats: UserAnimeStats.compute(updatedList),
      errorMessage: null,
    ));

    try {
      await repository.removeEntry(animeId);
    } catch (e) {
      emit(state.copyWith(
        allEntries: previousEntries,
        stats: UserAnimeStats.compute(previousEntries),
        errorMessage: 'Ошибка удаления из списков: $e',
      ));
    }
  }

  Future<void> importBatch(List<UserAnimeEntry> entries) async {
    if (entries.isEmpty) return;
    emit(state.copyWith(isLoading: true));
    try {
      await repository.upsertEntries(entries);
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
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        unawaited(enrichImportedEntriesInBackground(result.entries));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Ошибка парсинга бэкапа Anixart: $e',
      ));
    }
  }

  /// Умный импорт CSV закладок с маппингом через официальный Shikimori API
  Future<AnixartImportResult?> importAnixartCsvWithShikimori(
    String rawCsv, {
    required String userId,
    AnimeListStatus defaultStatus = AnimeListStatus.planned,
    AnimeListStatus? overrideStatus,
    void Function(int current, int total, String currentTitle)? onProgress,
  }) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final result = await repository.importAnixartCsvWithShikimori(
        rawCsv,
        userId: userId,
        defaultStatus: defaultStatus,
        overrideStatus: overrideStatus,
        onProgress: onProgress,
      );
      final entries = await repository.getAllEntries();
      final stats = UserAnimeStats.compute(entries);
      emit(state.copyWith(
        allEntries: entries,
        stats: stats,
        isLoading: false,
        lastImportResult: result,
      ));
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        unawaited(enrichImportedEntriesInBackground(result.entries));
      }
      return result;
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Ошибка умного импорта Anixart: $e',
      ));
      return null;
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
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        unawaited(enrichImportedEntriesInBackground(result.entries));
      }
      return result;
    } catch (e) {
      final msg = AnixartRemoteDataSourceImpl.mapUserFriendlyError(e);
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

  /// Фоновая дозагрузка постеров, totalEpisodes и animeId для импортированных карточек
  Future<void> enrichImportedEntriesInBackground(
    List<UserAnimeEntry> importedEntries, {
    Dio? dio,
  }) async {
    await ImportPosterEnricher.instance.enrichEntries(
      importedEntries,
      dio: dio,
      onEnriched: (match) async {
        if (isClosed) return;
        final idx = state.allEntries.indexWhere((e) => e.animeId == match.oldAnimeId);
        if (idx == -1) return;
        final current = state.allEntries[idx];
        final resolvedId = match.matchedAnimeId ?? current.animeId;
        final updated = current.copyWith(
          animeId: resolvedId,
          posterUrl: match.posterUrl,
          episodesTotal: match.totalEpisodes ?? current.episodesTotal,
          updatedAt: DateTime.now(),
        );
        if (resolvedId != current.animeId) {
          await repository.removeEntry(current.animeId);
        }
        await repository.upsertEntry(updated);
        if (isClosed) return;
        final nextList = List<UserAnimeEntry>.from(state.allEntries);
        nextList[idx] = updated;
        emit(state.copyWith(
          allEntries: nextList,
          stats: UserAnimeStats.compute(nextList),
        ));
      },
    );
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

  Future<void> _hydrateMissingPostersInBackground(
    List<UserAnimeEntry> entries,
  ) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final candidates = entries.where((e) {
      return AnimePosterResolver.isMissingOrPlaceholder(e.posterUrl) ||
          AnimePosterResolver.isAniLibriaWatermarkedUrl(e.posterUrl);
    }).toList();
    if (candidates.isEmpty) return;

    final ids = candidates
        .map((e) => e.animeId)
        .where((id) => id > 0)
        .toList();
    final batchHits = await AnimePosterResolver.instance.resolveBatchIds(ids);
    if (isClosed) return;

    for (final entry in candidates) {
      final hit = batchHits[entry.animeId];
      if (hit != null && hit != entry.posterUrl) {
        await updatePosterUrl(entry.animeId, hit);
      }
    }

    final remaining = candidates
        .where((e) => !batchHits.containsKey(e.animeId))
        .take(20);
    await Future.wait(
      remaining.map((entry) async {
        if (isClosed) return;
        final resolved = await AnimePosterResolver.instance.resolvePoster(
          malId: entry.animeId > 0 ? entry.animeId : null,
          title: entry.titleRu,
        );
        if (!isClosed && resolved != null && resolved != entry.posterUrl) {
          await updatePosterUrl(entry.animeId, resolved);
        }
      }),
    );
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

