import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/anime_review.dart';
import '../utils/review_text_sanitizer.dart';

class JikanAnimeScoreAndReviews {
  final double? malScore;
  final int malVotesCount;
  final List<AnimeReview> reviews;

  const JikanAnimeScoreAndReviews({
    this.malScore,
    this.malVotesCount = 0,
    this.reviews = const [],
  });
}

abstract class JikanRemoteDataSource {
  Future<JikanAnimeScoreAndReviews> getReviewsAndScore(int malId);
}

class JikanRemoteDataSourceImpl implements JikanRemoteDataSource {
  final Dio _dio;

  static const String _baseUrl = 'https://api.jikan.moe/v4';

  // Ограничение частоты запросов к Jikan API: максимум 3 запроса в секунду (~350ms между запросами)
  static DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);

  JikanRemoteDataSourceImpl({Dio? customDio})
      : _dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                headers: {
                  if (!kIsWeb) 'User-Agent': 'SyncPai/1.0.0 (Anime Sync App; contact@syncpai.app)',
                  'Accept': 'application/json',
                },
              ),
            );

  static Future<void> _throttle() async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequestTime).inMilliseconds;
    if (elapsed < 350) {
      await Future.delayed(Duration(milliseconds: 350 - elapsed));
    }
    _lastRequestTime = DateTime.now();
  }

  @override
  Future<JikanAnimeScoreAndReviews> getReviewsAndScore(int malId) async {
    if (malId <= 0) {
      return const JikanAnimeScoreAndReviews();
    }

    double? malScore;
    int malVotesCount = 0;
    final reviews = <AnimeReview>[];

    try {
      await _throttle();

      // 1. Запрос отзывов тайтла
      final response = await _dio.get('/anime/$malId/reviews');
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data['data'] as List?;
        if (data != null) {
          for (final item in data) {
            if (item is! Map) continue;

            final rawText = item['review'] as String? ?? '';
            final sanitized = ReviewTextSanitizer.sanitize(rawText);
            if (sanitized.text.length < 15) continue;

            final user = item['user'] as Map?;
            final username = user?['username'] as String? ?? 'MAL User';
            final images = user?['images'] as Map?;
            final jpg = images?['jpg'] as Map?;
            final avatarUrl = jpg?['image_url'] as String?;

            final rawScore = item['score'];
            final double? score = rawScore != null ? (rawScore as num).toDouble() : null;

            final isSpoiler = (item['is_spoiler'] as bool?) ?? sanitized.containsSpoiler;
            final dateStr = item['date'] as String?;
            final createdAt = dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();

            final url = item['url'] as String?;
            final reactions = item['reactions'] as Map?;
            final overallLikes = (reactions?['overall'] as num?)?.toInt() ?? 0;

            reviews.add(
              AnimeReview(
                id: 'mal_${item['mal_id'] ?? DateTime.now().millisecondsSinceEpoch}',
                source: ReviewSource.mal,
                authorName: username,
                authorAvatarUrl: avatarUrl,
                score: score,
                sentiment: ReviewSentiment.fromScore(score),
                content: sanitized.text,
                containsSpoiler: isSpoiler,
                createdAt: createdAt,
                originalUrl: url,
                likes: overallLikes,
              ),
            );
          }
        }
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        debugPrint('[Jikan API] Rate limit hit (429), backing off gracefully.');
      } else {
        debugPrint('[Jikan API] Reviews fetch failed (graceful): ${e.message}');
      }
    } catch (e) {
      debugPrint('[Jikan API] Unexpected error: $e');
    }

    // 2. Получение общего рейтинга и количества голосов на MyAnimeList
    try {
      await _throttle();
      final statsResponse = await _dio.get('/anime/$malId');
      if (statsResponse.statusCode == 200 && statsResponse.data is Map) {
        final animeData = statsResponse.data['data'] as Map?;
        if (animeData != null) {
          final s = animeData['score'];
          if (s != null) {
            malScore = (s as num).toDouble();
          }
          final scoredBy = animeData['scored_by'];
          if (scoredBy != null) {
            malVotesCount = (scoredBy as num).toInt();
          }
        }
      }
    } catch (_) {
      // Игнорируем ошибку при недоступности отдельного эндпоинта
    }

    return JikanAnimeScoreAndReviews(
      malScore: malScore,
      malVotesCount: malVotesCount,
      reviews: reviews,
    );
  }
}
