import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/anime_review.dart';

abstract class SyncPaiReviewsDataSource {
  Future<List<AnimeReview>> getReviews(String animeKey);
  Future<AnimeReview> submitReview({
    required String animeKey,
    required String userId,
    required String userName,
    String? userAvatar,
    required double score,
    required String content,
    required bool containsSpoiler,
  });
}

class SyncPaiReviewsDataSourceImpl implements SyncPaiReviewsDataSource {
  static const String _localPrefix = 'syncpai_local_reviews_';
  final SharedPreferences? _prefs;

  SyncPaiReviewsDataSourceImpl([this._prefs]);

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<AnimeReview>> getReviews(String animeKey) async {
    final list = <AnimeReview>[];
    final seenIds = <String>{};

    // 1. Пытаемся получить отзывы из облака Supabase (таблица anime_reviews)
    final client = _supabase;
    if (client != null) {
      try {
        final parsedAnimeId = int.tryParse(animeKey.replaceAll(RegExp(r'[^0-9]'), ''));
        if (parsedAnimeId != null && parsedAnimeId > 0) {
          dynamic response;
          try {
            response = await client
                .from('anime_reviews')
                .select('*, profiles:user_id(username, avatar_url)')
                .eq('anime_id', parsedAnimeId)
                .order('created_at', ascending: false)
                .limit(50);
          } catch (_) {
            // Fallback на простой select без foreign key
            response = await client
                .from('anime_reviews')
                .select()
                .eq('anime_id', parsedAnimeId)
                .order('created_at', ascending: false)
                .limit(50);
          }

          if (response is Iterable) {
            for (final item in response) {
              if (item is! Map) continue;
              final row = item.cast<String, dynamic>();
              final review = fromSupabaseRow(row);
              seenIds.add(review.id);
              list.add(review);
            }
          }
        }
      } catch (e) {
        debugPrint('[SyncPaiReviews] Supabase fetch error (fallback to local): $e');
      }
    }

    // 2. Дополняем локальными отзывами из SharedPreferences
    final prefs = _prefs;
    if (prefs != null) {
      try {
        final localRaw = prefs.getString('$_localPrefix$animeKey');
        if (localRaw != null && localRaw.isNotEmpty) {
          final decoded = jsonDecode(localRaw) as List;
          for (final item in decoded) {
            if (item is! Map<String, dynamic>) continue;
            final rev = AnimeReview.fromJson(item);
            if (!seenIds.contains(rev.id)) {
              seenIds.add(rev.id);
              list.insert(0, rev); // локальные только что созданные в начало
            }
          }
        }
      } catch (e) {
        debugPrint('[SyncPaiReviews] Local storage read error: $e');
      }
    }

    return list;
  }

  @override
  Future<AnimeReview> submitReview({
    required String animeKey,
    required String userId,
    required String userName,
    String? userAvatar,
    required double score,
    required String content,
    required bool containsSpoiler,
  }) async {
    final now = DateTime.now();
    final reviewId = 'sync_${now.millisecondsSinceEpoch}_${userId.hashCode.abs() % 10000}';

    final review = AnimeReview(
      id: reviewId,
      source: ReviewSource.syncpai,
      authorName: userName,
      authorAvatarUrl: userAvatar,
      score: score,
      sentiment: ReviewSentiment.fromScore(score),
      content: content.trim(),
      containsSpoiler: containsSpoiler,
      createdAt: now,
      likes: 1,
    );

    // 1. Всегда надежно сохраняем локально в SharedPreferences
    final prefs = _prefs;
    if (prefs != null) {
      try {
        final existingRaw = prefs.getString('$_localPrefix$animeKey');
        final List<dynamic> localList = existingRaw != null ? jsonDecode(existingRaw) as List : [];
        localList.insert(0, review.toJson());
        await prefs.setString('$_localPrefix$animeKey', jsonEncode(localList));
      } catch (e) {
        debugPrint('[SyncPaiReviews] Failed to save local review: $e');
      }
    }

    // 2. Отправляем в Supabase
    final client = _supabase;
    if (client != null) {
      try {
        final currentUserId = client.auth.currentUser?.id;
        final effectiveUserId = currentUserId ?? (userId.startsWith('guest_') ? null : userId);
        final parsedAnimeId = int.tryParse(animeKey.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

        if (effectiveUserId != null && parsedAnimeId > 0) {
          final intScore = score.round().clamp(1, 10);
          final trimmedContent = content.trim();
          if (trimmedContent.length >= 3) {
            final row = toSupabaseRow(
              animeId: parsedAnimeId,
              userId: effectiveUserId,
              authorName: userName,
              authorAvatar: userAvatar,
              rating: intScore,
              comment: trimmedContent,
              likesCount: 1,
              createdAt: now,
            );
            try {
              await client.from('anime_reviews').upsert(row);
            } on PostgrestException catch (e) {
              if (e.code == 'PGRST204') {
                // Fallback для legacy-схемы (score/content/contains_spoiler)
                await client.from('anime_reviews').upsert({
                  'user_id': effectiveUserId,
                  'anime_id': parsedAnimeId,
                  'score': intScore,
                  'content': trimmedContent,
                  'contains_spoiler': containsSpoiler,
                  'created_at': now.toUtc().toIso8601String(),
                });
              } else {
                rethrow;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[SyncPaiReviews] Supabase insert warning (offline/schema fallback): $e');
      }
    }

    return review;
  }

  static Map<String, dynamic> toSupabaseRow({
    required int animeId,
    required String userId,
    required String authorName,
    String? authorAvatar,
    required int rating,
    required String comment,
    int likesCount = 1,
    required DateTime createdAt,
  }) {
    return {
      'anime_id': animeId,
      'user_id': userId,
      'author_name': authorName,
      'author_avatar': authorAvatar,
      'rating': rating,
      'comment': comment,
      'likes_count': likesCount,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  static AnimeReview fromSupabaseRow(Map<String, dynamic> row) {
    final id = 'sync_${row['id']}';
    final profileMap = row['profiles'] is Map ? (row['profiles'] as Map) : null;
    final authorName = (row['author_name'] as String?) ??
        (profileMap?['username'] as String?) ??
        (row['user_name'] as String?) ??
        'Зритель SyncPai';
    final authorAvatarUrl = (row['author_avatar'] as String?) ??
        (profileMap?['avatar_url'] as String?) ??
        (row['user_avatar'] as String?);

    final rawRating = row['rating'] ?? row['score'];
    final parsedScore = rawRating is num
        ? rawRating.toDouble()
        : double.tryParse('${rawRating ?? ''}');
    final comment = (row['comment'] as String?) ?? (row['content'] as String?) ?? '';
    final likesRaw = row['likes_count'] ?? row['likes'];
    final likesCount = likesRaw is num ? likesRaw.toInt() : 1;
    final createdAt = row['created_at'] != null
        ? DateTime.tryParse('${row['created_at']}') ?? DateTime.now()
        : DateTime.now();

    return AnimeReview(
      id: id,
      source: ReviewSource.syncpai,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      score: parsedScore,
      sentiment: ReviewSentiment.fromScore(parsedScore),
      content: comment,
      containsSpoiler: row['contains_spoiler'] as bool? ?? false,
      createdAt: createdAt,
      likes: likesCount,
    );
  }
}
