import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/entities/user_anime_entry.dart';

/// Сервис синхронизации пользовательских списков аниме с таблицей `public.user_anime_lists`.
/// Использует точную схему колонок БД (`user_id`, `anime_id`, `anime_title`, `poster_url`,
/// `category`, `episodes_watched`, `updated_at`) и безопасно обрабатывает PGRST204/PGRST205.
class ListsSyncService {
  ListsSyncService._();

  static bool _tableUnavailable = false;

  static Map<String, dynamic> toSupabaseRow(
    UserAnimeEntry entry, {
    required String userId,
    double? score,
  }) {
    return {
      'user_id': userId,
      'anime_id': entry.animeId,
      'anime_title': entry.titleRu,
      'poster_url': entry.posterUrl,
      'category': entry.status.name,
      'episodes_watched': entry.lastEpisode,
      'total_episodes': entry.episodesTotal,
      'score': score,
      'updated_at': entry.updatedAt.toIso8601String(),
    };
  }

  static Future<void> upsertEntry(
    SupabaseClient client, {
    required String userId,
    required UserAnimeEntry entry,
  }) async {
    if (_tableUnavailable) return;
    try {
      await client
          .from('user_anime_lists')
          .upsert(toSupabaseRow(entry, userId: userId), onConflict: 'user_id, anime_id');
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') {
        _tableUnavailable = true;
      }
      debugPrint('[ListsSyncService] Postgrest upsert skipped (${e.code}): ${e.message}');
    } catch (e) {
      debugPrint('[ListsSyncService] Upsert skipped: $e');
    }
  }

  static Future<void> upsertEntries(
    SupabaseClient client, {
    required String userId,
    required List<UserAnimeEntry> entries,
  }) async {
    if (_tableUnavailable || entries.isEmpty) return;
    try {
      final payload = entries
          .map((e) => toSupabaseRow(e, userId: userId))
          .toList();
      await client
          .from('user_anime_lists')
          .upsert(payload, onConflict: 'user_id, anime_id');
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') {
        _tableUnavailable = true;
      }
      debugPrint('[ListsSyncService] Postgrest bulk upsert skipped (${e.code}): ${e.message}');
    } catch (e) {
      debugPrint('[ListsSyncService] Bulk upsert skipped: $e');
    }
  }

  static Future<List<UserAnimeEntry>> fetchEntries(
    SupabaseClient client, {
    required String userId,
  }) async {
    if (_tableUnavailable) return const [];
    try {
      final List<dynamic> response = await client
          .from('user_anime_lists')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);
      return response
          .map((item) => UserAnimeEntry.fromJson(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') {
        _tableUnavailable = true;
      }
      debugPrint('[ListsSyncService] Postgrest fetch skipped (${e.code}): ${e.message}');
      return const [];
    } catch (e) {
      debugPrint('[ListsSyncService] Fetch skipped: $e');
      return const [];
    }
  }
}

