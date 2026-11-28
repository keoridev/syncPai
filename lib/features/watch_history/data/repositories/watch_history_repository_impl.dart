import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/anime_poster_resolver.dart';
import '../../domain/entities/watch_history_item.dart';
import '../../domain/repositories/watch_history_repository.dart';

class WatchHistoryRepositoryImpl implements WatchHistoryRepository {
  final SharedPreferences prefs;

  static const String _historyKey = 'syncpai_watch_history';

  WatchHistoryRepositoryImpl(this.prefs);

  @override
  Future<WatchHistoryItem?> getProgress(int titleId) async {
    final list = await getAllHistory();
    try {
      return list.firstWhere((item) => item.titleId == titleId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<WatchHistoryItem>> getAllHistory() async {
    final jsonStr = prefs.getString(_historyKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final decoded = jsonDecode(jsonStr) as List<dynamic>;
      final list = decoded
          .map((e) => WatchHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      // Сортировка: самые свежие сверху
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      // Гарантированная дедупликация: одно аниме = ровно одна карточка в истории
      final deduplicated = <WatchHistoryItem>[];
      final seenIds = <int>{};
      final seenNames = <String>{};
      var dirty = false;

      for (final item in list) {
        final normName = item.titleName.trim().toLowerCase();
        if (seenIds.contains(item.titleId) ||
            (normName.isNotEmpty && seenNames.contains(normName))) {
          dirty = true;
          continue;
        }
        seenIds.add(item.titleId);
        if (normName.isNotEmpty) {
          seenNames.add(normName);
        }

        final isBadPoster =
            AnimePosterResolver.isMissingOrPlaceholder(item.posterUrl) ||
                AnimePosterResolver.isAniLibriaWatermarkedUrl(item.posterUrl);
        if (isBadPoster) {
          final cachedClean = AnimePosterResolver.instance.getCachedSync(
            malId: item.titleId > 0 ? item.titleId : null,
            title: item.titleName,
          );
          final nextPoster = cachedClean ?? '';
          if (nextPoster != item.posterUrl) dirty = true;
          deduplicated.add(item.copyWith(posterUrl: nextPoster));
        } else {
          deduplicated.add(item);
        }
      }
      if (dirty) {
        final encoded =
            jsonEncode(deduplicated.map((e) => e.toJson()).toList());
        await prefs.setString(_historyKey, encoded);
      }
      return await _mergeFromSupabase(deduplicated);
    } catch (_) {
      return [];
    }
  }

  Future<List<WatchHistoryItem>> _mergeFromSupabase(
    List<WatchHistoryItem> local,
  ) async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) return local;

      final rows = await client
          .from('user_anime_lists')
          .select('anime_id, title_ru, poster_url, last_episode, position_ms, updated_at')
          .eq('user_id', uid)
          .gt('position_ms', 0)
          .order('updated_at', ascending: false)
          .limit(30);

      final byId = <int, WatchHistoryItem>{
        for (final item in local) item.titleId: item,
      };
      var changed = false;

      for (final row in rows as List) {
        if (row is! Map) continue;
        final animeId = (row['anime_id'] as num?)?.toInt() ?? 0;
        final posMs = (row['position_ms'] as num?)?.toInt() ?? 0;
        if (animeId <= 0 || posMs < 5000) continue;

        final ep = (row['last_episode'] as num?)?.toInt() ?? 1;
        final titleRu = row['title_ru']?.toString().trim() ?? '';
        final rawPoster = row['poster_url']?.toString() ?? '';
        final isBad = AnimePosterResolver.isMissingOrPlaceholder(rawPoster) ||
            AnimePosterResolver.isAniLibriaWatermarkedUrl(rawPoster);
        final cleanPoster = isBad
            ? (AnimePosterResolver.instance.getCachedSync(
                  malId: animeId,
                  title: titleRu,
                ) ??
                '')
            : rawPoster;
        final remoteUpdated =
            DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
                DateTime.now();

        final existing = byId[animeId];
        if (existing == null ||
            remoteUpdated.isAfter(existing.updatedAt) ||
            (existing.positionMs < 5000 && posMs >= 5000)) {
          byId[animeId] = WatchHistoryItem(
            titleId: animeId,
            titleName: titleRu.isNotEmpty
                ? titleRu
                : (existing?.titleName ?? 'Аниме #$animeId'),
            posterUrl: cleanPoster.isNotEmpty
                ? cleanPoster
                : (existing?.posterUrl ?? ''),
            episode: ep,
            episodeName: existing?.episodeName,
            positionMs: posMs,
            durationMs: existing?.durationMs ?? 1440000,
            updatedAt: remoteUpdated,
          );
          changed = true;
        }
      }

      if (!changed) return local;
      final merged = byId.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final encoded = jsonEncode(merged.map((e) => e.toJson()).toList());
      await prefs.setString(_historyKey, encoded);
      return merged;
    } catch (_) {
      return local;
    }
  }

  @override
  Future<void> saveProgress(WatchHistoryItem item) async {
    final list = await getAllHistory();
    final isBadPoster =
        AnimePosterResolver.isMissingOrPlaceholder(item.posterUrl) ||
            AnimePosterResolver.isAniLibriaWatermarkedUrl(item.posterUrl);
    final sanitizedItem = isBadPoster
        ? item.copyWith(
            posterUrl: AnimePosterResolver.instance.getCachedSync(
                  malId: item.titleId > 0 ? item.titleId : null,
                  title: item.titleName,
                ) ??
                '',
          )
        : item;
    final normName = sanitizedItem.titleName.trim().toLowerCase();
    final updated = List<WatchHistoryItem>.from(list)
      ..removeWhere((e) =>
          e.titleId == sanitizedItem.titleId ||
          (normName.isNotEmpty && e.titleName.trim().toLowerCase() == normName))
      ..insert(0, sanitizedItem);

    // Храним последние 100 тайтлов
    if (updated.length > 100) {
      updated.removeLast();
    }

    final encoded = jsonEncode(updated.map((e) => e.toJson()).toList());
    await prefs.setString(_historyKey, encoded);

    // Асинхронная синхронизация прогресса в Supabase (user_anime_lists + watch_sessions)
    try {
      final client = Supabase.instance.client;
      final currentUid = client.auth.currentUser?.id;
      if (currentUid != null &&
          sanitizedItem.titleId > 0 &&
          sanitizedItem.positionMs >= 5000) {
        final nowIso = sanitizedItem.updatedAt.toUtc().toIso8601String();
        client
            .from('user_anime_lists')
            .update({
              'last_episode': sanitizedItem.episode,
              'position_ms': sanitizedItem.positionMs,
              'updated_at': nowIso,
            })
            .eq('user_id', currentUid)
            .eq('anime_id', sanitizedItem.titleId)
            .then((_) {})
            .catchError((_) {});

        final sessionMs = sanitizedItem.positionMs.clamp(0, 14400000);
        client.from('watch_sessions').insert({
          'user_id': currentUid,
          'anime_id': sanitizedItem.titleId,
          'episode': sanitizedItem.episode,
          'watched_ms': sessionMs,
          'watched_at': nowIso,
        }).then((_) {}).catchError((_) {});
      }
    } catch (_) {}
  }

  @override
  Future<void> removeProgress(int titleId) async {
    final list = await getAllHistory();
    final updated = List<WatchHistoryItem>.from(list)
      ..removeWhere((e) => e.titleId == titleId);

    final encoded = jsonEncode(updated.map((e) => e.toJson()).toList());
    await prefs.setString(_historyKey, encoded);
  }

  @override
  Future<void> updatePosterUrl(int titleId, String posterUrl) async {
    if (titleId <= 0 ||
        AnimePosterResolver.isMissingOrPlaceholder(posterUrl) ||
        AnimePosterResolver.isAniLibriaWatermarkedUrl(posterUrl)) {
      return;
    }
    final list = await getAllHistory();
    var changed = false;
    final updated = list.map((item) {
      if (item.titleId == titleId && item.posterUrl != posterUrl) {
        changed = true;
        return item.copyWith(posterUrl: posterUrl);
      }
      return item;
    }).toList();
    if (changed) {
      final encoded = jsonEncode(updated.map((e) => e.toJson()).toList());
      await prefs.setString(_historyKey, encoded);
    }
  }
}

