import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../datasources/anixart_backup_parser.dart';
import '../datasources/anixart_csv_parser.dart';
import '../datasources/anixart_remote_datasource.dart';
import '../../domain/entities/user_anime_entry.dart';
import '../../domain/repositories/anime_list_repository.dart';
import '../../services/lists_sync_service.dart';

class AnimeListRepositoryImpl implements AnimeListRepository {
  final SharedPreferences _prefs;
  final AnixartRemoteDataSource? anixartRemoteDataSource;
  static const String _storageKey = 'sync_pai_anime_lists_entries';

  AnimeListRepositoryImpl(this._prefs, {this.anixartRemoteDataSource});

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<UserAnimeEntry>> getAllEntries() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => UserAnimeEntry.fromJson(e as Map<String, dynamic>))
          .map((e) {
            // Если в базе сохранились сырые строки выгрузки Anixart, автоматически очищаем
            if (e.titleRu.contains(' / ') || e.titleRu.startsWith('"') || e.titleRu.contains('""')) {
              return e.copyWith(titleRu: e.cleanTitleRu);
            }
            return e;
          })
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Error reading local anime lists: $e');
      return [];
    }
  }

  Future<void> _saveLocal(List<UserAnimeEntry> entries) async {
    final jsonList = entries.map((e) => e.toJson()).toList();
    await _prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  @override
  Future<UserAnimeEntry?> getEntry(int animeId) async {
    final all = await getAllEntries();
    try {
      return all.firstWhere((e) => e.animeId == animeId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsertEntry(UserAnimeEntry entry) async {
    final all = await getAllEntries();
    final index = all.indexWhere((e) => e.animeId == entry.animeId);
    if (index >= 0) {
      all[index] = entry;
    } else {
      all.insert(0, entry);
    }
    await _saveLocal(all);

    // Неблокирующая фоновая синхронизация с Supabase (fire-and-forget)
    final client = _supabase;
    if (client != null && client.auth.currentUser != null) {
      unawaited(
        ListsSyncService.upsertEntry(
          client,
          userId: client.auth.currentUser!.id,
          entry: entry,
        ).catchError((e) {
          debugPrint('[AnimeListRepository] Background upsert error: $e');
        }),
      );
    }
  }

  @override
  Future<void> upsertEntries(List<UserAnimeEntry> entries) async {
    if (entries.isEmpty) return;
    final all = await getAllEntries();
    final map = {for (final e in all) e.animeId: e};
    for (final e in entries) {
      map[e.animeId] = e;
    }
    final merged = map.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _saveLocal(merged);

    final client = _supabase;
    if (client != null && client.auth.currentUser != null) {
      unawaited(
        ListsSyncService.upsertEntries(
          client,
          userId: client.auth.currentUser!.id,
          entries: entries,
        ).catchError((e) {
          debugPrint('[AnimeListRepository] Background batch upsert error: $e');
        }),
      );
    }
  }

  @override
  Future<void> removeEntry(int animeId) async {
    final all = await getAllEntries();
    all.removeWhere((e) => e.animeId == animeId);
    await _saveLocal(all);

    // Неблокирующее фоновое удаление из Supabase (fire-and-forget)
    final client = _supabase;
    if (client != null && client.auth.currentUser != null) {
      unawaited(() async {
        try {
          await client
              .from('user_anime_lists')
              .delete()
              .eq('user_id', client.auth.currentUser!.id)
              .eq('anime_id', animeId);
        } catch (e) {
          debugPrint('Supabase delete error: $e');
        }
      }());
    }
  }

  @override
  Future<void> updatePosterUrl(int animeId, String posterUrl) async {
    final all = await getAllEntries();
    final index = all.indexWhere((e) => e.animeId == animeId);
    if (index >= 0) {
      all[index] = all[index].copyWith(posterUrl: posterUrl);
      await _saveLocal(all);
    }
  }

  @override
  Future<void> batchChangeStatus(List<int> animeIds, AnimeListStatus newStatus) async {
    if (animeIds.isEmpty) return;
    final all = await getAllEntries();
    final idsSet = animeIds.toSet();
    final now = DateTime.now();

    for (int i = 0; i < all.length; i++) {
      if (idsSet.contains(all[i].animeId)) {
        all[i] = all[i].copyWith(status: newStatus, updatedAt: now);
      }
    }
    await _saveLocal(all);
  }

  @override
  Future<void> batchDelete(List<int> animeIds) async {
    if (animeIds.isEmpty) return;
    final all = await getAllEntries();
    final idsSet = animeIds.toSet();
    all.removeWhere((e) => idsSet.contains(e.animeId));
    await _saveLocal(all);
  }

  Future<AnixartImportResult> _mergeAndSaveImportedEntries(
    AnixartImportResult result,
  ) async {
    final current = await getAllEntries();
    final List<UserAnimeEntry> merged = List<UserAnimeEntry>.from(current);
    final Map<int, int> indexById = {};
    final Map<String, int> indexByKey = {};

    for (var i = 0; i < merged.length; i++) {
      final entry = merged[i];
      indexById[entry.animeId] = i;
      final k = normalizeAnimeKey(entry.titleRu);
      if (k.isNotEmpty) {
        indexByKey.putIfAbsent(k, () => i);
      }
    }

    final seenBatchIndices = <int>{};
    final Map<int, UserAnimeEntry> toUpsertByIndex = {};
    int addedCount = 0;
    int updatedCount = 0;

    for (final imported in result.entries) {
      final normKey = normalizeAnimeKey(imported.titleRu);
      final existingIdx = indexById[imported.animeId] ??
          (normKey.isNotEmpty ? indexByKey[normKey] : null);

      if (existingIdx != null) {
        final existing = merged[existingIdx];
        final resolvedPoster = (existing.posterUrl != null && existing.posterUrl!.isNotEmpty)
            ? existing.posterUrl
            : imported.posterUrl;
        final resolvedEpisode = imported.lastEpisode > existing.lastEpisode
            ? imported.lastEpisode
            : existing.lastEpisode;
        final updatedEntry = existing.copyWith(
          posterUrl: resolvedPoster,
          status: imported.status,
          lastEpisode: resolvedEpisode,
          episodesTotal: imported.episodesTotal ?? existing.episodesTotal,
          updatedAt: imported.updatedAt,
        );
        merged[existingIdx] = updatedEntry;
        toUpsertByIndex[existingIdx] = updatedEntry;
        if (seenBatchIndices.add(existingIdx)) {
          updatedCount++;
        }
      } else {
        final newIdx = merged.length;
        merged.add(imported);
        indexById[imported.animeId] = newIdx;
        if (normKey.isNotEmpty) {
          indexByKey[normKey] = newIdx;
        }
        toUpsertByIndex[newIdx] = imported;
        seenBatchIndices.add(newIdx);
        addedCount++;
      }
    }

    final toUpsert = toUpsertByIndex.values.toList();

    merged.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _saveLocal(merged);

    final client = _supabase;
    if (client != null && client.auth.currentUser != null && toUpsert.isNotEmpty) {
      await ListsSyncService.upsertEntries(
        client,
        userId: client.auth.currentUser!.id,
        entries: toUpsert,
      );
    }

    return result.copyWith(
      entries: toUpsert,
      addedCount: addedCount,
      updatedCount: updatedCount,
    );
  }

  @override
  Future<AnixartImportResult> importAnixartBackup(
    String jsonContent, {
    required String userId,
  }) async {
    final result = AnixartBackupParser.parse(jsonContent, userId: userId);
    return _mergeAndSaveImportedEntries(result);
  }

  @override
  Future<AnixartImportResult> importAnixartCsvWithShikimori(
    String rawCsv, {
    required String userId,
    AnimeListStatus defaultStatus = AnimeListStatus.planned,
    AnimeListStatus? overrideStatus,
    void Function(int current, int total, String currentTitle)? onProgress,
  }) async {
    final result = await AnixartCsvParser.parseWithShikimori(
      rawCsv,
      userId: userId,
      defaultStatus: defaultStatus,
      overrideStatus: overrideStatus,
      onProgress: onProgress,
    );
    return _mergeAndSaveImportedEntries(result);
  }

  @override
  Future<AnixartImportResult> importAnixartByLoginOrId(
    String loginOrId, {
    required String userId,
  }) async {
    final remoteDataSource = anixartRemoteDataSource ?? AnixartRemoteDataSourceImpl();
    final result = await remoteDataSource.fetchProfileBookmarks(
      loginOrId: loginOrId,
      userId: userId,
    );
    return _mergeAndSaveImportedEntries(result);
  }

  @override
  Future<void> syncWithCloud({required String userId}) async {
    final client = _supabase;
    if (client == null || client.auth.currentUser == null) return;

    try {
      final cloudEntries = await ListsSyncService.fetchEntries(
        client,
        userId: userId,
      );

      final localEntries = await getAllEntries();
      final map = {for (final e in localEntries) e.animeId: e.copyWith(userId: userId)};

      // Слияние: если в облаке новее — берем облако, иначе оставляем локальное
      for (final cloud in cloudEntries) {
        final local = map[cloud.animeId];
        if (local == null || cloud.updatedAt.isAfter(local.updatedAt)) {
          map[cloud.animeId] = cloud;
        }
      }

      final mergedList = map.values.toList();
      await _saveLocal(mergedList);

      // Загружаем объединенные закладки пользователя в облако
      await ListsSyncService.upsertEntries(
        client,
        userId: userId,
        entries: mergedList,
      );
    } catch (e) {
      debugPrint('Cloud sync error: $e');
    }
  }
}
