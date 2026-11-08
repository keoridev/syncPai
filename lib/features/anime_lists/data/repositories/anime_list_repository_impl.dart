import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../datasources/anixart_backup_parser.dart';
import '../datasources/anixart_csv_parser.dart';
import '../datasources/anixart_remote_datasource.dart';
import '../../domain/entities/user_anime_entry.dart';
import '../../domain/repositories/anime_list_repository.dart';

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

    // Фоновая синхронизация с Supabase
    final client = _supabase;
    if (client != null && client.auth.currentUser != null) {
      try {
        await client.from('user_anime_lists').upsert({
          'user_id': client.auth.currentUser!.id,
          'anime_id': entry.animeId,
          'title_ru': entry.titleRu,
          'poster_url': entry.posterUrl,
          'status': entry.status.name,
          'last_episode': entry.lastEpisode,
          'position_ms': entry.positionMs,
          'episodes_total': entry.episodesTotal,
          'updated_at': entry.updatedAt.toIso8601String(),
        }, onConflict: 'user_id, anime_id');
      } catch (e) {
        debugPrint('Supabase upsert error: $e');
      }
    }
  }

  @override
  Future<void> removeEntry(int animeId) async {
    final all = await getAllEntries();
    all.removeWhere((e) => e.animeId == animeId);
    await _saveLocal(all);

    final client = _supabase;
    if (client != null && client.auth.currentUser != null) {
      try {
        await client
            .from('user_anime_lists')
            .delete()
            .eq('user_id', client.auth.currentUser!.id)
            .eq('anime_id', animeId);
      } catch (e) {
        debugPrint('Supabase delete error: $e');
      }
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

  @override
  Future<AnixartImportResult> importAnixartBackup(
    String jsonContent, {
    required String userId,
  }) async {
    final result = AnixartBackupParser.parse(jsonContent, userId: userId);

    final current = await getAllEntries();
    final map = {for (final e in current) e.animeId: e};

    // Объединяем, не затирая более свежие изменения
    for (final imported in result.entries) {
      map[imported.animeId] = imported;
    }

    final merged = map.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _saveLocal(merged);

    // Пачковая отправка в облако
    final client = _supabase;
    if (client != null && client.auth.currentUser != null) {
      try {
        final payload = result.entries.map((e) => {
              'user_id': client.auth.currentUser!.id,
              'anime_id': e.animeId,
              'title_ru': e.titleRu,
              'poster_url': e.posterUrl,
              'status': e.status.name,
              'last_episode': e.lastEpisode,
              'position_ms': e.positionMs,
              'episodes_total': e.episodesTotal,
              'updated_at': e.updatedAt.toIso8601String(),
            }).toList();

        await client.from('user_anime_lists').upsert(
              payload,
              onConflict: 'user_id, anime_id',
            );
      } catch (e) {
        debugPrint('Cloud bulk import error: $e');
      }
    }

    return result;
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

    final current = await getAllEntries();
    final map = {for (final e in current) e.animeId: e};

    for (final imported in result.entries) {
      map[imported.animeId] = imported;
    }

    final merged = map.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _saveLocal(merged);

    // Пачковый UPSERT в таблицу Supabase
    final client = _supabase;
    if (client != null && client.auth.currentUser != null) {
      try {
        final payload = result.entries.map((e) => {
              'user_id': client.auth.currentUser!.id,
              'anime_id': e.animeId,
              'shikimori_id': e.animeId,
              'title_ru': e.titleRu,
              'poster_url': e.posterUrl,
              'status': e.status.name,
              'last_episode': e.lastEpisode,
              'position_ms': e.positionMs,
              'episodes_total': e.episodesTotal,
              'updated_at': e.updatedAt.toIso8601String(),
            }).toList();

        await client.from('user_anime_lists').upsert(
              payload,
              onConflict: 'user_id, anime_id',
            );
      } catch (e) {
        debugPrint('Cloud bulk UPSERT error: $e');
      }
    }

    return result;
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

    final current = await getAllEntries();
    final map = {for (final e in current) e.animeId: e};

    for (final imported in result.entries) {
      map[imported.animeId] = imported;
    }

    final merged = map.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _saveLocal(merged);

    // Синхронизация с облаком Supabase
    final client = _supabase;
    if (client != null && client.auth.currentUser != null) {
      try {
        final payload = result.entries.map((e) => {
              'user_id': client.auth.currentUser!.id,
              'anime_id': e.animeId,
              'title_ru': e.titleRu,
              'poster_url': e.posterUrl,
              'status': e.status.name,
              'last_episode': e.lastEpisode,
              'position_ms': e.positionMs,
              'episodes_total': e.episodesTotal,
              'updated_at': e.updatedAt.toIso8601String(),
            }).toList();

        await client.from('user_anime_lists').upsert(
              payload,
              onConflict: 'user_id, anime_id',
            );
      } catch (e) {
        debugPrint('Cloud bulk import error: $e');
      }
    }

    return result;
  }

  @override
  Future<void> syncWithCloud({required String userId}) async {
    final client = _supabase;
    if (client == null || client.auth.currentUser == null) return;

    try {
      final List<dynamic> response = await client
          .from('user_anime_lists')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      final cloudEntries = response
          .map((item) => UserAnimeEntry.fromJson(item as Map<String, dynamic>))
          .toList();

      final localEntries = await getAllEntries();
      final map = {for (final e in localEntries) e.animeId: e};

      // Слияние: если в облаке новее — берем облако, иначе оставляем локальное
      for (final cloud in cloudEntries) {
        final local = map[cloud.animeId];
        if (local == null || cloud.updatedAt.isAfter(local.updatedAt)) {
          map[cloud.animeId] = cloud;
        }
      }

      await _saveLocal(map.values.toList());

      // Загружаем объединенные закладки пользователя в облако
      if (map.isNotEmpty) {
        final payload = map.values.map((e) => {
              'user_id': userId,
              'anime_id': e.animeId,
              'title_ru': e.titleRu,
              'poster_url': e.posterUrl,
              'status': e.status.name,
              'last_episode': e.lastEpisode,
              'position_ms': e.positionMs,
              'episodes_total': e.episodesTotal,
              'updated_at': e.updatedAt.toIso8601String(),
            }).toList();

        await client.from('user_anime_lists').upsert(
              payload,
              onConflict: 'user_id, anime_id',
            );
      }
    } catch (e) {
      debugPrint('Cloud sync error: $e');
    }
  }
}
