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
      return deduplicated;
    } catch (_) {
      return [];
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

    // Асинхронное логирование сессии просмотра в Supabase watch_sessions
    try {
      final client = Supabase.instance.client;
      final currentUid = client.auth.currentUser?.id;
      if (currentUid != null && item.titleId > 0 && item.positionMs > 0) {
        final sessionMs = item.positionMs.clamp(0, 14400000);
        client.from('watch_sessions').insert({
          'user_id': currentUid,
          'anime_id': item.titleId,
          'episode': item.episode,
          'watched_ms': sessionMs,
          'watched_at': item.updatedAt.toUtc().toIso8601String(),
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

